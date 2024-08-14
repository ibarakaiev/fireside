defmodule Mix.Tasks.Fireside.Update do
  @shortdoc "Updates a Fireside component."
  @moduledoc """
  Updates a Fireside component.

  ## Args

  mix fireside.update `component`

  ## Supported formats

  * `component` - The component's source will be fetched from the local component config (in `config/fireside.exs`).
  #{Fireside.Helpers.supported_formats()}

  ## Options

  * --yes - auto-accept all prompts
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {component_requirements, argv} = Enum.split_while(argv, fn arg -> not String.starts_with?(arg, "-") end)

    unless length(component_requirements) == 1 do
      raise "Exactly one component must be provided."
    end

    [component_requirement] = component_requirements

    {component_name, component_source} =
      Fireside.Helpers.determine_component_source(component_requirement)

    unless Fireside.component_installed?(component_name) do
      raise """
      #{component_name} is not installed. You can install it with `mix fireside.install #{component_name}@... #{if(length(argv) > 0, do: " " <> Enum.join(argv, " "), else: "")}`.

      #{Fireside.Helpers.supported_formats(component_name)}.
      """
    end

    Application.ensure_all_started([:rewrite])

    Fireside.update(component_name, component_source, yes?: "--yes" in argv)
  end
end
