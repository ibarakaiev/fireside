defmodule Fireside.Util.Update do
  require Igniter.Code.Function

  def update(component_name) do
    igniter = Igniter.new() |> Igniter.include_all_elixir_files()

    unless Igniter.Project.Config.configures_key?(
             igniter,
             "fireside.exs",
             Igniter.Project.Application.app_name(),
             [Fireside, component_name]
           ) do
      raise "#{component_name} is not installed. You can install it with `fireside.install #{component_name}`."
    end

    component_config = get_component_config(igniter, component_name)

    igniter
    |> check_integrity(component_config)
    |> Igniter.assign(:overwritable_paths, [])
    # TODO: add dependency updates
    |> reimport_files(component_name, component_config)
    |> delete_no_longer_used_files(component_config)
    |> Igniter.do_or_dry_run([])
  end

  defp check_integrity(igniter, component_config) do
    for {file_path, hash} <- component_config.files do
      if Igniter.exists?(igniter, file_path) do
        source =
          igniter.rewrite
          |> Rewrite.source!(file_path)
          |> Rewrite.Source.get(:quoted)
          |> remove_fireside_comments()

        if Fireside.calculate_hash(source) != hash do
          raise "#{file_path} has diverged from its original source, aborting."
        end
      else
        raise "#{file_path} does not exist, aborting."
      end
    end

    igniter
  end

  defp reimport_files(igniter, component_name, component_config) do
    case component_config.source do
      :path ->
        component_path = component_config.origin

        if not File.dir?(component_path) do
          raise "#{component_name}'s source directory `#{component_path}` no longer exists"
        end

        fireside_module_path = Path.join(component_path, "/fireside.exs")

        if not File.exists?(fireside_module_path) do
          raise "#{component_name}'s source directory `#{component_path}` does not contain fireside.exs"
        end

        fireside_module = Fireside.load_module(fireside_module_path)

        fireside_module_prefix =
          fireside_module |> Module.split() |> List.first() |> String.to_atom()

        project_prefix = Mix.Project.get!() |> Module.split() |> List.first() |> String.to_atom()

        expanded_fireside_includes =
          Fireside.expand_fireside_includes(component_path, fireside_module.config())

        igniter
        |> install_code(
          expanded_fireside_includes,
          fireside_module_prefix,
          project_prefix,
          expanded_fireside_includes[:overwritable]
        )
        |> Fireside.add_or_replace_fireside_lock(component_name, component_path)
    end
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
        for path <- expanded_fireside_includes[kind],
            path not in expanded_fireside_includes.overwritable,
            reduce: igniter do
          igniter ->
            Fireside.Util.Install.import_to_project(
              igniter,
              path,
              kind,
              fireside_module_prefix,
              project_prefix,
              overwritable_paths,
              check_for_conflicts?: false
            )
        end
    end
  end

  # WARN:Igniter currently doesn't support deleting files, so this won't show up in the diff
  defp delete_no_longer_used_files(igniter, component_config) do
    for {file_path, _hash} <- component_config.files,
        file_path not in igniter.assigns.imported_paths,
        reduce: igniter do
      igniter ->
        %{igniter | rewrite: Rewrite.rm!(igniter.rewrite, file_path)}
    end
  end

  defp remove_fireside_comments(ast) do
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

  defp get_component_config(igniter, component_name) do
    zipper =
      igniter.rewrite
      |> Rewrite.source!("config/fireside.exs")
      |> Rewrite.Source.get(:quoted)
      |> Sourceror.Zipper.zip()

    otp_app = Igniter.Project.Application.app_name()

    {:ok, zipper} =
      Igniter.Code.Function.move_to_function_call_in_current_scope(
        zipper,
        :config,
        3,
        fn function_call ->
          Igniter.Code.Function.argument_equals?(function_call, 0, otp_app) and
            Igniter.Code.Function.argument_equals?(function_call, 1, Fireside) and
            Igniter.Code.Function.argument_matches_predicate?(
              function_call,
              2,
              fn argument_zipper ->
                Igniter.Code.Keyword.keyword_has_path?(argument_zipper, [component_name])
              end
            )
        end
      )

    {{:__block__, _, [^component_name]}, map} =
      zipper
      |> Igniter.Code.Function.move_to_nth_argument(2)
      |> then(fn {:ok, zipper} -> zipper end)
      |> Sourceror.Zipper.down()
      |> Sourceror.Zipper.node()

    {config, []} =
      map
      |> Sourceror.to_string()
      |> Code.eval_string()

    config
  end
end
