defmodule Lantern.SQLTest do
  use ExUnit.Case, async: true

  alias Lantern.SQL

  defp field(column, value, cast \\ nil), do: %{column: column, value: value, cast: cast}

  describe "quote_ident/1" do
    test "double-quotes a plain identifier" do
      assert SQL.quote_ident("users") == ~s|"users"|
    end

    test "escapes embedded double-quotes" do
      assert SQL.quote_ident(~s|we"ird|) == ~s|"we""ird"|
    end
  end

  describe "select/6" do
    test "builds a bare paginated select" do
      assert {sql, []} = SQL.select("users", nil, nil, :asc, 100, 0)
      assert sql == ~s|SELECT * FROM "users" LIMIT 100 OFFSET 0|
    end

    test "adds a where fragment when present" do
      {sql, []} = SQL.select("users", "id > 10", nil, :asc, 50, 0)
      assert sql == ~s|SELECT * FROM "users" WHERE id > 10 LIMIT 50 OFFSET 0|
    end

    test "ignores a blank where fragment" do
      {sql, []} = SQL.select("users", "   ", nil, :asc, 10, 0)
      refute sql =~ "WHERE"
    end

    test "adds ascending and descending order" do
      {asc, []} = SQL.select("users", nil, "name", :asc, 10, 0)
      {desc, []} = SQL.select("users", nil, "name", :desc, 10, 0)
      assert asc =~ ~s|ORDER BY "name" ASC|
      assert desc =~ ~s|ORDER BY "name" DESC|
    end

    test "clamps negative limit/offset to zero" do
      {sql, []} = SQL.select("users", nil, nil, :asc, -5, -9)
      assert sql =~ "LIMIT 0 OFFSET 0"
    end
  end

  describe "count/2" do
    test "counts all rows" do
      assert {sql, []} = SQL.count("users", nil)
      assert sql == ~s|SELECT COUNT(*) FROM "users"|
    end

    test "honors the where fragment" do
      {sql, []} = SQL.count("users", "active")
      assert sql == ~s|SELECT COUNT(*) FROM "users" WHERE active|
    end
  end

  describe "insert/2" do
    test "emits DEFAULT VALUES when no fields are given" do
      assert {:ok, {sql, []}} = SQL.insert("users", [])
      assert sql == ~s|INSERT INTO "users" DEFAULT VALUES RETURNING *|
    end

    test "builds a parameterized insert with casts" do
      fields = [field("name", "Ada"), field("age", "36", "integer")]
      assert {:ok, {sql, params}} = SQL.insert("users", fields)

      assert sql ==
               ~s|INSERT INTO "users" ("name", "age") VALUES ($1, $2::text::integer) RETURNING *|

      assert params == ["Ada", "36"]
    end

    test "passes nil through as a NULL parameter" do
      assert {:ok, {_sql, params}} = SQL.insert("t", [field("note", nil)])
      assert params == [nil]
    end
  end

  describe "update/3" do
    test "errors with no set fields" do
      assert {:error, :no_fields} = SQL.update("t", [], [field("id", "1", "integer")])
    end

    test "errors with no key fields" do
      assert {:error, :no_key} = SQL.update("t", [field("name", "x")], [])
    end

    test "numbers set and where placeholders sequentially" do
      set = [field("name", "Ada"), field("age", "36", "integer")]
      pk = [field("id", "7", "integer")]

      assert {:ok, {sql, params}} = SQL.update("users", set, pk)

      assert sql ==
               ~s|UPDATE "users" SET "name" = $1, "age" = $2::text::integer | <>
                 ~s|WHERE "id" = $3::text::integer RETURNING *|

      assert params == ["Ada", "36", "7"]
    end

    test "supports composite keys" do
      set = [field("qty", "5", "integer")]
      pk = [field("order_id", "1", "integer"), field("sku", "ABC")]

      {:ok, {sql, params}} = SQL.update("line_items", set, pk)
      assert sql =~ ~s|WHERE "order_id" = $2::text::integer AND "sku" = $3|
      assert params == ["5", "1", "ABC"]
    end
  end

  describe "delete/2" do
    test "errors with no rows" do
      assert {:error, :no_rows} = SQL.delete("t", [])
    end

    test "errors when a row has no key fields" do
      assert {:error, :no_key} = SQL.delete("t", [[]])
    end

    test "deletes a single row" do
      {:ok, {sql, params}} = SQL.delete("users", [[field("id", "3", "integer")]])
      assert sql == ~s|DELETE FROM "users" WHERE ("id" = $1::text::integer)|
      assert params == ["3"]
    end

    test "ORs multiple rows with sequential placeholders" do
      rows = [
        [field("id", "1", "integer")],
        [field("id", "2", "integer")]
      ]

      {:ok, {sql, params}} = SQL.delete("users", rows)

      assert sql ==
               ~s|DELETE FROM "users" WHERE ("id" = $1::text::integer) OR ("id" = $2::text::integer)|

      assert params == ["1", "2"]
    end

    test "handles composite keys across rows" do
      rows = [
        [field("a", "1", "integer"), field("b", "x")],
        [field("a", "2", "integer"), field("b", "y")]
      ]

      {:ok, {sql, params}} = SQL.delete("t", rows)
      assert sql =~ ~s|("a" = $1::text::integer AND "b" = $2)|
      assert sql =~ ~s|("a" = $3::text::integer AND "b" = $4)|
      assert params == ["1", "x", "2", "y"]
    end
  end
end
