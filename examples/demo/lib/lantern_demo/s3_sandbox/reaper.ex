defmodule LanternDemo.S3Sandbox.Reaper do
  @moduledoc """
  Backstop sweep for the S3 upload sandbox (flicker #986, invariant 5).

  The primary teardown is `PrefixProvider.reap/1`, which runs on every session
  release / TTL expiry / owner death. This periodic sweep only exists to catch
  prefixes leaked by an abnormal exit: every ~5 min it deletes objects under
  `sessions/` whose `last_modified` is older than `@orphan_age_seconds` (well
  past the 10-min session TTL). Fail-safe: anything whose age can't be positively
  determined is left alone.

  Self-gating: does nothing until the sandbox is configured, so an unconfigured
  deploy is a no-op.
  """

  use GenServer

  require Logger

  alias LanternDemo.S3Sandbox.Storage
  alias LanternS3.Storage.S3

  @sweep_interval_ms 5 * 60 * 1_000
  @orphan_age_seconds 30 * 60

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    if Storage.configured?(), do: sweep()
    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :sweep, @sweep_interval_ms)

  defp sweep do
    with {:ok, config} <- Storage.s3_config(),
         bucket = Storage.bucket(),
         {:ok, %{files: files}} <- S3.list(config, bucket, "sessions/", []) do
      cutoff = DateTime.add(DateTime.utc_now(), -@orphan_age_seconds, :second)
      stale = for file <- files, stale?(file, cutoff), do: file.key

      case stale do
        [] ->
          :ok

        keys ->
          Logger.info("[S3Sandbox.Reaper] deleting #{length(keys)} orphaned object(s)")
          S3.delete_many(config, bucket, keys)
      end
    else
      _ -> :ok
    end
  end

  # Only delete when we can positively confirm the object predates the cutoff.
  defp stale?(%{last_modified: last_modified}, cutoff) when is_binary(last_modified) do
    case DateTime.from_iso8601(last_modified) do
      {:ok, dt, _offset} -> DateTime.compare(dt, cutoff) == :lt
      _ -> false
    end
  end

  defp stale?(_file, _cutoff), do: false
end
