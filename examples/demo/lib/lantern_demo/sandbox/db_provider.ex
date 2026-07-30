defmodule LanternDemo.Sandbox.DbProvider do
  @moduledoc """
  `:db` pool provider — forks and drops the Postgres demo sandbox via
  `LanternDemo.DemoDB`. This is the existing DB-demo behaviour, now behind the
  generic `SandboxManager` slot/queue engine.
  """

  @behaviour LanternDemo.Sandbox.Provider

  @impl true
  def provision do
    case LanternDemo.DemoDB.create_sandbox() do
      {:ok, url, sandbox_id} -> {:ok, %{url: url, sandbox_id: sandbox_id}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def reap(%{sandbox_id: sandbox_id}) do
    LanternDemo.DemoDB.drop_sandbox(sandbox_id)
    :ok
  end

  @impl true
  def payload(%{url: url}), do: %{url: url}
end
