defmodule LanternDemo.SandboxManagerTest do
  use ExUnit.Case, async: true

  alias LanternDemo.SandboxManager

  # A provider that always provisions. Reaps notify the test via a resource-
  # carried pid so we can assert teardown happened.
  defmodule OkProvider do
    @behaviour LanternDemo.Sandbox.Provider

    @impl true
    def provision, do: {:ok, %{id: System.unique_integer([:positive])}}

    @impl true
    def reap(_resource), do: :ok

    @impl true
    def payload(%{id: id}), do: %{id: id}
  end

  defmodule FailProvider do
    @behaviour LanternDemo.Sandbox.Provider

    @impl true
    def provision, do: {:error, "boom"}

    @impl true
    def reap(_resource), do: :ok

    @impl true
    def payload(_resource), do: %{}
  end

  # Starts an isolated manager under a unique name so tests stay async-safe.
  defp start_manager(opts) do
    name = :"sbm_#{System.unique_integer([:positive])}"
    pid = start_supervised!({SandboxManager, Keyword.put(opts, :name, name)})
    pid
  end

  # A process whose only job is to relay every message it receives back to the
  # test, tagged with `id`, so we can assert on messages the manager sends to a
  # queued/active owner. Plain spawn (not linked) so killing it can't take the
  # test down.
  defp caller(id) do
    test = self()
    spawn(fn -> relay(test, id) end)
  end

  defp relay(test, id) do
    receive do
      msg ->
        send(test, {id, msg})
        relay(test, id)
    end
  end

  defp pools(max, provider \\ OkProvider), do: %{db: [max: max, provider: provider]}

  describe "grant vs. queue" do
    test "grants up to `max`, then queues with increasing positions" do
      mgr = start_manager(pools: pools(2), ttl_seconds: 3600)
      c1 = caller(:c1)
      c2 = caller(:c2)
      c3 = caller(:c3)
      c4 = caller(:c4)

      assert {:granted, %{ref: _}} = SandboxManager.claim(mgr, :db, c1)
      assert {:granted, %{ref: _}} = SandboxManager.claim(mgr, :db, c2)
      assert {:queued, %{position: 1, ref: _}} = SandboxManager.claim(mgr, :db, c3)
      assert {:queued, %{position: 2, ref: _}} = SandboxManager.claim(mgr, :db, c4)
    end

    test "releasing an active slot grants the queue head (FIFO) and re-broadcasts positions" do
      mgr = start_manager(pools: pools(2), ttl_seconds: 3600)
      c1 = caller(:c1)
      c2 = caller(:c2)
      c3 = caller(:c3)
      c4 = caller(:c4)

      {:granted, %{ref: r1}} = SandboxManager.claim(mgr, :db, c1)
      {:granted, %{ref: _r2}} = SandboxManager.claim(mgr, :db, c2)
      {:queued, %{ref: r3}} = SandboxManager.claim(mgr, :db, c3)
      {:queued, %{ref: r4}} = SandboxManager.claim(mgr, :db, c4)

      SandboxManager.release(mgr, r1)

      # Head of queue (c3) is granted.
      assert_receive {:c3, {:sandbox_granted, ^r3, %{ttl: 3600, payload: %{id: _}}}}
      # The remaining queued caller (c4) moves up to position 1.
      assert_receive {:c4, {:queue_position, ^r4, 1}}
    end

    test "unknown pool is rejected" do
      mgr = start_manager(pools: pools(2))
      assert {:error, :unknown_pool} = SandboxManager.claim(mgr, :s3, self())
    end

    test "queue full is rejected once queue_max is reached" do
      mgr = start_manager(pools: pools(1), queue_max: 1, ttl_seconds: 3600)

      assert {:granted, _} = SandboxManager.claim(mgr, :db, caller(:a))
      assert {:queued, %{position: 1}} = SandboxManager.claim(mgr, :db, caller(:b))
      assert {:error, :queue_full} = SandboxManager.claim(mgr, :db, caller(:c))
    end
  end

  describe "provisioning failure" do
    test "a failing provider surfaces the error and holds no slot" do
      mgr = start_manager(pools: pools(2, FailProvider))
      assert {:error, "boom"} = SandboxManager.claim(mgr, :db, caller(:x))
      # Slot was not consumed: a second attempt still reaches the provider (also fails).
      assert {:error, "boom"} = SandboxManager.claim(mgr, :db, caller(:y))
    end
  end

  describe "process death" do
    test "a queued owner that dies is dropped and positions re-broadcast" do
      mgr = start_manager(pools: pools(1), ttl_seconds: 3600)
      _a = SandboxManager.claim(mgr, :db, caller(:a))

      c_dies = caller(:dies)
      c_after = caller(:after)
      {:queued, %{position: 1}} = SandboxManager.claim(mgr, :db, c_dies)
      {:queued, %{position: 2, ref: r_after}} = SandboxManager.claim(mgr, :db, c_after)

      Process.exit(c_dies, :kill)

      # The survivor advances to position 1.
      assert_receive {:after, {:queue_position, ^r_after, 1}}
    end

    test "an active owner that dies frees its slot for the queue head" do
      mgr = start_manager(pools: pools(1), ttl_seconds: 3600)

      c1 = caller(:c1)
      {:granted, _} = SandboxManager.claim(mgr, :db, c1)

      c2 = caller(:c2)
      {:queued, %{ref: r2}} = SandboxManager.claim(mgr, :db, c2)

      Process.exit(c1, :kill)

      assert_receive {:c2, {:sandbox_granted, ^r2, _}}
    end
  end

  describe "expiry" do
    test "an active slot expires after its TTL, notifies the owner, and frees the slot" do
      # 50ms TTL keeps the test fast.
      mgr = start_manager(pools: pools(1), ttl_seconds: 0, queue_max: 5)
      # ttl_seconds: 0 -> send_after 0ms -> immediate expiry.
      c1 = caller(:c1)
      {:granted, %{ref: r1}} = SandboxManager.claim(mgr, :db, c1)

      assert_receive {:c1, {:sandbox_expired, ^r1}}

      # Slot is free again after expiry.
      assert {:granted, _} = SandboxManager.claim(mgr, :db, caller(:c2))
    end
  end
end
