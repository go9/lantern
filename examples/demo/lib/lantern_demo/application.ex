defmodule LanternDemo.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
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
end
