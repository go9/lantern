defmodule Lantern.ConnectionTest do
  @moduledoc """
  Covers the one thing `Lantern.Connection` must never do again: report a real,
  nameable connect failure as a generic pool timeout.

  No database required. `Postgrex.start_link/1` only boots a *pool* and reports
  `{:ok, pid}` without ever having connected, so pointing a source at a closed
  port reproduces the exact production shape — the pool sits there retrying, and
  every query against it fails with a `DBConnection.ConnectionError` describing
  our queue. The real reason is only ever logged.

  Each `run/2` against an unreachable host has to wait out that pool timeout
  (seconds), so the tests that only inspect the message share a single one.
  """
  use ExUnit.Case, async: true

  alias Lantern.Connection
  alias Lantern.Errors

  # Port 1 is reserved and never listening, so a connect is refused immediately.
  # That makes the *pool's* failure and the *probe's* failure the same underlying
  # event, which is the whole point: only one of them can name it.
  @unreachable "postgres://someone:secret@127.0.0.1:1/some_db"

  setup_all do
    parent = self()

    # Mirrors the real call shape: every caller (see `Lantern.Explorer`) runs a
    # query through the connection and renders whatever comes back through
    # `Errors.humanize/1`. Reproducing both halves is what makes this a test of
    # the copy a *user* ends up reading, rather than of an internal return value.
    result =
      Connection.run(@unreachable, fn conn ->
        send(parent, :fun_ran)
        Postgrex.query(conn, "SELECT 1", [])
      end)

    fun_ran? =
      receive do
        :fun_ran -> true
      after
        0 -> false
      end

    copy =
      case result do
        {:error, reason} -> Errors.humanize(reason)
        other -> flunk("expected an error from an unreachable database, got: #{inspect(other)}")
      end

    %{copy: copy, fun_ran?: fun_ran?}
  end

  describe "a database that can't be connected to" do
    test "surfaces the real connect error, not the pool's queue timeout", %{copy: copy} do
      # What the user actually wants to know: the connection was refused.
      assert copy =~ "tcp connect (127.0.0.1:1)"
      assert copy =~ "econnrefused"

      # The regression this test exists for. Pre-fix, the pool's checkout timeout
      # was the only thing a caller ever saw, so it humanized to the generic copy
      # and every one of these held instead.
      refute copy == Errors.connection_error()
      refute copy =~ "Couldn't connect"
      refute copy =~ "dropped from queue"
      refute copy =~ "pool_size"
    end

    test "never leaks a raw struct into the copy", %{copy: copy} do
      assert is_binary(copy)
      refute copy =~ "DBConnection"
      refute copy =~ "ConnectionError"
      refute copy =~ "%"
    end

    test "does not run the caller's function against a connection that never opened",
         %{fun_ran?: fun_ran?} do
      # Pre-fix, the `SET search_path` failure was discarded and `fun` was handed
      # a pool that had never connected — so its query bought a second, identical
      # queue timeout. That was the second half of the ~8s users waited.
      refute fun_ran?
    end

    test "leaves the caller's process untouched" do
      # `Postgrex.Protocol.connect/1` sets `trap_exit`, relabels the process, and
      # puts its socket in active mode. Running it inline would do all of that to
      # a host LiveView, so it must happen in a throwaway process instead. Needs
      # its own `run/2`: these are assertions about *this* process.
      {:trap_exit, trap_exit_before} = Process.info(self(), :trap_exit)
      label_before = Process.get(:"$process_label")

      assert {:error, _message} = Connection.run(@unreachable, fn conn -> {:ok, conn} end)

      assert Process.info(self(), :trap_exit) == {:trap_exit, trap_exit_before}
      assert Process.get(:"$process_label") == label_before

      # Nor may the probe leave anything in the caller's mailbox.
      assert {:messages, []} = Process.info(self(), :messages)
    end
  end

  describe "a source that can't be resolved" do
    test "reports the resolution error rather than probing" do
      assert {:error, "Connection URL must start with postgres:// or postgresql://"} =
               Connection.run("mysql://root@localhost/app", fn conn -> {:ok, conn} end)
    end
  end
end
