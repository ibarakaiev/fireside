defmodule Fireside.Util.Install do
  def install(component) do
    Mix.shell().info("Installing #{component}")

    {component_name, [path: component_path]} = determine_component_type_and_version(component)

    if not File.dir?(component_path) do
      raise "directory `#{component_path}` doesn't exist"
    end

    fireside_config_path = Path.join(component_path, "/.fireside.exs")

    if not File.exists?(fireside_config_path) do
      raise "#{component_path} is not a Fireside component, aborting."
    end

    fireside_config = eval_file_with_keyword_list(fireside_config_path)

    # TODO: implement overwritable functionality
    Keyword.validate!(fireside_config, [:lib, :overwritable, :tests, :test_supports])

    Igniter.new()
    |> install_dependencies(component_path)
    |> install_source_code(component_name, component_path, fireside_config)
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
      |> Igniter.Code.Module.move_to_defp(:deps, 0)
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

    desired_tasks = Enum.map(deps, &"#{elem(&1, 0)}.install")

    igniter =
      Enum.reduce(deps, igniter, fn dep, igniter ->
        {name, version, opts} =
          case dep do
            {_name, _version, _opts} = dep -> dep
            {name, version} -> {name, version, []}
          end

        Igniter.Project.Deps.add_dependency(igniter, name, version, opts)
      end)

    igniter = Igniter.apply_and_fetch_dependencies(igniter, error_on_abort?: true)

    igniter_tasks =
      Mix.Task.load_all()
      |> Stream.map(fn item ->
        Code.ensure_compiled!(item)
        item
      end)
      |> Stream.filter(&Igniter.Util.Install.implements_behaviour?(&1, Igniter.Mix.Task))
      |> Enum.filter(&(Mix.Task.task_name(&1) in desired_tasks))
      |> Enum.sort_by(
        &Enum.find_index(desired_tasks, fn e -> e == Mix.Task.task_name(&1) end),
        &<=/2
      )

    title =
      case desired_tasks do
        [task] ->
          "Final result of installer: `#{task}`"

        tasks ->
          "Final result of installers: #{Enum.map_join(tasks, ", ", &"`#{&1}`")}"
      end

    igniter_tasks
    |> Enum.reduce(igniter, fn task, igniter ->
      Igniter.compose_task(igniter, task, [])
    end)
    |> Igniter.do_or_dry_run(title: title)
  end

  defp install_source_code(igniter, component_name, component_path, fireside_config) do
    %{igniter: igniter, lock: lock} =
      for kind <- [:lib, :tests, :test_supports], reduce: %{igniter: Igniter.new(), lock: []} do
        %{igniter: igniter, lock: lock} ->
          {includes, _opts} = Keyword.pop!(fireside_config, kind)

          for glob <- includes, reduce: %{igniter: igniter, lock: lock} do
            %{igniter: igniter, lock: lock} ->
              file_paths =
                Path.join(component_path, glob)
                |> GlobEx.compile!()
                |> GlobEx.ls()

              for file_path <- file_paths, reduce: %{igniter: igniter, lock: lock} do
                %{igniter: igniter, lock: lock} ->
                  {ast, hash} = prepare_ast_with_hash(file_path, component_name)

                  {igniter, path} = import_to_project(igniter, ast, kind)

                  %{
                    igniter: igniter,
                    lock: lock ++ [%{path: path, hash: hash}]
                  }
              end
          end
      end

    igniter = Igniter.create_new_elixir_file(igniter, "config/fireside.exs", transform_lock(lock))
  end

  defp transform_lock(lock) do
    hash =
      :crypto.hash(:sha, Enum.sort(lock) |> Enum.map(& &1.hash) |> Enum.join(""))
      |> Base.encode16()

    # TODO: or update
    quote do
      %{
        shopifex: %{
          hash: unquote(hash),
          files: unquote(lock)
        }
      }
    end
    |> Macro.to_string()
  end

  def add_dependencies(igniter, component_path) do
    mix_file = Path.join(component_path, "mix.exs")

    unless File.exists?(mix_file) do
      raise "mix.exs not found in the component directory"
    end

    {deps, _} =
      mix_file
      |> File.read!()
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()
      |> Igniter.Code.Module.move_to_defp(:deps, 0)
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

    {Enum.reduce(deps, igniter, fn dep, igniter ->
       {name, version, opts} =
         case dep do
           {_name, _version, _opts} = dep -> dep
           {name, version} -> {name, version, []}
         end

       Igniter.Project.Deps.add_dependency(igniter, name, version, opts)
     end), deps}
  end

  defp prepare_ast_with_hash(file_path, component_name) do
    file_path
    |> File.read!()
    |> Sourceror.parse_string!()
    |> replace_module_prefix_to_mix_project_name()
    |> compute_and_include_hash(component_name)
  end

  defp import_to_project(igniter, ast, kind) do
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

    {Igniter.create_new_elixir_file(
       igniter,
       proper_location,
       Sourceror.to_string(ast)
     ), proper_location}
  end

  defp replace_module_prefix_to_mix_project_name(ast) do
    app_name_atom = Mix.Project.get!() |> Module.split() |> List.first() |> String.to_atom()

    {:defmodule, _defmodule_meta, [{:__aliases__, _aliases_meta, [prefix | _suffix]} | _rest]} =
      ast

    ast
    |> Macro.prewalk(fn
      {:__aliases__, aliases_meta, [^prefix | rest]} ->
        {:__aliases__, aliases_meta, [app_name_atom | rest]}

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

  # borrowed from mix format
  defp eval_file_with_keyword_list(path) do
    {opts, _} = Code.eval_file(path)

    unless Keyword.keyword?(opts) do
      Mix.raise("Expected #{inspect(path)} to return a keyword list, got: #{inspect(opts)}")
    end

    opts
  end
end
