defmodule Lantern.GuardedSqlTest do
  @moduledoc """
  Unit tests for `Lantern.Explorer.destructive_sql?/1` — the safety boundary for
  the `:guarded` SQL workspace mode. Pure (no database), so it runs in the default
  suite, not just `--include integration`.
  """
  use ExUnit.Case, async: true

  alias Lantern.Explorer

  describe "destructive_sql?/1 — flags a confirm" do
    test "DROP / TRUNCATE in any case or leading whitespace" do
      assert Explorer.destructive_sql?("DROP TABLE users")
      assert Explorer.destructive_sql?("drop table users")
      assert Explorer.destructive_sql?("   \n  DROP  TABLE users")
      assert Explorer.destructive_sql?("TRUNCATE users")
      assert Explorer.destructive_sql?("truncate table users restart identity")
    end

    test "DELETE / UPDATE without a WHERE clause (full-table wipe/rewrite)" do
      assert Explorer.destructive_sql?("DELETE FROM users")
      assert Explorer.destructive_sql?("update users set active = false")
    end

    test "a table named 'wherehouse' does not slip a WHERE-less DELETE through" do
      assert Explorer.destructive_sql?("delete from wherehouse")
    end
  end

  describe "destructive_sql?/1 — does not flag" do
    test "DELETE / UPDATE that carry a real WHERE clause" do
      refute Explorer.destructive_sql?("DELETE FROM users WHERE id = 1")
      refute Explorer.destructive_sql?("update users set active = false where id = 1")
    end

    test "reads and inserts" do
      refute Explorer.destructive_sql?("SELECT * FROM users")
      refute Explorer.destructive_sql?("explain analyze select 1")
      refute Explorer.destructive_sql?("INSERT INTO users (name) VALUES ('Ada')")
    end

    test "non-binary input is safe" do
      refute Explorer.destructive_sql?(nil)
      refute Explorer.destructive_sql?(123)
    end
  end
end
