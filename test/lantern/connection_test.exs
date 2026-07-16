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
    # `fun` returns a value nothing else can produce, so the result alone shows
    # whether it ran.
    %{result: Connection.run(@unreachable, fn conn -> {:fun_ran, conn} end)}
  end

  describe "a database that can't be connected to" do
    test "surfaces the real connect error, not the pool's queue timeout", %{result: result} do
      assert {:error, message} = result

      # What the user actually wants to know: the connection was refused.
      assert message =~ "tcp connect (127.0.0.1:1)"
      assert message =~ "econnrefused"

      # The regression this test exists for. Pre-fix, `Postgrex.query/3`'s queue
      # timeout reached `Errors.humanize/1` as a bare
      # `%DBConnection.ConnectionError{}` and every one of these held instead.
      refute message == Errors.connection_error()
      refute message =~ "Couldn't connect"
      refute message =~ "dropped from queue"
      refute message =~ "pool_size"
    end

    test "never leaks a raw struct into the copy", %{result: result} do
      assert {:error, message} = result

      assert is_binary(message)
      refute message =~ "DBConnection"
      refute message =~ "ConnectionError"
      refute message =~ "%"
    end

    test "does not run the caller's function when there is no connection", %{result: result} do
      # Pre-fix, the `SET search_path` failure was discarded and `fun` ran anyway
      # against a dead pool — buying a second identical queue timeout (the ~8s
      # users saw) only to fail the same way. Had it run, the result would be
      # `{:fun_ran, conn}`.
      assert {:error, _message} = result
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
