defmodule Mix.Tasks.Fireside.Update do
  @moduledoc """
  Updates a Fireside component.

  ## Args

  mix fireside.update `component`

  ## Supported formats

  * `component` - The component to be updated
  """
  use Mix.Task

  @impl true
  @shortdoc "Update a Fireside component."
  def run(argv) do
    if length(argv) != 1 do
      raise ArgumentError, "must provide exactly one component to update"
    end

    [component] = argv

    if String.contains?(component, "@") do
      raise ArgumentError, "you may only provide the component name"
    end

    Application.ensure_all_started([:rewrite])

    Fireside.Util.Update.update(String.to_atom(component))
  end
end
