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

  setup_all do
    source = repo_source()

    with_raw_conn(source, fn conn ->
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
    end)

    on_exit(fn ->
      with_raw_conn(source, fn conn ->
        Postgrex.query!(conn, "DROP TABLE IF EXISTS #{@table}", [])
      end)
    end)

    {:ok, source: source}
  end

  setup %{source: source} do
    with_raw_conn(source, fn conn ->
      Postgrex.query!(conn, "TRUNCATE #{@table} RESTART IDENTITY", [])
    end)

    :ok
  end

  test "list_tables includes the fixture table", %{source: source} do
    assert {:ok, tables} = Lantern.list_tables(source)
    assert @table in tables
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
    assert author.fk == %{table: "lantern_author_itest", column: "id"}

    id = Enum.find(cols, &(&1.name == "id"))
    assert id.fk == nil

    assert {:ok, options} = Lantern.reference_options(source, "lantern_author_itest", "id")
    assert {"1", "Ada — 1"} in options
    assert {"2", "Grace — 2"} in options
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
