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
      {:lantern_s3, github: "go9/lantern-s3"},
      # lantern_s3 pins its own unpinned lantern_ui git dep with no override, which
      # diverges from the pin in ../../mix.exs once both are in the tree. Mix
      # requires the override on the actual top-level project (this one), not on
      # the nested `lantern` path dependency where the other pin lives.
      {:lantern_ui,
       github: "go9/lantern-ui", ref: "f4e46ffebcb3e219514cb0bd01eb97487cb17d65", override: true},
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.1"},
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.0"},
      {:bandit, "~> 1.7"},
      {:req, "~> 0.5"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "lantern_demo.seed"]
    ]
  end
end
