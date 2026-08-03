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

      # ⚠️ TEMPORARY LOCAL OVERRIDE — MUST BE REMOVED BEFORE MERGE ⚠️
      #
      # `lantern` pins {:lantern_ui, github: "go9/lantern-ui"} (the default
      # branch). The `command` palette component is NOT merged and NOT released
      # yet — it lives on the `feat/command-palette` branch (go9/lantern-ui
      # PR #73), checked out in a sibling worktree. This override points the
      # demo at that working tree so the component (and its compiled
      # priv/static CSS + hooks, which the endpoint serves) resolve locally.
      #
      # It only works on a machine that has ~/Sites/lantern-ui-command checked
      # out — CI and every other clone will fail `mix deps.get` here.
      #
      # REVERT THIS LINE (delete it entirely; `lantern`'s own github pin then
      # takes over) once lantern-ui PR #73 is merged and released.
      {:lantern_ui, path: "../../../lantern-ui-command", override: true},
      {:lantern_s3, github: "go9/lantern-s3"},
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
