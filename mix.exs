defmodule Fireside.MixProject do
  use Mix.Project

  @source_url "https://github.com/ibarakaiev/fireside"
  @version "0.1.2"

  @description """
  Fireside is a small Elixir library that allows importing code components (templates) into an existing Elixir project together with their dependencies. It also allows upgrading these components if they have a newer version available. 
  """

  def project do
    [
      app: :fireside,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: @description,
      source_url: @source_url,
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "logos/logo-256.png",
      extras: [
        {"README.md", title: "Overview"},
        "documentation/creating-components.md",
        {"CHANGELOG.md", title: "Changelog"}
      ]
    ]
  end

  defp package do
    [
      name: :fireside,
      licenses: ["MIT"],
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      links: %{
        GitHub: @source_url
      }
    ]
  end

  defp deps do
    [
      {:igniter, "~> 0.3"},
      {:ex_doc, "~> 0.32", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
