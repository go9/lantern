defmodule LanternDemo.SandboxManager do
  @moduledoc """
  Manages short-lived Postgres database sandboxes for demo visitors.

  Each sandbox is a fresh copy of the demo seed data. It expires after
  @ttl_seconds and is dropped automatically. If the owning LiveView
  disconnects first, it calls stop/1 to release the sandbox immediately.
  """

  use GenServer, restart: :permanent

  require Logger

  @ttl_seconds 300
  @max_concurrent 10

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, Keyword.put(opts, :name, __MODULE__))
  end

  @doc """
  Creates a sandbox for the given LiveView PID. Returns
  `{:ok, %{url: url, ref: ref, ttl: seconds}}` or `{:error, reason}`.
  """
  @spec start(pid()) :: {:ok, %{url: String.t(), ref: reference(), ttl: pos_integer()}} | {:error, String.t()}
  def start(caller_pid) do
    GenServer.call(__MODULE__, {:start, caller_pid}, 60_000)
  end

  @doc "Releases a sandbox immediately (LiveView disconnect or user reset)."
  @spec stop(reference()) :: :ok
  def stop(ref) do
    GenServer.cast(__MODULE__, {:stop, ref})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:start, _caller_pid}, _from, state) when map_size(state) >= @max_concurrent do
    {:reply, {:error, "Demo is at capacity — try again in a few minutes."}, state}
  end

  def handle_call({:start, caller_pid}, _from, state) do
    case LanternDemo.DemoDB.create_sandbox() do
      {:ok, url, sandbox_id} ->
        ref = make_ref()
        timer = Process.send_after(self(), {:expire, ref}, @ttl_seconds * 1_000)
        Process.monitor(caller_pid)
        entry = %{sandbox_id: sandbox_id, timer: timer, pid: caller_pid}
        {:reply, {:ok, %{url: url, ref: ref, ttl: @ttl_seconds}}, Map.put(state, ref, entry)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:stop, ref}, state) do
    {:noreply, drop_sandbox(state, ref)}
  end

  @impl true
  def handle_info({:expire, ref}, state) do
    Logger.info("[SandboxManager] sandbox expired: #{inspect(ref)}")
    {:noreply, drop_sandbox(state, ref)}
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, pid, _reason}, state) do
    case Enum.find(state, fn {_ref, entry} -> entry.pid == pid end) do
      {ref, _entry} ->
        Logger.info("[SandboxManager] LiveView down, releasing sandbox: #{inspect(ref)}")
        {:noreply, drop_sandbox(state, ref)}

      nil ->
        {:noreply, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp drop_sandbox(state, ref) do
    case Map.pop(state, ref) do
      {nil, state} ->
        state

      {entry, state} ->
        Process.cancel_timer(entry.timer)
        LanternDemo.DemoDB.drop_sandbox(entry.sandbox_id)
        state
    end
  end
end
