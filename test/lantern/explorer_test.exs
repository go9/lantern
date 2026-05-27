defmodule Lantern.ExplorerTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

  @moduletag :integration

  @table "lantern_explorer_itest"

  setup_all do
    with_conn(fn conn ->
      Postgrex.query!(conn, "DROP TABLE IF EXISTS #{@table}", [])
      Postgrex.query!(conn, "CREATE TABLE #{@table} (id serial PRIMARY KEY, name text)", [])
      Postgrex.query!(conn, "INSERT INTO #{@table} (name) VALUES ('Ada'), ('Grace')", [])
    end)

    on_exit(fn ->
      with_conn(fn conn -> Postgrex.query!(conn, "DROP TABLE IF EXISTS #{@table}", []) end)
    end)

    :ok
  end

  test "lists tables and auto-selects the first one for a valid source" do
    html = render_component(Lantern.Explorer, id: "lantern", source: Lantern.TestDB.url())

    assert html =~ "lt-table-item"
    assert html =~ ~s(phx-value-table=)
    # A table is auto-selected, so the grid (not the empty state) renders.
    assert html =~ "lt-grid"
    refute html =~ "Select a table to browse"
  end

  test "surfaces a connection error for a bad source" do
    html =
      render_component(Lantern.Explorer,
        id: "lantern",
        source: "postgres://nobody:nobody@127.0.0.1:1/none"
      )

    assert html =~ "lt-error" or html =~ "Could not connect"
  end

  defp with_conn(fun) do
    {:ok, source} = Lantern.Source.from(Lantern.TestDB.url())
    {:ok, conn} = Postgrex.start_link(Lantern.Source.to_postgrex_opts(source))

    try do
      fun.(conn)
    after
      GenServer.stop(conn)
    end
  end
end
