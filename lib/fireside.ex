defmodule Fireside do
  @moduledoc """
  This is the documentation for the Fireside project.
  """

  alias Igniter.Code.Function
  alias Igniter.Project.Config
  alias Sourceror.Zipper

  require Logger

  @doc """
  Checks if the provided component is installed in the current project.

  ## Examples

      iex> Fireside.component_installed?(:example_component)
      false
  """
  def component_installed?(component_name)

  def component_installed?(component_name) when is_binary(component_name) do
    component_installed?(String.to_atom(component_name))
  end

  def component_installed?(component_name) when is_atom(component_name) do
    igniter = Igniter.new()

    Config.configures_key?(
      igniter,
      "fireside.exs",
      Igniter.Project.Application.app_name(igniter),
      [Fireside, component_name]
    )
  end

  @doc """
  Installs a Fireside component into the project.

  This is done by importing files listed in `config/0` (in `fireside.exs`) of the target component.
  If the component defines a `setup/1` method, it will also be called.

  ## Parameters

    - `component_name`: The name of the component to install. It can be an atom or a string.
    - `source`: The source from which to install the component. The supported formats are:
      - `[path: component_path]`: Install from a local path.
      - `[{:git, git_url} | git_opts]`: Install from a Git repository. `git_opts` can include `:ref`, `:branch`, or `:tag`.
      - `[{:github, github_repo} | git_opts]`: Install from a GitHub repository. `git_opts` can include `:ref`, `:branch`, or `:tag`.
    - `opts`: A keyword list of options. Supported options include:
      - `:unlocked?` - When true, the component is installed without being tracked by Fireside.
      - `:yes?` - When true, auto-accepts all prompts during installation.

  ## Examples

      iex> Fireside.install(:my_component, [path: "/path/to/component"], unlocked?: true)
      :ok

      iex> Fireside.install(:my_component, [git: "https://github.com/user/repo.git"] ++ [tag: "v1.0.0"])
      :ok

      iex> Fireside.install(:my_component, [github: "user/repo"] ++ [branch: "main"])
      :ok

  """
  def install(component_name, source, opts \\ [])

  def install(component_name, source, opts) when is_binary(component_name) do
    install(String.to_atom(component_name), source, opts)
  end

  def install(component_name, source, opts) when is_atom(component_name) do
    Fireside.Helpers.ensure_clean_git!()

    do_install_or_update(Igniter.new(), component_name, source, opts)
  end

  @doc """
  Updates a previously installed Fireside component.

  This is done by reimporting files listed in `config/0` (in `fireside.exs`) of the target component.
  If the component's version is being changed and a corresponding `upgrade/3` migration is defined,
  it will also be executed. (Note: multiple `upgrade/3` migrations may be executed if the app's
  version is changed by more than 1.)

  Before updating, the integrity of the installed component will be checked by comparing the hash
  of the AST with the hash listed in `config/fireside.exs`. If the installed component has been
  modified and has diverged from its original source, the operation will be aborted, as it might
  lead to a regression since any added/removed functionality may be overwritten by remote updates.
  In this case, it is recommended to run `unlock/2` to instruct Fireside to stop tracking the
  component's source.

  ## Parameters

    - `component_name`: The name of the component to update. It can be an atom or a string.
    - `source`: The source from which to update the component. If `nil` (default), the source from the
      local component configuration is used. Otherwise, the supported formats are:
      - `[path: component_path]`: Install from a local path.
      - `[{:git, git_url} | git_opts]`: Install from a Git repository. `git_opts` can include `:ref`, `:branch`, or `:tag`.
      - `[{:github, github_repo} | git_opts]`: Install from a GitHub repository. `git_opts` can include `:ref`, `:branch`, or `:tag`.
    - `opts`: A keyword list of options. Supported options include:
      - `:yes?` - When true, auto-accepts all prompts during the update.

  ## Examples

      iex> Fireside.update(:my_component)
      :ok

      iex> Fireside.update(:my_component, [git: "https://github.com/user/repo.git"] ++ [branch: "dev"])
      :ok

  """
  def update(component_name, source \\ nil, opts \\ [])

  def update(component_name, source, opts) when is_binary(component_name) do
    update(String.to_atom(component_name), source, opts)
  end

  def update(component_name, source, opts) do
    local_component_config = get_local_component_config(component_name)

    ensure_integrity!(local_component_config)

    opts = opts ++ [current_version: local_component_config[:version]]

    Fireside.Helpers.ensure_clean_git!()

    igniter = track_managed_files(Igniter.new(), local_component_config)

    case source do
      nil ->
        do_install_or_update(
          igniter,
          component_name,
          local_component_config[:origin],
          opts
        )

      source ->
        do_install_or_update(igniter, component_name, source, opts)
    end

    :ok
  end

  @doc """
  Unlocks a Fireside component, removing it from Fireside's tracking without deleting it.

  This is useful if you want to continue using the component but no longer want it to be managed
  by Fireside.

  ## Parameters

    - `component_name`: The name of the component to unlock. It can be an atom or a string.
    - `opts`: A keyword list of options. Supported options include:
      - `:yes?` - When true, auto-accepts all prompts during the unlock process.

  ## Examples

      iex> Fireside.unlock(:my_component)
      :ok
  """

  def unlock(component_name, opts) when is_binary(component_name) do
    unlock(String.to_atom(component_name), opts)
  end

  def unlock(component_name, opts) when is_atom(component_name) do
    local_component_config = get_local_component_config(component_name)

    igniter =
      for {file_path, _hash} <- local_component_config[:files], reduce: Igniter.new() do
        igniter ->
          Igniter.update_elixir_file(igniter, file_path, fn zipper ->
            zipper_without_fireside_comments = zipper |> Zipper.node() |> Fireside.Helpers.remove_fireside_comments()
            {:ok, Zipper.replace(zipper, zipper_without_fireside_comments)}
          end)
      end

    igniter
    |> remove_local_component_config(component_name)
    |> run_igniter(opts)

    :ok
  end

  @doc """
  Uninstalls a Fireside component from the project.

  This function will attempt to remove all files and configurations associated with the component that were
  managed by Fireside. However, there are certain manual steps you may need to perform after the
  uninstallation; read more in the "Warning" below.

  ## Parameters

    - `component_name`: The name of the component to uninstall. It can be an atom or a string.
    - `opts`: A keyword list of options. Supported options include:
      - `:yes?` - When true, auto-accepts all prompts during the uninstallation.

  > ### Warning {: .warning}
  >
  > After uninstalling a component, you may need to manually:
  >
  > - **Remove Optional or Manually Added Files**: If the component installation added files that were not tracked by Fireside
  >   (e.g., files that were marked as `:optional` or added outside the standard component structure via Igniter),
  >   these will not be automatically deleted. You will need to identify and remove these files yourself, if needed.
  > - **Cleanup Configuration Changes**: If the component installation modified configuration files
  >   (e.g., `config/config.exs`, `config/dev.exs`), these changes will not be reverted automatically.
  >   Review these files and manually remove any settings or configurations related to the uninstalled component.
  > - **Remove Unused Dependencies**: Dependencies installed alongside the component will not be automatically
  >   removed, as Fireside cannot determine if they are used elsewhere in your project. You may need to manually
  >   remove these dependencies from your `mix.exs` file and run `mix deps.clean` to fully remove them from your project.

  ## Examples

      iex> Fireside.uninstall(:my_component)
      :ok
  """
  def uninstall(component_name, opts \\ [])

  def uninstall(component_name, opts) when is_binary(component_name) do
    uninstall(String.to_atom(component_name), opts)
  end

  def uninstall(component_name, opts) when is_atom(component_name) do
    local_component_config = get_local_component_config(component_name)

    igniter =
      Igniter.new()
      |> track_managed_files(local_component_config)
      |> Igniter.assign(:imported_files, [])
      |> Igniter.add_warning(
        "Finally, any code modification that were performed in `setup/1` or `upgrade/3` by the component will not be removed. Please consult the component's original Fireside config (fireside.exs) to see if anything was added modified manually, such as config.exs."
      )
      |> Igniter.add_warning(
        "Imported files that were marked as :optional in Fireside's component configuration will also not be deleted, as they could have existed before component installation (for example, `test/supports/data_case.ex` or `lib/my_app_web/endpoint.ex`)"
      )
      |> Igniter.add_warning("""
      NOTE: the dependencies installed alongside the component will NOT be deleted as Fireside has no way of knowing if they are used elsewhere in the codebase.

      If you want to manually delete them, please check the list of non-optional dependencies in the source code of the component you're uninstalling.

      Keep in mind that those dependencies may have had associated Igniter installers that added some code or configuration to your codebase—you may want to delete that too.
      """)
      |> add_deletions()
      |> remove_local_component_config(component_name)

    if run_igniter(igniter, opts) == :changes_made do
      cleanup_no_longer_used_files(igniter)
    end

    :ok
  end

  defp run_igniter(igniter, opts) do
    Igniter.do_or_dry_run(igniter, yes: Keyword.get(opts, :yes?, false), title: Keyword.get(opts, :title, "Fireside"))
  end

  defp do_install_or_update(igniter, component_name, source, opts)

  defp do_install_or_update(igniter, component_name, [{:github, github_repo} | params], opts) do
    git_url = "https://github.com/#{github_repo}.git"
    do_install_or_update(igniter, component_name, [git: git_url] ++ params, opts)
  end

  defp do_install_or_update(igniter, component_name, [{:git, git_url} | git_opts] = origin, opts) do
    temp_dir = Path.join(System.tmp_dir!(), "fireside_#{component_name}_#{:os.system_time(:millisecond)}")

    File.mkdir_p!(temp_dir)

    {_, 0} = System.cmd("git", ["clone", git_url, temp_dir])

    cond do
      ref = git_opts[:ref] ->
        {_, 0} = System.cmd("git", ["checkout", ref], cd: temp_dir)

      branch = git_opts[:branch] ->
        {_, 0} = System.cmd("git", ["checkout", branch], cd: temp_dir)

      tag = git_opts[:tag] ->
        {_, 0} = System.cmd("git", ["checkout", "tags/#{tag}"], cd: temp_dir)

      true ->
        :ok
    end

    import_component(igniter, component_name, temp_dir, origin, opts)

    File.rm_rf!(temp_dir)
  end

  defp do_install_or_update(igniter, component_name, [path: component_path] = origin, opts) do
    import_component(igniter, component_name, component_path, origin, opts)
  end

  defp import_component(igniter, component_name, component_path, origin, opts) do
    current_version = Keyword.get(opts, :current_version, nil)
    unlocked? = Keyword.get(opts, :unlocked?, false)

    ensure_path_is_a_fireside_component!(component_path)

    install_required_dependencies(component_path, yes?: Keyword.get(opts, :yes?, false))

    fireside_module = get_fireside_component_module(component_name, component_path)

    {igniter, current_version} =
      case current_version do
        nil ->
          igniter =
            try do
              fireside_module.setup(igniter)
            rescue
              _ -> igniter
            end

          {igniter, 1}

        _ ->
          {igniter, current_version}
      end

    igniter =
      igniter
      |> Igniter.update_assign(:fireside_managed_files, [], & &1)
      |> Igniter.assign(imported_files: [], deletions: [], hashes: [])
      |> install_files(fireside_module, component_path)
      |> run_upgrades(fireside_module, current_version)
      |> replace_component_name(fireside_module)
      |> add_deletions()

    igniter =
      if unlocked? do
        igniter
      else
        add_or_replace_fireside_lock(
          igniter,
          fireside_module,
          origin
        )
      end

    igniter =
      Igniter.add_notice(
        igniter,
        "\"#{component_name}\" (version: #{fireside_module.config()[:version]}) has been successfully installed."
      )

    if run_igniter(igniter, opts) in [:changes_made, :no_changes] do
      cleanup_no_longer_used_files(igniter)
    end
  end

  defp install_files(igniter, fireside_module, component_path) do
    fireside_component_files =
      Fireside.Helpers.expand_fireside_component_globs(fireside_module.config()[:files], component_path)

    for kind <- [:required, :optional], reduce: igniter do
      igniter ->
        relative_paths = fireside_component_files[kind]

        Enum.reduce(relative_paths, igniter, fn relative_path, igniter ->
          install_file(
            igniter,
            fireside_module,
            component_path,
            relative_path,
            skip_if_exists?: kind == :optional,
            untracked?: relative_path in fireside_component_files[:overwritable] or kind == :optional
          )
        end)
    end
  end

  defp install_file(igniter, fireside_module, component_path, relative_file_path, opts) do
    fireside_module_prefix = Fireside.Helpers.get_module_prefix(fireside_module)
    project_prefix = Fireside.Helpers.get_module_prefix(Mix.Project.get!())

    ast =
      [component_path, relative_file_path]
      |> Path.join()
      |> File.read!()
      |> Sourceror.parse_string!()

    module_name =
      ast
      |> Fireside.Helpers.replace_module_prefix_from_to(fireside_module_prefix, project_prefix)
      |> Fireside.Helpers.get_module_name()

    proper_location =
      case relative_file_path do
        "/lib/" <> _ ->
          Igniter.Code.Module.proper_location(module_name)

        "/test/support/" <> _ ->
          Igniter.Code.Module.proper_test_support_location(module_name)

        "/test/" <> _ ->
          Igniter.Code.Module.proper_test_location(module_name)
      end

    igniter =
      if Keyword.fetch!(opts, :skip_if_exists?) do
        Igniter.include_or_create_file(
          igniter,
          proper_location,
          Sourceror.to_string(ast)
        )
      else
        fireside_managed_files = igniter.assigns.fireside_managed_files

        if Igniter.exists?(igniter, proper_location) and proper_location not in fireside_managed_files do
          raise "Conflicting file #{proper_location} already exists, aborting."
        end

        igniter
        |> Igniter.create_or_update_elixir_file(
          proper_location,
          Sourceror.to_string(ast),
          fn _ -> Zipper.zip(ast) end
        )
        |> Igniter.update_assign(:imported_files, [proper_location], &(&1 ++ [proper_location]))
      end

    if Keyword.fetch!(opts, :untracked?) do
      Igniter.update_assign(
        igniter,
        :untracked_files,
        [proper_location],
        fn overwritable_paths -> overwritable_paths ++ [proper_location] end
      )
    else
      igniter
    end
  end

  defp add_deletions(igniter) do
    deletion_list =
      MapSet.difference(
        MapSet.new(igniter.assigns.fireside_managed_files),
        MapSet.new(igniter.assigns.imported_files)
      )

    for file_path <- deletion_list, reduce: igniter do
      igniter ->
        igniter
        |> Igniter.add_warning("#{file_path} will be deleted.")
        |> Igniter.update_assign(:deletions, [file_path], fn deletions -> deletions ++ [file_path] end)
    end
  end

  defp cleanup_no_longer_used_files(igniter) do
    for file_path <- igniter.assigns.deletions do
      File.rm!(file_path)
    end
  end

  defp remove_local_component_config(igniter, component_name) do
    Config.configure(
      igniter,
      "fireside.exs",
      Igniter.Project.Application.app_name(igniter),
      [Fireside],
      [],
      updater: fn zipper ->
        Igniter.Code.Keyword.remove_keyword_key(zipper, component_name)
      end
    )
  end

  defp add_or_replace_fireside_lock(igniter, fireside_module, origin) do
    igniter =
      for source <- Rewrite.sources(igniter.rewrite),
          Rewrite.Source.get(source, :path) in igniter.assigns.imported_files,
          Rewrite.Source.get(source, :path) not in igniter.assigns.untracked_files,
          reduce: igniter do
        igniter ->
          {new_quoted, hash} =
            source
            |> Rewrite.Source.get(:quoted)
            |> compute_and_include_hash(fireside_module.config()[:name])

          new_source =
            Rewrite.Source.update(
              source,
              :quoted,
              new_quoted
            )

          path = Rewrite.Source.get(source, :path)

          Igniter.update_assign(
            %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)},
            :hashes,
            [{path, hash}],
            fn hashes -> hashes ++ [{path, hash}] end
          )
      end

    app_name = Igniter.Project.Application.app_name(igniter)

    igniter
    |> Config.configure(
      "fireside.exs",
      app_name,
      [Fireside, fireside_module.config()[:name], :origin],
      origin
    )
    |> Config.configure(
      "fireside.exs",
      app_name,
      [Fireside, fireside_module.config()[:name], :version],
      fireside_module.config()[:version]
    )
    |> Config.configure(
      "fireside.exs",
      app_name,
      [Fireside, fireside_module.config()[:name], :files],
      Macro.escape(igniter.assigns.hashes)
    )
  end

  defp ensure_path_is_a_fireside_component!(path) do
    unless File.dir?(path) do
      raise "directory `#{path}` doesn't exist"
    end

    fireside_module_path = Path.join(path, "/fireside.exs")

    unless File.exists?(fireside_module_path) do
      raise "#{path} is not a Fireside component, aborting."
    end
  end

  defp get_fireside_component_module(component_name, component_path) do
    fireside_module_path = Path.join(component_path, "/fireside.exs")

    fireside_module = Fireside.Helpers.load_module(fireside_module_path)

    unless fireside_module.config()[:name] == component_name do
      raise "The provided Fireside module is not \"#{component_name}\""
    end

    fireside_module
  end

  defp get_local_component_config(component_name) do
    zipper =
      "config/fireside.exs"
      |> File.read!()
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()

    otp_app = Igniter.Project.Application.app_name(Igniter.new())

    {:ok, zipper} =
      Function.move_to_function_call_in_current_scope(
        zipper,
        :config,
        3,
        fn function_call ->
          Function.argument_equals?(function_call, 0, otp_app) and
            Function.argument_equals?(function_call, 1, Fireside) and
            Function.argument_matches_predicate?(
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
      |> Function.move_to_nth_argument(2)
      |> then(fn {:ok, zipper} -> zipper end)
      |> Sourceror.Zipper.down()
      |> Sourceror.Zipper.node()

    {config, []} =
      map
      |> Sourceror.to_string()
      |> Code.eval_string()

    config
  end

  defp track_managed_files(igniter, local_component_config) do
    for {file_path, _hash} <- local_component_config[:files], reduce: igniter do
      igniter ->
        igniter
        |> Igniter.include_existing_file(file_path)
        |> Igniter.update_assign(
          :fireside_managed_files,
          [file_path],
          fn fireside_managed_files -> fireside_managed_files ++ [file_path] end
        )
    end
  end

  defp replace_component_name(igniter, fireside_module) do
    fireside_module_prefix = Fireside.Helpers.get_module_prefix(fireside_module)
    project_prefix = Fireside.Helpers.get_module_prefix(Mix.Project.get!())

    igniter = Igniter.include_all_elixir_files(igniter)

    for source <- Rewrite.sources(igniter.rewrite),
        Rewrite.Source.get(source, :path) != "config/fireside.exs",
        reduce: igniter do
      igniter ->
        new_quoted =
          source
          |> Rewrite.Source.get(:quoted)
          |> Fireside.Helpers.replace_module_prefix_from_to(fireside_module_prefix, project_prefix)
          |> Fireside.Helpers.replace_app_prefix(
            Igniter.Project.Application.app_name(igniter),
            fireside_module.config()[:name]
          )

        new_source =
          Rewrite.Source.update(
            source,
            :quoted,
            new_quoted
          )

        %{igniter | rewrite: Rewrite.update!(igniter.rewrite, new_source)}
    end
  end

  defp install_required_dependencies(component_path, opts) do
    mix_file = Path.join(component_path, "mix.exs")

    unless File.exists?(mix_file) do
      raise "mix.exs not found in the component directory"
    end

    {deps, _} =
      mix_file
      |> File.read!()
      |> Sourceror.parse_string!()
      |> Sourceror.Zipper.zip()
      |> Function.move_to_defp(:deps, 0)
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

    yes? = Keyword.get(opts, :yes?, false)

    deps
    |> Enum.reject(&(elem(&1, 0) == :igniter))
    |> Enum.reject(fn
      {_app, opts} when is_list(opts) ->
        Keyword.get(opts, :optional, false)

      {_app, _requirement, opts} ->
        Keyword.get(opts, :optional, false)

      {_app, _requirement} ->
        false
    end)
    |> Igniter.Util.Install.install(if(yes?, do: ["--yes"], else: []), Igniter.new(),
      error_on_abort?: true,
      title: "Fireside",
      notify_on_present?: false
    )

    Igniter.Util.DepsCompile.run()
  end

  defp ensure_integrity!(imported_component_config) do
    igniter = track_managed_files(Igniter.new(), imported_component_config)

    for {file_path, hash} <- imported_component_config[:files] do
      if Igniter.exists?(igniter, file_path) do
        source =
          igniter.rewrite
          |> Rewrite.source!(file_path)
          |> Rewrite.Source.get(:quoted)
          |> Fireside.Helpers.remove_fireside_comments()

        unless Fireside.Helpers.calculate_hash(source) == hash do
          raise "#{file_path} has diverged from its original source, aborting."
        end
      else
        raise "#{file_path} does not exist, aborting."
      end
    end

    :ok
  end

  defp run_upgrades(igniter, fireside_module, current_version) do
    target_version = fireside_module.config()[:version]

    if target_version > current_version do
      {igniter, _version} =
        Enum.reduce(
          (current_version + 1)..target_version,
          {igniter, current_version},
          fn next_version, {igniter, current_version} ->
            igniter =
              try do
                fireside_module.upgrade(igniter, current_version, next_version)
              rescue
                _ -> igniter
              end

            {igniter, current_version + 1}
          end
        )

      igniter
    else
      igniter
    end
  end

  defp compute_and_include_hash(ast, component_name) do
    hash = Fireside.Helpers.calculate_hash(ast)

    {Sourceror.prepend_comments(
       ast,
       [
         %{
           line: 1,
           previous_eol_count: 1,
           next_eol_count: 1,
           text:
             "#! fireside: DO NOT EDIT this file. Run `mix fireside.unlock #{component_name}` if you want to stop syncing."
         }
       ],
       :leading
     ), hash}
  end
end
