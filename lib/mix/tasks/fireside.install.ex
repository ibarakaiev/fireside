defmodule Mix.Tasks.Fireside.Install do
  @shortdoc "Installs a Fireside component."
  @moduledoc """
  Installs a Fireside component.

  ## Args

  mix fireside.install `component`

  ## Supported formats

  #{Fireside.Helpers.supported_formats()}

  ## Options

  * --unlocked - the component will be installed without being tracked by Fireside.
  * --yes - auto-accept all prompts
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {component_requirements, argv} = Enum.split_while(argv, fn arg -> not String.starts_with?(arg, "-") end)

    unless length(component_requirements) == 1 do
      raise "Only one component can be provided."
    end

    [component_requirement] = component_requirements

    {component_name, component_source} =
      Fireside.Helpers.determine_component_source(component_requirement)

    if is_nil(component_source) do
      raise """
      Make sure to the provide the source for the component. Supported formats:

      #{Fireside.Helpers.supported_formats(component_name)}
      """
    end

    if Fireside.component_installed?(component_name) do
      raise "#{component_name} is already installed. Use `mix fireside.update #{component_name}#{if(length(argv) > 0, do: " " <> Enum.join(argv, " "), else: "")}` to update it instead."
    end

    Mix.shell().info("Installing #{component_name}...")

    Application.ensure_all_started([:rewrite])

    Fireside.install(component_name, component_source, unlocked?: "--unlocked" in argv, yes?: "--yes" in argv)
  end
end
