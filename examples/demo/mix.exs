defmodule LanternDemo.MixProject do
  use Mix.Project

  def project do
    [
      app: :lantern_demo,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {LanternDemo.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:lantern, path: "../.."},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.0"},
      {:bandit, "~> 1.7"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "lantern_demo.seed"]
    ]
  end
end
