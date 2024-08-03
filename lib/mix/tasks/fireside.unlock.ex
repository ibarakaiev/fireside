defmodule Mix.Tasks.Fireside.Unlock do
  @shortdoc "Unlocks a Fireside component."
  @moduledoc """
  Unlocks a Fireside component.

  ## Args

  mix fireside.unlock `component`

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
      raise "#{component_name} is not installed. You can install it with `mix fireside.install #{component_name}@path:/path/to/#{component_name}#{if(length(argv) > 0, do: " " <> Enum.join(argv, " "), else: "")} --unlock`."
    end

    Application.ensure_all_started([:rewrite])

    Fireside.unlock(component_name, yes?: "--yes" in argv)
  end
end
