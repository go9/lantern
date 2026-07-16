defmodule Lantern.ErrorsTest do
  @moduledoc """
  Unit tests for `Lantern.Errors.humanize/1` — the single chokepoint that keeps
  raw error structs out of the UI. Pure (no database), so they run in the default
  suite, not just `--include integration`.
  """
  use ExUnit.Case, async: true

  alias Lantern.Errors

  describe "connection failures → friendly copy, never a struct" do
    test "a DBConnection.ConnectionError (the flicker :queue_timeout case) is humanized" do
      result = Errors.humanize(%DBConnection.ConnectionError{message: "connection not available"})

      assert result == Errors.connection_error()
      # The regression we're guarding: no struct/internals leak into the UI.
      refute result =~ "DBConnection"
      refute result =~ "ConnectionError"
      refute result =~ "queue_timeout"
      refute result =~ "%"
    end

    test "bare connection reasons map to the friendly copy" do
      for reason <- [
            :queue_timeout,
            :timeout,
            :closed,
            :killed,
            :disconnected,
            :econnrefused,
            :nxdomain
          ] do
        assert Errors.humanize(reason) == Errors.connection_error()
      end
    end

    test "a {:shutdown, _} exit reason maps to the friendly copy" do
      assert Errors.humanize({:shutdown, :db_termination}) == Errors.connection_error()
    end

    test "connection_error/0 reads as honest, plain copy" do
      copy = Errors.connection_error()
      assert copy =~ "Couldn't connect"
      refute copy =~ "—"
    end
  end

  describe "Postgres query errors → clean message plus a hint" do
    test "surfaces the Postgres message" do
      error = %Postgrex.Error{postgres: %{message: ~s(relation "widgets" does not exist)}}
      assert Errors.humanize(error) =~ ~s(relation "widgets" does not exist)
    end

    test "appends a SQLSTATE-derived hint when Postgres sent none" do
      error = %Postgrex.Error{
        postgres: %{message: ~s(relation "widgets" does not exist), code: :undefined_table}
      }

      result = Errors.humanize(error)
      assert result =~ ~s(relation "widgets" does not exist)
      assert result =~ "Hint:"
      assert result =~ "table doesn't exist"
      # Message and hint are separated onto their own lines.
      assert result =~ "\n"
    end

    test "prefers Postgres's own HINT when present" do
      error = %Postgrex.Error{
        postgres: %{
          message: "duplicate key value",
          code: :unique_violation,
          hint: "Use ON CONFLICT"
        }
      }

      result = Errors.humanize(error)
      assert result =~ "duplicate key value"
      assert result =~ "Hint: Use ON CONFLICT"
    end

    test "maps common SQLSTATE codes to hints" do
      for {code, fragment} <- [
            {:undefined_column, "column doesn't exist"},
            {:syntax_error, "syntax error"},
            {:insufficient_privilege, "isn't allowed"},
            {:not_null_violation, "NOT NULL"},
            {:foreign_key_violation, "foreign key"},
            {:check_violation, "CHECK constraint"}
          ] do
        error = %Postgrex.Error{postgres: %{message: "boom", code: code}}
        assert Errors.humanize(error) =~ fragment
      end
    end

    test "a Postgrex.Error without a postgres map falls back to its message" do
      assert Errors.humanize(%Postgrex.Error{message: "decode error"}) == "decode error"
    end
  end

  describe "humanize_connect_error/1 — errors from a direct connect attempt" do
    test "surfaces a Postgres FATAL that the pool would have masked as a timeout" do
      # Both captured live, from branches that previously only ever produced a
      # generic pool queue_timeout.
      for {code, message} <- [
            {:connection_failure, "the database failed to resume; please retry"},
            {:invalid_password, ~s(password authentication failed for user "postgres")}
          ] do
        error = %Postgrex.Error{postgres: %{code: code, message: message, severity: "FATAL"}}

        result = Errors.humanize_connect_error(error)

        assert result =~ message
        refute result == Errors.connection_error()
      end
    end

    test "surfaces a direct connect's socket-level reason" do
      # The distinction from humanize/1: from a *pool* this struct means "no
      # connection was available" and is noise; from a direct connect it is the
      # actual reason, and the only useful thing we have.
      error = %DBConnection.ConnectionError{
        message: "tcp connect (db.example.com:5432): non-existing domain - :nxdomain"
      }

      result = Errors.humanize_connect_error(error)

      assert result =~ "non-existing domain"
      assert result =~ "db.example.com:5432"
      refute result == Errors.connection_error()
    end

    test "humanize/1 still masks that same struct, because a pool's copy is noise" do
      pool_error = %DBConnection.ConnectionError{
        message: "connection not available and request was dropped from queue after 5991ms",
        reason: :queue_timeout
      }

      assert Errors.humanize(pool_error) == Errors.connection_error()
    end

    test "falls back to the friendly copy when there is no message to show" do
      assert Errors.humanize_connect_error(%DBConnection.ConnectionError{message: ""}) ==
               Errors.connection_error()
    end

    test "defers to humanize/1 for everything else, hints included" do
      error = %Postgrex.Error{postgres: %{message: "boom", code: :insufficient_privilege}}

      result = Errors.humanize_connect_error(error)

      assert result =~ "boom"
      assert result =~ "isn't allowed"
    end
  end

  describe "other inputs" do
    test "a binary passes through unchanged" do
      assert Errors.humanize("already friendly") == "already friendly"
    end

    test "a generic exception uses its message, not the struct" do
      assert Errors.humanize(%RuntimeError{message: "boom"}) == "boom"
    end

    test "an unknown non-struct reason is inspected (short and safe, no struct dump)" do
      result = Errors.humanize(:some_unexpected_atom)
      assert is_binary(result)
      assert result =~ "some_unexpected_atom"
    end
  end
end
