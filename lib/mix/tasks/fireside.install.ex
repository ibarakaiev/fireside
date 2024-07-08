defmodule Mix.Tasks.Fireside.Install do
  @moduledoc """
  Install a Fireside app.

  ## Args

  mix fireside.install `app`

  ## Package formats

  * `app@path:path/to/app` - The app will be installed from the specified path.
  """
  use Mix.Task

  @impl true
  @shortdoc "Install a Fireside app."
  def run(argv) do
    if length(argv) != 1 do
      raise ArgumentError, "must provide exactly one component to install"
    end

    [component] = argv

    Application.ensure_all_started([:rewrite])

    Fireside.Util.Install.install(component)
  end
end
