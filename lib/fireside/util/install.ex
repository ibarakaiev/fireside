defmodule Fireside.Util.Install do
  def install(component) do
    IO.puts("Installing #{component}")

    {component_name, [path: component_path]} = determine_dep_type_and_version(component)

    if not File.dir?(component_path) do
      raise "directory `#{component_path} doesn't exist"
    end

    fireside_config_path = Path.join(component_path, "/.fireside.exs")

    if not File.exists?(fireside_config_path) do
      raise "#{component_path} is not a Fireside component"
    end

    fireside_opts = eval_file_with_keyword_list(fireside_config_path)

    IO.inspect(fireside_opts)
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
