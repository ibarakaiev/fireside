defmodule Fireside.Util.Install do
  def install(component) do
    Mix.shell().info("Installing #{component}")

    {component_name, [path: component_path]} = determine_component_type_and_version(component)

    if not File.dir?(component_path) do
      raise "directory `#{component_path}` doesn't exist"
    end

    fireside_module_path = Path.join(component_path, "/fireside.exs")

    if not File.exists?(fireside_module_path) do
      raise "#{component_path} is not a Fireside component, aborting."
    end

    fireside_module = load_module(fireside_module_path)

    expanded_fireside_includes =
      expand_fireside_includes(component_path, fireside_module.config())

    Igniter.new()
    |> install_dependencies(component_path)
    |> install_code(expanded_fireside_includes)
    |> fireside_module.setup()
    |> replace_component_name(fireside_module)
    |> add_fireside_lock(component_name)
    |> Igniter.do_or_dry_run([])

    :ok
  end

  defp load_module(path) do
    Code.require_file(path)

    {:defmodule, _defmodule_meta, [{:__aliases__, _aliases_meta, module_name} | _rest]} =
      path
      |> File.read!()
      |> Sourceror.parse_string!()

    Module.concat(module_name)
  end

  defp expand_fireside_includes(component_path, fireside_config) do
    for kind <- [:lib, :tests, :test_supports], reduce: %{} do
      expanded_includes ->
        includes = fireside_config[kind]

        expanded_paths =
          for glob <- includes, reduce: [] do
            expanded_paths ->
              expanded_paths ++
                (Path.join(component_path, glob)
                 |> GlobEx.compile!()
                 |> GlobEx.ls())
          end

        Map.merge(expanded_includes, %{kind => expanded_paths})
    end
  end

  defp install_dependencies(igniter, component_path) do
    mix_file = Path.join(component_path, "mix.exs")

    unless File.exists?(mix_file) do
      raise "mix.exs not found in the component directory"
    end

    {deps, _} =
      mix_file
      |> File.read!()
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()
      |> Igniter.Code.Function.move_to_defp(:deps, 0)
      |> then(fn {:ok, zipper} ->
        case Igniter.Code.Common.move_right(zipper, &Igniter.Code.List.list?/1) do
          {:ok, zipper} ->
            zipper

          :error ->
            {:error, "deps/0 doesn't return a list"}
        end
      end)
      |> Sourceror.Zipper.node()
      |> Code.eval_quoted()

    desired_tasks =
      deps
      |> Enum.reject(&(elem(&1, 0) == :igniter))
      |> Enum.map(&"#{elem(&1, 0)}.install")

    igniter =
      Enum.reduce(deps, igniter, fn dep, igniter ->
        {name, version, opts} =
          case dep do
            {_name, _version, _opts} = dep -> dep
            {name, version} -> {name, version, []}
          end

        Igniter.Project.Deps.add_dep(igniter, {name, version}, opts ++ [append?: true])
      end)

    igniter = Igniter.apply_and_fetch_dependencies(igniter, error_on_abort?: true)

    desired_tasks
    |> Enum.map(&Mix.Task.get/1)
    |> Enum.filter(& &1)
    |> Enum.reduce(igniter, fn task, igniter ->
      Igniter.compose_task(igniter, task, [])
    end)
  end

  defp install_code(igniter, expanded_fireside_includes) do
    for kind <- [:lib, :tests, :test_supports], reduce: igniter do
      igniter ->
        for path <- expanded_fireside_includes[kind], reduce: igniter do
          igniter ->
            import_to_project(igniter, path, kind)
        end
    end
  end

  defp replace_component_name(igniter, fireside_module) do
    igniter = Igniter.include_glob(igniter, "{lib,test}/**/*.{ex,exs}")

    fireside_module_prefix = fireside_module |> Module.split() |> List.first() |> String.to_atom()
    new_app_prefix = Mix.Project.get!() |> Module.split() |> List.first() |> String.to_atom()

    for source <- Rewrite.sources(igniter.rewrite),
        reduce: igniter do
      igniter ->
        new_quoted =
          source
          |> Rewrite.Source.get(:quoted)
          |> replace_module_prefix_from_to(fireside_module_prefix, new_app_prefix)

        new_source =
          Rewrite.Source.update(
            source,
            :quoted,
            new_quoted
          )

        %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}
    end
  end

  defp add_fireside_lock(igniter, component_name) do
    igniter =
      for source <- Rewrite.sources(igniter.rewrite),
          Rewrite.Source.get(source, :path) in igniter.assigns.imported_paths,
          reduce: igniter do
        igniter ->
          {new_quoted, hash} =
            source
            |> Rewrite.Source.get(:quoted)
            |> compute_and_include_hash(component_name)

          new_source =
            Rewrite.Source.update(
              source,
              :quoted,
              new_quoted
            )

          path = Rewrite.Source.get(source, :path)

          %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}
          |> Igniter.update_assign(:hashes, %{path => hash}, fn hashes ->
            Map.merge(hashes, %{path => hash})
          end)
      end

    aggregate_hash =
      :crypto.hash(
        :sha,
        igniter.assigns.hashes
        |> Enum.map(& &1)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {_path, hash} -> hash end)
        |> Enum.join("")
      )
      |> Base.encode16()

    component_lock = %{
      hash: aggregate_hash,
      files: igniter.assigns.hashes
    }

    Igniter.Project.Config.configure_new(
      igniter,
      "fireside.exs",
      Igniter.Project.Application.app_name(),
      [Fireside, String.to_atom(component_name)],
      component_lock
    )
  end

  defp import_to_project(igniter, file_path, kind) do
    ast =
      file_path
      |> File.read!()
      |> Sourceror.parse_string!()

    module_name = get_module_name(ast)

    proper_location =
      case kind do
        :lib ->
          Igniter.Code.Module.proper_location(module_name)

        :tests ->
          Igniter.Code.Module.proper_test_location(module_name)

        :test_supports ->
          Igniter.Code.Module.proper_test_support_location(module_name)
      end

    Igniter.create_new_elixir_file(
      igniter,
      proper_location,
      Sourceror.to_string(ast)
    )
    |> Igniter.update_assign(:imported_paths, [proper_location], fn imported_paths ->
      imported_paths ++ [proper_location]
    end)
  end

  defp replace_module_prefix_from_to(ast, old_prefix, new_prefix) do
    ast
    |> Macro.prewalk(fn
      {:__aliases__, aliases_meta, [^old_prefix | rest]} ->
        {:__aliases__, aliases_meta, [new_prefix | rest]}

      node ->
        node
    end)
  end

  defp compute_and_include_hash(ast, component_name) do
    hash = :crypto.hash(:sha, Sourceror.to_string(ast)) |> Base.encode16()

    {Sourceror.prepend_comments(
       ast,
       [
         %{
           line: 1,
           previous_eol_count: 1,
           next_eol_count: 1,
           text: "#! fireside:#{hash}"
         },
         %{
           line: 1,
           previous_eol_count: 1,
           next_eol_count: 1,
           text:
             "#! DO NOT EDIT this file. Run `mix fireside.unlock #{component_name}` if you want to stop syncing."
         }
       ],
       :leading
     ), hash}
  end

  defp get_module_name(quoted) do
    {:defmodule, _defmodule_meta, [{:__aliases__, _aliases_meta, module_name} | _rest]} =
      quoted

    Module.concat(module_name)
  end

  defp determine_component_type_and_version(requirement) do
    case String.split(requirement, "@", trim: true) do
      [_component] ->
        raise "only @path components are currently supported"

      [component, version] ->
        case version do
          "git:" <> _requirement ->
            raise "@git components are not yet supported"

          "github:" <> _requirement ->
            raise "@github components are not yet supported"

          "path:" <> requirement ->
            [path: requirement]

          _version ->
            raise "only @path components are currently supported"
        end
        |> case do
          :error ->
            :error

          requirement ->
            {component, requirement}
        end
    end
  end
end
