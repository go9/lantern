defmodule LanternDemo.Sandbox.Provider do
  @moduledoc """
  Behaviour a sandbox pool implements to provision, describe, and reap the
  real resource behind a slot (a Postgres branch for the `:db` pool, an
  ephemeral bucket for the `:s3` pool).

  The `SandboxManager` owns admission (slots + queue + TTL + monitors) and is
  otherwise resource-agnostic — it calls a pool's provider to create/tear down
  the underlying resource. Reaping must succeed even when the owning LiveView
  is already gone, so `reap/1` takes the opaque resource the manager stored,
  never a caller pid.
  """

  @typedoc "Opaque per-session resource, stored by the manager and passed back to `reap/1`."
  @type resource :: term()

  @doc "Create the real resource for one session. Runs inside the manager process."
  @callback provision() :: {:ok, resource()} | {:error, String.t()}

  @doc "Tear the resource down. Must be idempotent — may be called after the owner died."
  @callback reap(resource()) :: :ok

  @doc "Public payload handed to the LiveView on grant (e.g. `%{url: ...}`). No secrets the client can misuse."
  @callback payload(resource()) :: map()
end
