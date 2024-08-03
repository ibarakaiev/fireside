defmodule Fireside.Helpers do
  @moduledoc false
  def expand_fireside_component_globs(fireside_component_files, component_path) do
    for kind <- [:required, :overwritable, :optional], reduce: [] do
      expanded_files ->
        globs = fireside_component_files[kind] || []

        expanded_paths =
          Enum.reduce(globs, [], fn glob, expanded_paths ->
            new_paths =
              component_path
              |> Path.join(glob)
              |> GlobEx.compile!()
              |> GlobEx.ls()
              |> Enum.map(fn path ->
                String.replace_prefix(path, component_path, "")
              end)

            expanded_paths ++ new_paths
          end)

        expanded_files ++ [{kind, expanded_paths}]
    end
  end

  def determine_component_type_and_version(requirement) do
    case String.split(requirement, "@", trim: true, parts: 2) do
      [component_name] ->
        {String.to_atom(component_name), nil}

      [component, suffix] ->
        case suffix do
          "git:" <> _requirement ->
            raise "@git components are not yet supported"

          "github:" <> _requirement ->
            raise "@github components are not yet supported"

          "path:" <> requirement ->
            {String.to_atom(component), path: requirement}

          _version ->
            raise "only @path components are currently supported"
        end
    end
  end

  def load_module(path) do
    [{module, _}] = Code.require_file(path)

    module
  end

  def get_module_prefix(module) do
    module |> Module.split() |> List.first() |> String.to_atom()
  end

  def replace_module_prefix_from_to(ast, old_prefix, new_prefix) do
    old_prefix_str = Atom.to_string(old_prefix)
    new_prefix_str = Atom.to_string(new_prefix)

    Macro.prewalk(ast, fn
      {:__aliases__, aliases_meta, [prefix | rest]} when is_atom(prefix) ->
        prefix_str = Atom.to_string(prefix)

        if String.starts_with?(prefix_str, old_prefix_str) do
          replaced_prefix =
            prefix_str
            |> String.replace_prefix(old_prefix_str, new_prefix_str)
            |> String.to_atom()

          {:__aliases__, aliases_meta,
           [
             replaced_prefix
             | rest
           ]}

          {:__aliases__, aliases_meta, [replaced_prefix | rest]}
        else
          {:__aliases__, aliases_meta, [prefix | rest]}
        end

      node ->
        node
    end)
  end

  def replace_app_name(ast, component_name) do
    otp_app_name = Igniter.Project.Application.app_name()

    Macro.prewalk(ast, fn
      ^component_name -> otp_app_name
      node -> node
    end)
  end

  def get_module_name_list(ast) do
    {:defmodule, _defmodule_meta, [{:__aliases__, _aliases_meta, module_name_list} | _rest]} =
      ast

    module_name_list
  end

  def get_module_name(ast) do
    ast
    |> get_module_name_list()
    |> Module.concat()
  end

  def calculate_hash(ast) do
    :sha |> :crypto.hash(Sourceror.to_string(ast)) |> Base.encode16()
  end

  def remove_fireside_comments(ast) do
    {:defmodule, meta, implementation} = ast

    meta =
      Keyword.replace_lazy(meta, :leading_comments, fn value ->
        Enum.reject(value, fn
          %{text: "#! fireside" <> _} -> true
          _ -> false
        end)
      end)

    {:defmodule, meta, implementation}
  end

  def ensure_clean_git! do
    unless match?({"", 0}, System.cmd("git", ["status", "--porcelain"])) do
      raise "Please stage or stash your current Git changes before continuing."
    end
  end
end
