defmodule Lantern.SQLTest do
  use ExUnit.Case, async: true

  alias Lantern.SQL

  defp field(column, value, cast \\ nil), do: %{column: column, value: value, cast: cast}

  defp col(name, type, opts \\ []), do: Enum.into(opts, %{name: name, type: type})

  describe "quote_ident/1" do
    test "double-quotes a plain identifier" do
      assert SQL.quote_ident("users") == ~s|"users"|
    end

    test "escapes embedded double-quotes" do
      assert SQL.quote_ident(~s|we"ird|) == ~s|"we""ird"|
    end

    test "quotes schema-qualified table identifiers" do
      assert SQL.quote_table("ops", "events") == ~s|"ops"."events"|
      assert SQL.quote_table(~s|we"ird|, ~s|ta"ble|) == ~s|"we""ird"."ta""ble"|
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

    test "builds schema-qualified selects" do
      {sql, []} = SQL.select("ops", "events", nil, nil, :asc, 10, 0)
      assert sql == ~s|SELECT * FROM "ops"."events" LIMIT 10 OFFSET 0|
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

  describe "validate_type/1" do
    test "accepts bare allowlisted types case-insensitively" do
      assert {:ok, "bigint"} = SQL.validate_type("BigInt")
      assert {:ok, "text"} = SQL.validate_type("  text ")
      assert {:ok, "timestamptz"} = SQL.validate_type("timestamptz")
    end

    test "normalizes internal whitespace in multi-word types" do
      assert {:ok, "double precision"} = SQL.validate_type("double   precision")
      assert {:ok, "timestamp with time zone"} = SQL.validate_type("TIMESTAMP WITH TIME ZONE")
    end

    test "accepts parameterized types whose base is allowlisted" do
      assert {:ok, "varchar(255)"} = SQL.validate_type("varchar(255)")
      assert {:ok, "numeric(10,2)"} = SQL.validate_type("numeric(10,2)")
      assert {:ok, "numeric(10, 2)"} = SQL.validate_type("numeric(10, 2)")
    end

    test "rejects unknown types and injection attempts" do
      assert :error = SQL.validate_type("text; drop table users")
      assert :error = SQL.validate_type("notatype")
      assert :error = SQL.validate_type("int[]")
      assert :error = SQL.validate_type("varchar(255); --")
      assert :error = SQL.validate_type(nil)
    end
  end

  describe "create_table/2" do
    test "errors with no columns" do
      assert {:error, :no_columns} = SQL.create_table("t", [])
    end

    test "builds a column list with NOT NULL and a primary key constraint" do
      columns = [
        col("id", "bigint", nullable: false, primary_key: true),
        col("name", "text"),
        col("age", "integer", nullable: false)
      ]

      assert {:ok, {sql, []}} = SQL.create_table("users", columns)

      assert sql ==
               ~s|CREATE TABLE "users" (| <>
                 ~s|"id" bigint NOT NULL, "name" text, "age" integer NOT NULL, | <>
                 ~s|PRIMARY KEY ("id"))|
    end

    test "supports composite primary keys" do
      columns = [
        col("order_id", "bigint", primary_key: true),
        col("sku", "text", primary_key: true)
      ]

      {:ok, {sql, []}} = SQL.create_table("line_items", columns)
      assert sql =~ ~s|PRIMARY KEY ("order_id", "sku")|
    end

    test "omits the constraint when no column is a primary key" do
      {:ok, {sql, []}} = SQL.create_table("t", [col("a", "text")])
      refute sql =~ "PRIMARY KEY"
    end

    test "quotes identifiers and rejects invalid types" do
      assert {:ok, {sql, []}} = SQL.create_table(~s|we"ird|, [col(~s|c"ol|, "text")])
      assert sql =~ ~s|CREATE TABLE "we""ird" ("c""ol" text)|

      assert {:error, {:invalid_type, "bogus"}} =
               SQL.create_table("t", [col("a", "bogus")])
    end

    test "errors when a column name is blank" do
      assert {:error, :missing_name} = SQL.create_table("t", [col("  ", "text")])
    end
  end

  describe "drop_table/1" do
    test "drops a quoted table without cascade" do
      assert {:ok, {sql, []}} = SQL.drop_table("users")
      assert sql == ~s|DROP TABLE "users"|
    end
  end

  describe "add_column/2" do
    test "adds a nullable column" do
      assert {:ok, {sql, []}} = SQL.add_column("users", col("nickname", "text"))
      assert sql == ~s|ALTER TABLE "users" ADD COLUMN "nickname" text|
    end

    test "adds a NOT NULL parameterized column" do
      {:ok, {sql, []}} = SQL.add_column("users", col("code", "varchar(8)", nullable: false))
      assert sql == ~s|ALTER TABLE "users" ADD COLUMN "code" varchar(8) NOT NULL|
    end

    test "rejects an invalid type" do
      assert {:error, {:invalid_type, "bogus"}} =
               SQL.add_column("users", col("c", "bogus"))
    end
  end

  describe "drop_column/2" do
    test "drops a quoted column" do
      assert {:ok, {sql, []}} = SQL.drop_column("users", "nickname")
      assert sql == ~s|ALTER TABLE "users" DROP COLUMN "nickname"|
    end
  end

  describe "alter_column_type/3" do
    test "changes a column to a parameterized type" do
      assert {:ok, {sql, []}} = SQL.alter_column_type("users", "nickname", "varchar(255)")
      assert sql == ~s|ALTER TABLE "users" ALTER COLUMN "nickname" TYPE varchar(255)|
    end

    test "rejects an invalid type" do
      assert {:error, {:invalid_type, "bogus"}} = SQL.alter_column_type("users", "c", "bogus")
    end
  end

  describe "set_column_nullable/3" do
    test "drops and sets not null" do
      assert {:ok, {sql, []}} = SQL.set_column_nullable("users", "nickname", true)
      assert sql == ~s|ALTER TABLE "users" ALTER COLUMN "nickname" DROP NOT NULL|

      assert {:ok, {sql, []}} = SQL.set_column_nullable("users", "nickname", false)
      assert sql == ~s|ALTER TABLE "users" ALTER COLUMN "nickname" SET NOT NULL|
    end
  end

  describe "rename_column/3" do
    test "renames a quoted column" do
      assert {:ok, {sql, []}} = SQL.rename_column("users", "nickname", "handle")
      assert sql == ~s|ALTER TABLE "users" RENAME COLUMN "nickname" TO "handle"|
    end
  end

  describe "create_index/3 and drop_index/1" do
    test "creates and drops a quoted index" do
      assert {:ok, {sql, []}} = SQL.create_index("users", "users_email_idx", ["email"])
      assert sql == ~s|CREATE INDEX "users_email_idx" ON "users" ("email")|

      assert {:ok, {sql, []}} = SQL.drop_index("users_email_idx")
      assert sql == ~s|DROP INDEX "users_email_idx"|
    end
  end

  describe "rename_table/2" do
    test "renames a quoted table" do
      assert {:ok, {sql, []}} = SQL.rename_table("users", "accounts")
      assert sql == ~s|ALTER TABLE "users" RENAME TO "accounts"|
    end
  end
end
