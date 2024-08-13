defmodule Mix.Tasks.Fireside.Uninstall do
  @shortdoc "Uninstalls a Fireside component."
  @moduledoc """
  Uninstalls a Fireside component.

  ## Args

  mix fireside.uninstall `component`

  ## Supported formats

  * `component` - The installed component's name.

  ## Options

  * --yes - auto-accept all prompts
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {component_name, argv} = Enum.split_while(argv, fn arg -> not String.starts_with?(arg, "-") end)

    unless length(component_name) == 1 do
      raise "Exactly one component must be provided."
    end

    [component_name] = component_name

    unless Fireside.component_installed?(component_name) do
      raise "#{component_name} is not installed."
    end

    Application.ensure_all_started([:rewrite])

    Fireside.uninstall(component_name, yes?: "--yes" in argv)
  end
end
