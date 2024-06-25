defmodule Fireside.Util.Install do
  def install(component) do
    Mix.shell().info("Installing #{component}")

    {_component_name, [path: component_path]} = determine_dep_type_and_version(component)

    if not File.dir?(component_path) do
      raise "directory `#{component_path} doesn't exist"
    end

    fireside_config_path = Path.join(component_path, "/.fireside.exs")

    if not File.exists?(fireside_config_path) do
      raise "#{component_path} is not a Fireside component"
    end

    fireside_opts = eval_file_with_keyword_list(fireside_config_path)

    Keyword.validate!(fireside_opts, [:includes, :overwritable])

    {fireside_includes, _fireside_opts} = Keyword.pop!(fireside_opts, :includes)

    igniter =
      for include_glob <- fireside_includes, reduce: Igniter.new() do
        igniter ->
          Path.join(component_path, include_glob)
          |> GlobEx.compile!()
          |> GlobEx.ls()
          |> Enum.reduce(igniter, fn file_path, igniter ->
            contents = File.read!(file_path)

            quoted = Sourceror.parse_string!(contents)

            {:defmodule, _defmodule_meta,
             [{:__aliases__, _aliases_meta, [prefix | _suffix]} | _rest]} = quoted

            app_name_atom =
              Igniter.Code.Module.module_name_prefix()
              |> Module.split()
              |> List.first()
              |> String.to_atom()

            patched_quoted =
              quoted
              |> Macro.prewalk(fn
                {:__aliases__, aliases_meta, [^prefix]} ->
                  {:__aliases__, aliases_meta, [app_name_atom]}

                {:__aliases__, aliases_meta, [^prefix | rest]} ->
                  {:__aliases__, aliases_meta, [app_name_atom | rest]}

                quoted ->
                  quoted
              end)

            {:defmodule, _defmodule_meta,
             [{:__aliases__, _aliases_meta, new_module_name} | _rest]} =
              patched_quoted

            Igniter.create_new_elixir_file(
              igniter,
              Igniter.Code.Module.proper_location(Module.concat(new_module_name)),
              Sourceror.to_string(patched_quoted)
            )
          end)
      end

    Igniter.do_or_dry_run(igniter, ["--dry-run"])
  end

  defp determine_dep_type_and_version(requirement) do
    case String.split(requirement, "@", trim: true) do
      [_package] ->
        raise "only @path components are currently supported"

      [package, version] ->
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
            {package, requirement}
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
