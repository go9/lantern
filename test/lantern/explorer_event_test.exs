defmodule Lantern.ExplorerEventTest do
  @moduledoc """
  Event-handler tests for `Lantern.Explorer`.

  Exercises `update/2` and `handle_event/3` directly on a constructed socket —
  the codepath `render_component/2` can't reach, and the one the `col_meta`
  crash bug previously slipped through.
  """
  use ExUnit.Case, async: false

  alias Lantern.Explorer
  alias Phoenix.LiveView.Socket

  @moduletag :integration

  @table "lantern_event_itest"

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

  setup do
    {:ok, socket} =
      Explorer.update(
        %{source: Lantern.TestDB.url(), id: "lt"},
        empty_socket()
      )

    # Switch to the fixture table so the assigns we care about are populated.
    {:noreply, socket} = Explorer.handle_event("select_table", %{"table" => @table}, socket)

    {:ok, socket: socket}
  end

  test "col_meta is available in socket assigns after load_schema", %{socket: socket} do
    assert is_map(socket.assigns.col_meta)
    assert Map.has_key?(socket.assigns.col_meta, "id")
    assert Map.has_key?(socket.assigns.col_meta, "name")
  end

  test "save_row reads col_meta without crashing and closes cleanly on no-op",
       %{socket: socket} do
    {:noreply, socket} = Explorer.handle_event("edit_row", %{"index" => "0"}, socket)
    assert socket.assigns.editing == 0

    # Submit unchanged values — the diff is empty so save should close the
    # form quietly without calling the DB.
    {:noreply, socket} =
      Explorer.handle_event(
        "save_row",
        %{"_index" => "0", "name" => current_name(socket, 0)},
        socket
      )

    assert socket.assigns.editing == nil
    refute socket.assigns.error
  end

  test "save_row actually updates a changed field", %{socket: socket} do
    {:noreply, socket} = Explorer.handle_event("edit_row", %{"index" => "0"}, socket)

    {:noreply, socket} =
      Explorer.handle_event(
        "save_row",
        %{"_index" => "0", "name" => "Augusta"},
        socket
      )

    refute socket.assigns.error
    assert socket.assigns.editing == nil
    assert "Augusta" in flat_values(socket.assigns.rows)
  end

  test "delete_selected reads col_meta without crashing", %{socket: socket} do
    {:noreply, socket} = Explorer.handle_event("toggle_row", %{"index" => "0"}, socket)
    {:noreply, socket} = Explorer.handle_event("delete_selected", %{}, socket)

    refute socket.assigns.error
    assert socket.assigns.count == 1
  end

  test "a table with no primary key is insert-only: add rows works, even though edit/delete can't",
       %{socket: socket} do
    no_pk = "lantern_nopk_itest"

    with_conn(fn conn ->
      Postgrex.query!(conn, "DROP TABLE IF EXISTS #{no_pk}", [])
      Postgrex.query!(conn, "CREATE TABLE #{no_pk} (a text, b integer)", [])
    end)

    on_exit(fn ->
      with_conn(fn conn -> Postgrex.query!(conn, "DROP TABLE IF EXISTS #{no_pk}", []) end)
    end)

    {:noreply, socket} = Explorer.handle_event("select_table", %{"table" => no_pk}, socket)

    # No primary key (so render gates edit/delete off) but the table is loaded
    # with columns — `render/1` derives `insertable` from exactly these, so the
    # "New row" affordance stays on.
    assert socket.assigns.primary_keys == []
    assert socket.assigns.result_columns != []

    {:noreply, socket} = Explorer.handle_event("new_row", %{}, socket)
    assert socket.assigns.inserting

    {:noreply, socket} =
      Explorer.handle_event("save_insert", %{"a" => "hello", "b" => "7"}, socket)

    refute socket.assigns.error
    refute socket.assigns.inserting
    assert socket.assigns.count == 1
    assert "hello" in flat_values(socket.assigns.rows)
  end

  defp current_name(socket, row_index) do
    cols = socket.assigns.result_columns
    name_idx = Enum.find_index(cols, &(&1 == "name"))
    socket.assigns.rows |> Enum.at(row_index) |> Enum.at(name_idx)
  end

  defp flat_values(rows), do: rows |> Enum.flat_map(& &1)

  defp empty_socket do
    %Socket{
      assigns: %{__changed__: %{}, flash: %{}},
      endpoint: Lantern.TestEndpoint
    }
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
