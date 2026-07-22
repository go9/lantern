defmodule LanternDemo.S3Sandbox.PrefixProvider do
  @moduledoc """
  `:s3` pool provider for the `SandboxManager` (flicker #986).

  "Provisioning" a session is just minting a fresh, unguessable prefix under the
  one shared demo bucket — there is no per-session storage call. Reaping deletes
  every object under that prefix. Session isolation is by prefix; the demo app's
  credentials are scoped to the single bucket only.
  """

  @behaviour LanternDemo.Sandbox.Provider

  require Logger

  alias LanternDemo.S3Sandbox.Storage
  alias LanternS3.Storage.S3

  @impl true
  def provision do
    case Storage.s3_config() do
      {:ok, config} ->
        {:ok, %{bucket: Storage.bucket(), prefix: new_prefix(), config: config}}

      {:error, :not_configured} ->
        {:error, "The upload sandbox isn't configured yet."}
    end
  end

  @impl true
  def reap(%{config: config, bucket: bucket, prefix: prefix}) do
    case S3.delete_prefix(config, bucket, prefix) do
      {:ok, _report} ->
        :ok

      {:error, reason} ->
        Logger.error("[S3Sandbox] prefix reap failed for #{prefix}: #{inspect(reason)}")
        :ok
    end
  end

  @impl true
  def payload(%{bucket: bucket, prefix: prefix}), do: %{bucket: bucket, prefix: prefix}

  @doc "A fresh, unguessable session prefix: `sessions/<128-bit>/`."
  @spec new_prefix() :: String.t()
  def new_prefix do
    random =
      16
      |> :crypto.strong_rand_bytes()
      |> Base.url_encode64(padding: false)
      |> String.replace(~r/[^A-Za-z0-9]/, "")

    "sessions/" <> random <> "/"
  end
end
