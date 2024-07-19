defmodule Fireside.Util.Install do
  @moduledoc false

  def install(component) do
    Fireside.ensure_clean_git!()

    igniter = Igniter.new()

    {component_name, [path: component_path]} = determine_component_type_and_version(component)

    if Igniter.Project.Config.configures_key?(
         igniter,
         "fireside.exs",
         Igniter.Project.Application.app_name(),
         [Fireside, component_name]
       ) do
      raise "#{component_name} is already installed. Use `fireside.update #{component_name}` to update it instead."
    end

    Mix.shell().info("Installing #{component}...")

    if not File.dir?(component_path) do
      raise "directory `#{component_path}` doesn't exist"
    end

    fireside_module_path = Path.join(component_path, "/fireside.exs")

    if not File.exists?(fireside_module_path) do
      raise "#{component_path} is not a Fireside component, aborting."
    end

    fireside_module = Fireside.load_module(fireside_module_path)
    fireside_module_prefix = fireside_module |> Module.split() |> List.first() |> String.to_atom()
    project_prefix = Mix.Project.get!() |> Module.split() |> List.first() |> String.to_atom()

    expanded_fireside_includes =
      Fireside.expand_fireside_includes(component_path, fireside_module.config())

    igniter
    |> install_dependencies(component_path)
    |> Igniter.assign(:overwritable_paths, [])
    |> install_code(
      expanded_fireside_includes,
      fireside_module_prefix,
      project_prefix,
      expanded_fireside_includes[:overwritable]
    )
    |> fireside_module.setup()
    |> replace_component_name(fireside_module_prefix, project_prefix)
    |> Fireside.add_or_replace_fireside_lock(
      component_name,
      component_path
    )
    |> Igniter.do_or_dry_run([])

    :ok
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

    deps
    |> Enum.reject(&(elem(&1, 0) == :igniter))
    |> Igniter.Util.Install.install([], igniter, append?: true)

    Igniter.new()
  end

  defp install_code(
         igniter,
         expanded_fireside_includes,
         fireside_module_prefix,
         project_prefix,
         overwritable_paths
       ) do
    for kind <- [:lib, :tests, :test_supports], reduce: igniter do
      igniter ->
        for path <- expanded_fireside_includes[kind], reduce: igniter do
          igniter ->
            import_to_project(
              igniter,
              path,
              kind,
              fireside_module_prefix,
              project_prefix,
              overwritable_paths
            )
        end
    end
  end

  # the setup() hook might introduce additional references to the Fireside module prefix,
  # so this needs to be done again
  defp replace_component_name(igniter, fireside_module_prefix, project_prefix) do
    igniter = Igniter.include_all_elixir_files(igniter)

    for source <- Rewrite.sources(igniter.rewrite),
        reduce: igniter do
      igniter ->
        new_quoted =
          source
          |> Rewrite.Source.get(:quoted)
          |> replace_module_prefix_from_to(fireside_module_prefix, project_prefix)

        new_source =
          Rewrite.Source.update(
            source,
            :quoted,
            new_quoted
          )

        %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}
    end
  end

  def import_to_project(
        igniter,
        file_path,
        kind,
        fireside_module_prefix,
        project_prefix,
        overwritable_paths
      ) do
    ast =
      file_path
      |> File.read!()
      |> Sourceror.parse_string!()
      |> replace_module_prefix_from_to(fireside_module_prefix, project_prefix)

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

    if Igniter.exists?(igniter, proper_location) and
         proper_location not in (igniter.assigns[:fireside_managed_files] || []) do
      raise "Conflicting file #{proper_location} already exists, aborting."
    end

    igniter
    |> Igniter.create_or_update_elixir_file(
      proper_location,
      Sourceror.to_string(ast),
      fn _zipper ->
        Sourceror.Zipper.zip(ast)
      end
    )
    |> Igniter.update_assign(:imported_paths, [proper_location], fn imported_paths ->
      imported_paths ++ [proper_location]
    end)
    |> then(fn igniter ->
      if file_path in overwritable_paths do
        Igniter.update_assign(
          igniter,
          :overwritable_paths,
          [proper_location],
          fn overwritable_paths -> overwritable_paths ++ [proper_location] end
        )
      else
        igniter
      end
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
            {String.to_atom(component), requirement}
        end
    end
  end
end
