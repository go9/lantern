defmodule Lantern.MixProject do
  use Mix.Project

  @version "0.6.0"
  @source_url "https://github.com/go9/lantern"

  def project do
    [
      app: :lantern,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Lantern",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, "~> 1.1"},
      {:livecode, "~> 0.1"},
      {:lantern_ui, github: "go9/lantern-ui"},
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.0"},
      # Heroicons SVG source (build-only, uncompiled). icon/1 reads the outline
      # set from this at COMPILE time, so every `hero-*` name resolves — no
      # hand-maintained subset to drift. Same pin flicker uses.
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "An embeddable Postgres table viewer and editor for Phoenix LiveView. " <>
      "Browse, filter, sort, and edit any database from a connection you supply — " <>
      "drop-in, dependency-free UI."
  end

  defp package do
    [
      maintainers: ["Giovanni Orlando"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"},
      files: ~w(lib priv/static/lantern .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
