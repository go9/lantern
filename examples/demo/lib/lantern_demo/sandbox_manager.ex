defmodule LanternDemo.SandboxManager do
  @moduledoc """
  Admission control for the public demo sandboxes: a fixed number of concurrent
  slots per pool with a FIFO wait queue, per-slot TTL, and owner-process
  monitoring. Resource-agnostic — each pool names a `LanternDemo.Sandbox.Provider`
  that provisions/reaps the real thing (a Postgres branch for `:db`, an
  ephemeral bucket for `:s3`).

  ## Pools

  Both the DB and S3 demos share this engine, so both are slot-limited **and**
  queued. Defaults: 5 concurrent slots per pool, a wait queue up to 20, a
  300-second TTL. Overridable via `start_link/1` opts or app env
  (`config :lantern_demo, LanternDemo.SandboxManager, ...`).

  ## Grant vs. queue

  `claim/3` replies `{:granted, %{ref, ttl, payload}}` immediately when a slot
  is free, otherwise `{:queued, %{ref, position}}` (or `{:error, :queue_full}`).
  A queued caller is later messaged directly (single node, no PubSub):

    * `{:queue_position, ref, position}` — position moved
    * `{:sandbox_granted, ref, %{ttl, payload}}` — a slot opened, resource ready
    * `{:sandbox_failed, ref, reason}` — provisioning failed on grant
    * `{:sandbox_expired, ref}` — TTL elapsed on an active slot

  A slot is released on `release/2`, on TTL expiry, or when the owning process
  dies (monitor). Queued callers are dropped from the queue when they die.

  ## Single node

  Slot/queue state is per-instance. The demo app must run a single replica.
  """

  use GenServer, restart: :permanent

  require Logger

  @ttl_seconds 300
  @queue_max 20
  @default_pools %{db: [max: 5, provider: LanternDemo.Sandbox.DbProvider]}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Requests a slot in `pool` for `caller_pid`. Grants immediately if a slot is
  free, otherwise enqueues (FIFO) and reports the position.
  """
  @spec claim(GenServer.server(), atom(), pid()) ::
          {:granted, %{ref: reference(), ttl: pos_integer(), payload: map()}}
          | {:queued, %{ref: reference(), position: pos_integer()}}
          | {:error, term()}
  def claim(server \\ __MODULE__, pool, caller_pid) do
    GenServer.call(server, {:claim, pool, caller_pid, queue: true}, 60_000)
  end

  @doc "Releases an active slot or leaves the queue, whichever `ref` refers to."
  @spec release(GenServer.server(), reference()) :: :ok
  def release(server \\ __MODULE__, ref) do
    GenServer.cast(server, {:release, ref})
  end

  # --- Legacy DB-demo API (no queue) — kept so DemoLive is unchanged. ---

  @doc false
  @spec start(pid()) ::
          {:ok, %{url: String.t(), ref: reference(), ttl: pos_integer()}} | {:error, String.t()}
  def start(caller_pid) do
    case GenServer.call(__MODULE__, {:claim, :db, caller_pid, queue: false}, 60_000) do
      {:granted, %{ref: ref, ttl: ttl, payload: %{url: url}}} ->
        {:ok, %{url: url, ref: ref, ttl: ttl}}

      {:error, reason} when reason in [:at_capacity, :queue_full] ->
        {:error, "Demo is at capacity — try again in a few minutes."}

      {:error, reason} when is_binary(reason) ->
        {:error, reason}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  @doc false
  @spec stop(reference()) :: :ok
  def stop(ref), do: release(__MODULE__, ref)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    cfg = Application.get_env(:lantern_demo, __MODULE__, [])

    state = %{
      ttl_seconds: opts[:ttl_seconds] || cfg[:ttl_seconds] || @ttl_seconds,
      queue_max: opts[:queue_max] || cfg[:queue_max] || @queue_max,
      pools: normalize_pools(opts[:pools] || cfg[:pools] || @default_pools),
      active: %{},
      queues: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:claim, pool, pid, opts}, _from, state) do
    case Map.fetch(state.pools, pool) do
      :error ->
        {:reply, {:error, :unknown_pool}, state}

      {:ok, %{max: max, provider: provider}} ->
        if active_count(state, pool) < max do
          grant_now(state, pool, provider, pid)
        else
          enqueue(state, pool, pid, Keyword.get(opts, :queue, true))
        end
    end
  end

  @impl true
  def handle_cast({:release, ref}, state) do
    if Map.has_key?(state.active, ref) do
      {pool, state} = deactivate(state, ref)
      {:noreply, promote(state, pool)}
    else
      {:noreply, remove_from_queues(state, &(&1.ref == ref))}
    end
  end

  @impl true
  def handle_info({:expire, ref}, state) do
    case Map.fetch(state.active, ref) do
      {:ok, %{pid: pid}} ->
        Logger.info("[SandboxManager] slot expired: #{inspect(ref)}")
        send(pid, {:sandbox_expired, ref})
        {pool, state} = deactivate(state, ref)
        {:noreply, promote(state, pool)}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, monitor, :process, _pid, _reason}, state) do
    case find_active_by_monitor(state, monitor) do
      {ref, _entry} ->
        Logger.info("[SandboxManager] owner down, releasing: #{inspect(ref)}")
        {pool, state} = deactivate(state, ref)
        {:noreply, promote(state, pool)}

      nil ->
        {:noreply, remove_from_queues(state, &(&1.monitor == monitor))}
    end
  end

  # ---------------------------------------------------------------------------
  # Grant / enqueue
  # ---------------------------------------------------------------------------

  defp grant_now(state, pool, provider, pid) do
    ref = make_ref()
    monitor = Process.monitor(pid)

    case provision(provider) do
      {:ok, resource} ->
        state = activate(state, pool, provider, ref, pid, monitor, resource)
        reply = %{ref: ref, ttl: pool_ttl(state, pool), payload: provider.payload(resource)}
        {:reply, {:granted, reply}, state}

      {:error, reason} ->
        Process.demonitor(monitor, [:flush])
        {:reply, {:error, reason}, state}
    end
  end

  defp enqueue(state, _pool, _pid, false), do: {:reply, {:error, :at_capacity}, state}

  defp enqueue(state, pool, pid, true) do
    queue = Map.get(state.queues, pool, [])

    if length(queue) >= state.queue_max do
      {:reply, {:error, :queue_full}, state}
    else
      ref = make_ref()
      monitor = Process.monitor(pid)
      queue = queue ++ [%{ref: ref, pid: pid, monitor: monitor}]
      state = put_in(state.queues[pool], queue)
      {:reply, {:queued, %{ref: ref, position: length(queue)}}, state}
    end
  end

  # Fill any free slots in `pool` from the head of its queue (FIFO).
  defp promote(state, pool) do
    %{max: max} = Map.fetch!(state.pools, pool)
    queue = Map.get(state.queues, pool, [])

    cond do
      active_count(state, pool) >= max -> state
      queue == [] -> state
      true -> promote_head(state, pool, queue)
    end
  end

  defp promote_head(state, pool, [head | rest]) do
    provider = state.pools[pool].provider
    state = put_in(state.queues[pool], rest)

    case provision(provider) do
      {:ok, resource} ->
        state = activate(state, pool, provider, head.ref, head.pid, head.monitor, resource)

        send(
          head.pid,
          {:sandbox_granted, head.ref,
           %{ttl: pool_ttl(state, pool), payload: provider.payload(resource)}}
        )

        state |> rebroadcast_positions(pool) |> promote(pool)

      {:error, reason} ->
        Process.demonitor(head.monitor, [:flush])
        send(head.pid, {:sandbox_failed, head.ref, reason})
        state |> rebroadcast_positions(pool) |> promote(pool)
    end
  end

  # ---------------------------------------------------------------------------
  # Active-slot bookkeeping
  # ---------------------------------------------------------------------------

  defp activate(state, pool, provider, ref, pid, monitor, resource) do
    timer = Process.send_after(self(), {:expire, ref}, pool_ttl(state, pool) * 1_000)

    entry = %{
      pool: pool,
      pid: pid,
      monitor: monitor,
      timer: timer,
      resource: resource,
      provider: provider
    }

    put_in(state.active[ref], entry)
  end

  defp deactivate(state, ref) do
    case Map.pop(state.active, ref) do
      {nil, state} ->
        {nil, state}

      {entry, active} ->
        Process.cancel_timer(entry.timer)
        Process.demonitor(entry.monitor, [:flush])
        reap(entry.provider, entry.resource)
        {entry.pool, %{state | active: active}}
    end
  end

  defp remove_from_queues(state, match_fun) do
    Enum.reduce(state.queues, state, fn {pool, queue}, acc ->
      case Enum.find(queue, match_fun) do
        nil ->
          acc

        entry ->
          Process.demonitor(entry.monitor, [:flush])
          acc = put_in(acc.queues[pool], List.delete(queue, entry))
          rebroadcast_positions(acc, pool)
      end
    end)
  end

  defp rebroadcast_positions(state, pool) do
    state.queues
    |> Map.get(pool, [])
    |> Enum.with_index(1)
    |> Enum.each(fn {entry, position} ->
      send(entry.pid, {:queue_position, entry.ref, position})
    end)

    state
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp active_count(state, pool) do
    Enum.count(state.active, fn {_ref, entry} -> entry.pool == pool end)
  end

  defp find_active_by_monitor(state, monitor) do
    Enum.find(state.active, fn {_ref, entry} -> entry.monitor == monitor end)
  end

  defp normalize_pools(pools) do
    Map.new(pools, fn {key, cfg} ->
      {key,
       %{
         max: Keyword.fetch!(cfg, :max),
         provider: Keyword.fetch!(cfg, :provider),
         ttl: Keyword.get(cfg, :ttl_seconds)
       }}
    end)
  end

  # Per-pool TTL override (pool config `:ttl_seconds`), else the manager default.
  defp pool_ttl(state, pool), do: state.pools[pool][:ttl] || state.ttl_seconds

  defp provision(provider) do
    provider.provision()
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, _ -> {:error, "provisioning failed"}
  end

  defp reap(provider, resource) do
    provider.reap(resource)
  rescue
    error -> Logger.error("[SandboxManager] reap failed: #{Exception.message(error)}")
  catch
    :exit, _ -> Logger.error("[SandboxManager] reap exited")
  end
end
