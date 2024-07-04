defmodule Mix.Tasks.Fireside.Install do
  @moduledoc """
  Install a Fireside component.

  ## Args

  mix fireside.install component

  ## Package formats

  * `package@path:path/to/dep` - The package will be installed from the specified path.
  """
  use Mix.Task

  @impl true
  @shortdoc "Install a package or packages, and run any associated installers."
  def run(argv) do
    if length(argv) != 1 do
      raise ArgumentError, "must provide exactly one component to install"
    end

    [component] = argv

    Application.ensure_all_started([:rewrite])

    Fireside.Util.Install.install(component)
  end
end
