defmodule LanternDemo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The seeded demo database is only used by the DB-viewer page and is only
    # configured in prod (LANTERN_DEMO_DATABASE_URL). Locally there's no DB, so
    # skip the seed — the components reference and everything else run without
    # Postgres. The DB-viewer page degrades gracefully when unconfigured.
    if demo_db_configured?(), do: LanternDemo.DemoDB.ensure!()

    children = [
      {Phoenix.PubSub, name: LanternDemo.PubSub},
      LanternDemo.SandboxManager,
      LanternDemoWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: LanternDemo.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    LanternDemoWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp demo_db_configured?, do: System.get_env("LANTERN_DEMO_DATABASE_URL") not in [nil, ""]
end
