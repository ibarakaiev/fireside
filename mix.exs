defmodule Fireside.MixProject do
  use Mix.Project

  @source_url "https://github.com/ibarakaiev/fireside"
  @version "0.0.2"

  @description """
  Fireside is a Elixir library to embed and maintain self-contained Elixir apps
  into your existing Elixir application with smart code generation.
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
      extras: [
        {"README.md", title: "Home"}
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
      {:igniter, "~> 0.3.8"},
      {:ex_doc, "~> 0.32", only: [:dev, :test], runtime: false}
    ]
  end
end
