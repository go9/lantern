defmodule LanternTest do
  @moduledoc """
  Integration tests exercising real Postgres round-trips.

  They connect to `Lantern.TestDB.url/0` and manage their own fixture tables.
  Tagged `:integration` so they are excluded unless run with
  `mix test --include integration`.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  @table "lantern_itest"
  @schema "lantern_alt_schema_itest"
  @schema_table "widgets"

  setup_all do
    source = repo_source()

    with_raw_conn(source, fn conn ->
      Postgrex.query!(conn, "DROP SCHEMA IF EXISTS #{@schema} CASCADE", [])
      Postgrex.query!(conn, "DROP TABLE IF EXISTS #{@table}", [])

      Postgrex.query!(
        conn,
        """
        CREATE TABLE #{@table} (
          id serial PRIMARY KEY,
          name text NOT NULL,
          age integer,
          active boolean,
          meta jsonb,
          born date
        )
        """,
        []
      )

      Postgrex.query!(conn, "CREATE SCHEMA #{@schema}", [])

      Postgrex.query!(
        conn,
        "CREATE TABLE #{@schema}.#{@schema_table} (id serial PRIMARY KEY, label text NOT NULL)",
        []
      )
    end)

    on_exit(fn ->
      with_raw_conn(source, fn conn ->
        Postgrex.query!(conn, "DROP SCHEMA IF EXISTS #{@schema} CASCADE", [])
        Postgrex.query!(conn, "DROP TABLE IF EXISTS #{@table}", [])
      end)
    end)

    {:ok, source: source}
  end

  setup %{source: source} do
    with_raw_conn(source, fn conn ->
      Postgrex.query!(conn, "TRUNCATE #{@table} RESTART IDENTITY", [])
      Postgrex.query!(conn, "TRUNCATE #{@schema}.#{@schema_table} RESTART IDENTITY", [])
    end)

    :ok
  end

  test "list_tables includes the fixture table", %{source: source} do
    assert {:ok, tables} = Lantern.list_tables(source)
    assert @table in tables
  end

  test "lists and queries non-public schemas", %{source: source} do
    assert {:ok, schemas} = Lantern.list_schemas(source)
    assert "public" in schemas
    assert @schema in schemas

    assert {:ok, [@schema_table]} = Lantern.list_tables(source, schema: @schema)

    assert {:ok, row} =
             Lantern.insert(source, @schema_table, %{"label" => "Alt"}, schema: @schema)

    assert row["label"] == "Alt"

    assert {:ok, page} = Lantern.query(source, @schema_table, schema: @schema)
    assert page.columns == ["id", "label"]
    assert page.count == 1
    assert List.first(page.rows) |> Enum.at(1) == "Alt"
  end

  test "public schema remains the default", %{source: source} do
    assert {:ok, tables} = Lantern.list_tables(source)
    assert @table in tables
    refute @schema_table in tables
  end

  test "table_stats returns table sizes for a schema", %{source: source} do
    {:ok, _row} = Lantern.insert(source, @table, %{"name" => "Ada"})

    assert {:ok, stats} = Lantern.table_stats(source)
    stat = Enum.find(stats, &(&1.name == @table))

    assert stat.total_bytes > 0
    assert stat.table_bytes >= 0
    assert stat.index_bytes >= 0
    assert is_binary(stat.total_size)
    assert is_binary(stat.table_size)
    assert is_binary(stat.index_size)
  end

  test "table_stats supports non-public schemas", %{source: source} do
    assert {:ok, stats} = Lantern.table_stats(source, schema: @schema)
    assert Enum.any?(stats, &(&1.name == @schema_table))
  end

  test "columns returns typed metadata", %{source: source} do
    assert {:ok, cols} = Lantern.columns(source, @table)
    names = Enum.map(cols, & &1.name)
    assert names == ~w(id name age active meta born)

    age = Enum.find(cols, &(&1.name == "age"))
    assert age.type == "integer"
    assert age.nullable == true

    name = Enum.find(cols, &(&1.name == "name"))
    assert name.nullable == false
  end

  test "primary_keys returns the pk column", %{source: source} do
    assert {:ok, ["id"]} = Lantern.primary_keys(source, @table)
  end

  test "insert casts text params into column types", %{source: source} do
    assert {:ok, row} =
             Lantern.insert(source, @table, %{
               "name" => "Ada",
               "age" => "36",
               "active" => "true",
               "meta" => ~s({"role":"admin"}),
               "born" => "1815-12-10"
             })

    assert row["name"] == "Ada"
    assert row["age"] == 36
    assert row["active"] == true
    assert row["meta"] == %{"role" => "admin"}
    assert row["born"] == ~D[1815-12-10]
  end

  test "insert with nil writes SQL NULL", %{source: source} do
    assert {:ok, row} = Lantern.insert(source, @table, %{"name" => "Bob", "age" => nil})
    assert row["age"] == nil
  end

  test "update changes a row by primary key", %{source: source} do
    {:ok, row} = Lantern.insert(source, @table, %{"name" => "Ada", "age" => "36"})

    assert {:ok, updated} =
             Lantern.update(source, @table, %{"age" => "37"}, %{"id" => to_string(row["id"])})

    assert updated["age"] == 37
    assert updated["name"] == "Ada"
  end

  test "update rejects a key that is not the primary key", %{source: source} do
    {:ok, _} = Lantern.insert(source, @table, %{"name" => "Ada"})

    assert {:error, :key_mismatch} =
             Lantern.update(source, @table, %{"age" => "1"}, %{"name" => "Ada"})
  end

  test "delete removes selected rows and returns the count", %{source: source} do
    {:ok, r1} = Lantern.insert(source, @table, %{"name" => "A"})
    {:ok, r2} = Lantern.insert(source, @table, %{"name" => "B"})
    {:ok, _r3} = Lantern.insert(source, @table, %{"name" => "C"})

    assert {:ok, 2} =
             Lantern.delete(source, @table, [
               %{"id" => to_string(r1["id"])},
               %{"id" => to_string(r2["id"])}
             ])

    assert {:ok, %{count: 1}} = Lantern.query(source, @table)
  end

  test "query filters, sorts, and paginates", %{source: source} do
    for n <- 1..5, do: Lantern.insert(source, @table, %{"name" => "u#{n}", "age" => "#{n}"})

    assert {:ok, %{rows: rows, count: count}} =
             Lantern.query(source, @table,
               where_clause: "age >= 3",
               sort_by: "age",
               sort_dir: :desc,
               limit: 2,
               offset: 0
             )

    assert count == 3
    assert length(rows) == 2
  end

  test "query supports safe parameterized filters and count off", %{source: source} do
    Lantern.insert(source, @table, %{"name" => "Ada", "age" => "36"})
    Lantern.insert(source, @table, %{"name" => "Bob", "age" => "41"})

    assert {:ok, page} =
             Lantern.query(source, @table,
               filters: [%{column: "name", op: "contains", value: "ad"}],
               count: false
             )

    assert page.count == nil
    assert page.count_kind == :none
    assert length(page.rows) == 1
    assert page.rows |> hd() |> Enum.at(1) == "Ada"
  end

  test "run_query executes trusted SQL", %{source: source} do
    assert {:ok, result} = Lantern.run_query(source, "SELECT 42 AS answer")
    assert result.columns == ["answer"]
    assert result.rows == [[42]]
  end

  test "query rejects an unknown sort column", %{source: source} do
    assert {:error, message} = Lantern.query(source, @table, sort_by: "nope")
    assert message =~ "Invalid sort column"
  end

  test "unknown column is rejected on insert", %{source: source} do
    assert {:error, message} = Lantern.insert(source, @table, %{"ghost" => "x"})
    assert message =~ "Unknown column"
  end

  test "columns expose enum values for enum-typed columns", %{source: source} do
    with_raw_conn(source, fn conn ->
      Postgrex.query!(conn, "DROP TABLE IF EXISTS lantern_enum_itest", [])
      Postgrex.query!(conn, "DROP TYPE IF EXISTS lantern_mood", [])
      Postgrex.query!(conn, "CREATE TYPE lantern_mood AS ENUM ('happy', 'sad', 'meh')", [])

      Postgrex.query!(
        conn,
        "CREATE TABLE lantern_enum_itest (id serial PRIMARY KEY, mood lantern_mood)",
        []
      )
    end)

    on_exit(fn ->
      with_raw_conn(source, fn conn ->
        Postgrex.query!(conn, "DROP TABLE IF EXISTS lantern_enum_itest", [])
        Postgrex.query!(conn, "DROP TYPE IF EXISTS lantern_mood", [])
      end)
    end)

    assert {:ok, cols} = Lantern.columns(source, "lantern_enum_itest")
    mood = Enum.find(cols, &(&1.name == "mood"))
    assert mood.enum_values == ["happy", "sad", "meh"]

    id = Enum.find(cols, &(&1.name == "id"))
    assert id.enum_values == nil
  end

  test "foreign keys are detected and reference options labelled", %{source: source} do
    with_raw_conn(source, fn conn ->
      Postgrex.query!(conn, "DROP TABLE IF EXISTS lantern_post_itest", [])
      Postgrex.query!(conn, "DROP TABLE IF EXISTS lantern_author_itest", [])

      Postgrex.query!(
        conn,
        "CREATE TABLE lantern_author_itest (id serial PRIMARY KEY, name text NOT NULL)",
        []
      )

      Postgrex.query!(
        conn,
        "CREATE TABLE lantern_post_itest (id serial PRIMARY KEY, author_id integer REFERENCES lantern_author_itest(id))",
        []
      )

      Postgrex.query!(
        conn,
        "INSERT INTO lantern_author_itest (name) VALUES ('Ada'), ('Grace')",
        []
      )
    end)

    on_exit(fn ->
      with_raw_conn(source, fn conn ->
        Postgrex.query!(conn, "DROP TABLE IF EXISTS lantern_post_itest", [])
        Postgrex.query!(conn, "DROP TABLE IF EXISTS lantern_author_itest", [])
      end)
    end)

    assert {:ok, cols} = Lantern.columns(source, "lantern_post_itest")
    author = Enum.find(cols, &(&1.name == "author_id"))
    assert author.fk == %{schema: "public", table: "lantern_author_itest", column: "id"}

    id = Enum.find(cols, &(&1.name == "id"))
    assert id.fk == nil

    assert {:ok, options} = Lantern.reference_options(source, "lantern_author_itest", "id")
    assert {"1", "Ada — 1"} in options
    assert {"2", "Grace — 2"} in options
  end

  describe "DDL" do
    @ddl_table "lantern_ddl_itest"

    setup %{source: source} do
      drop = fn ->
        with_raw_conn(source, &Postgrex.query!(&1, "DROP TABLE IF EXISTS #{@ddl_table}", []))
      end

      drop.()
      on_exit(drop)
      :ok
    end

    test "create_table creates a usable, typed table with a primary key", %{source: source} do
      assert :ok =
               Lantern.create_table(source, @ddl_table, [
                 %{name: "id", type: "bigint", nullable: false, primary_key: true},
                 %{name: "label", type: "text"},
                 %{name: "qty", type: "integer", nullable: false}
               ])

      assert {:ok, tables} = Lantern.list_tables(source)
      assert @ddl_table in tables
      assert {:ok, ["id"]} = Lantern.primary_keys(source, @ddl_table)

      {:ok, cols} = Lantern.columns(source, @ddl_table)
      assert Enum.map(cols, & &1.name) == ~w(id label qty)
      assert Enum.find(cols, &(&1.name == "label")).nullable == true
      assert Enum.find(cols, &(&1.name == "qty")).nullable == false
    end

    test "create_table rejects an unsupported type without touching the db", %{source: source} do
      assert {:error, message} =
               Lantern.create_table(source, @ddl_table, [%{name: "c", type: "bogus"}])

      assert message =~ "Unsupported column type"
      {:ok, tables} = Lantern.list_tables(source)
      refute @ddl_table in tables
    end

    test "create_table rejects an empty column list", %{source: source} do
      assert {:error, message} = Lantern.create_table(source, @ddl_table, [])
      assert message =~ "at least one column"
    end

    test "drop_table removes the table", %{source: source} do
      :ok = Lantern.create_table(source, @ddl_table, [%{name: "id", type: "bigint"}])
      assert :ok = Lantern.drop_table(source, @ddl_table)
      {:ok, tables} = Lantern.list_tables(source)
      refute @ddl_table in tables
    end

    test "add / rename / drop column round-trips", %{source: source} do
      :ok = Lantern.create_table(source, @ddl_table, [%{name: "id", type: "bigint"}])

      assert :ok =
               Lantern.add_column(source, @ddl_table, %{name: "nickname", type: "varchar(20)"})

      {:ok, cols} = Lantern.columns(source, @ddl_table)
      assert "nickname" in Enum.map(cols, & &1.name)

      assert :ok = Lantern.rename_column(source, @ddl_table, "nickname", "handle")
      {:ok, cols} = Lantern.columns(source, @ddl_table)
      assert "handle" in Enum.map(cols, & &1.name)
      refute "nickname" in Enum.map(cols, & &1.name)

      assert :ok = Lantern.drop_column(source, @ddl_table, "handle")
      {:ok, cols} = Lantern.columns(source, @ddl_table)
      refute "handle" in Enum.map(cols, & &1.name)
    end

    test "alter column type and nullability round-trip", %{source: source} do
      :ok = Lantern.create_table(source, @ddl_table, [%{name: "name", type: "text"}])

      assert :ok = Lantern.alter_column_type(source, @ddl_table, "name", "varchar(255)")
      assert :ok = Lantern.set_column_nullable(source, @ddl_table, "name", false)

      {:ok, cols} = Lantern.columns(source, @ddl_table)
      name = Enum.find(cols, &(&1.name == "name"))
      assert name.type == "character varying"
      assert name.nullable == false
    end

    test "rename_table renames the table", %{source: source} do
      :ok = Lantern.create_table(source, @ddl_table, [%{name: "id", type: "bigint"}])
      renamed = "#{@ddl_table}_renamed"

      on_exit(fn ->
        with_raw_conn(source, &Postgrex.query!(&1, "DROP TABLE IF EXISTS #{renamed}", []))
      end)

      assert :ok = Lantern.rename_table(source, @ddl_table, renamed)
      {:ok, tables} = Lantern.list_tables(source)
      assert renamed in tables
      refute @ddl_table in tables
    end

    test "blank names are rejected before connecting", %{source: source} do
      assert {:error, message} = Lantern.drop_table(source, "   ")
      assert message =~ "can't be blank"
    end
  end

  defp repo_source, do: Lantern.TestDB.url()

  defp with_raw_conn(source, fun) do
    {:ok, normalized} = Lantern.Source.from(source)
    {:ok, conn} = Postgrex.start_link(Lantern.Source.to_postgrex_opts(normalized))

    try do
      fun.(conn)
    after
      GenServer.stop(conn)
    end
  end
end
