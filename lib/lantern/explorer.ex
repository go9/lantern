defmodule Lantern.Explorer do
  @moduledoc """
  An embeddable Postgres table browser & editor `LiveComponent`.

  Drop it into any LiveView and hand it a connection source — Lantern manages
  the rest (table picker, grid, filtering, sorting, pagination, inline editing,
  row insertion, and bulk delete).

      <.live_component
        module={Lantern.Explorer}
        id="lantern"
        source={"postgres://user:pass@host:5432/db"}
      />

  `:source` is anything `Lantern.Source.from/1` accepts. The component
  owns all of its state and runs each query synchronously over a short-lived
  connection, so the host LiveView has nothing to supervise.

  ## Options

  Pass these attributes when mounting:

    * `:source` — required. See `Lantern.Source`.
    * `:title` — heading text. Default `"Data"`.
    * `:class` — extra class/classes for the root `.lantern` element.
    * `:theme` — `:system`/`"system"` (default), `:light`/`"light"`, or
      `:dark`/`"dark"`; rendered as `data-theme` for CSS targeting.
    * `:style` — inline root style, useful for setting `--lt-*` CSS variables.
    * `:allow_raw_filter` — when `true`, exposes a raw SQL filter input that
      is appended after `WHERE`. Default `false`. **Enable only for trusted
      operators**: a user-supplied fragment can execute arbitrary SQL (data-
      modifying CTEs, sub-selects, etc.) under the connection role's
      privileges. Lantern explicitly never sees the filter as
      parameterizable input — it's a literal SQL fragment.
    * `:allow_sql_workspace` — when `true`, exposes a SQL workspace. Default `false`.
    * `:sql_mode` — `:trusted` (default when SQL workspace is enabled) or `:read_only`.
    * `:read_only` — when `true`, the explorer is browse-only: inline editing,
      row insertion, bulk delete, and all DDL are hidden in the UI and refused
      server-side, and the SQL workspace accepts `SELECT`/`EXPLAIN` only.
      Default `false`. Useful for public or untrusted-viewer deployments.

  ## Styling

  Dependency-free: a plain `Phoenix.LiveComponent` with inlined Heroicons (MIT)
  and semantic `lt-*` class names — no Fluxon or icon library required. All
  markup lives under a `.lantern` root and every class is a single-class
  selector, so integrators override freely.

  Import the bundled `lantern.css` for good-looking defaults out of the box; it
  is driven entirely by `--lt-*` CSS variables, so re-theming means overriding a
  handful of variables (no Tailwind needed). Column resizing, the "set NULL"
  button, and live JSON validation need the `LanternGrid` JS hook registered in
  your LiveSocket — see the README for setup.

  Editing notes: rows are edited/deleted by primary key, so a table without one
  is insert-only — you can still add rows, but existing rows can't be edited or
  deleted. An empty input is written as SQL `NULL`.
  """
  use Phoenix.LiveComponent

  alias Lantern.Coercion
  alias LanternUI.Components.DatePicker
  import LiveCode.Editor, only: [editor: 1]

  @page_size 50

  # Every event that stages or commits a change. When `:read_only` is set these
  # are refused server-side, so hiding the buttons isn't the only safeguard.
  @write_events ~w(
    save_row save_insert delete_selected apply_pending discard_pending remove_pending
    new_row edit_row
    open_create_table create_table sync_new_table add_column_row remove_column_row
    open_columns add_column alter_column rename_column drop_column drop_constraint
    create_index drop_index open_rename_table rename_table drop_table
  )

  @impl true
  def update(assigns, socket) do
    source_changed? =
      socket.assigns[:loaded] == true and socket.assigns[:source] != assigns.source

    socket =
      socket
      |> assign(:source, assigns.source)
      |> assign(:allow_raw_filter, Map.get(assigns, :allow_raw_filter, false))
      |> assign(:allow_sql_workspace, Map.get(assigns, :allow_sql_workspace, false))
      |> assign(:read_only, Map.get(assigns, :read_only, false) == true)
      |> assign(:sql_mode, normalize_sql_mode(Map.get(assigns, :sql_mode, :trusted)))
      |> assign(:title, Map.get(assigns, :title, "Data"))
      |> assign(:dom_id, Map.get(assigns, :id, "lantern"))
      |> assign(:class, Map.get(assigns, :class, nil))
      |> assign(:theme, normalize_theme(Map.get(assigns, :theme, :system)))
      |> assign(:style, Map.get(assigns, :style, nil))

    cond do
      # First mount, or `:source` swapped to a different database — load (or
      # reload) tables and clear stale state so we don't leak rows across DBs.
      source_changed? or socket.assigns[:loaded] != true ->
        {:ok, init_state(socket)}

      true ->
        {:ok, socket}
    end
  end

  defp init_state(socket) do
    {schemas, schema_error} =
      case Lantern.list_schemas(socket.assigns.source) do
        {:ok, []} -> {["public"], nil}
        {:ok, schemas} -> {schemas, nil}
        {:error, reason} -> {[], reason}
      end

    selected_schema = if "public" in schemas, do: "public", else: List.first(schemas)

    {tables, table_stats, views, enums, table_error} =
      if selected_schema do
        case load_table_list(socket.assigns.source, selected_schema) do
          {:ok, tables, table_stats, views, enums} -> {tables, table_stats, views, enums, nil}
          {:error, reason} -> {[], %{}, [], [], reason}
        end
      else
        {[], %{}, [], [], nil}
      end

    error = schema_error || table_error

    # Default to the first table so the grid is populated on load.
    selected = List.first(tables)

    socket =
      socket
      |> assign(:loaded, true)
      |> assign(:schemas, schemas)
      |> assign(:selected_schema, selected_schema)
      |> assign(:tables, tables)
      |> assign(:table_stats, table_stats)
      |> assign(:views, views)
      |> assign(:enums, enums)
      |> assign(:selected_table, selected)
      |> assign(:columns, [])
      |> assign(:primary_keys, [])
      |> assign(:fk_options, %{})
      |> assign(:col_meta, %{})
      |> assign(:sort_by, nil)
      |> assign(:sort_dir, :asc)
      |> assign(:where_clause, "")
      |> assign(:page, 0)
      |> assign(:rows, [])
      |> assign(:count, 0)
      |> assign(:result_columns, [])
      |> assign(:selected, MapSet.new())
      |> assign(:editing, nil)
      |> assign(:inserting, false)
      |> assign(:open_row, nil)
      |> assign(:sidebar_open, true)
      |> assign(:fullscreen, false)
      |> assign(:dialog, nil)
      |> assign(:table_info, nil)
      |> assign(:active_view, :data)
      |> assign(:table_search, "")
      |> assign(:safe_filters, [empty_filter()])
      |> assign(:show_row_count, true)
      |> assign(:bytea_display, :hex)
      |> assign(:editor_font_size, "14px")
      |> assign(:hidden_columns, MapSet.new())
      |> assign(:count_kind, :exact)
      |> assign(:sql_text, default_sql(selected_schema, selected))
      |> assign(:sql_columns, [])
      |> assign(:sql_rows, [])
      |> assign(:sql_error, nil)
      |> assign(:sql_history, [])
      |> assign(:saved_queries, [])
      |> assign(:sql_query_name, "")
      |> assign(:sql_pending, nil)
      |> assign(:chart_kind, :bar)
      |> assign(:chart_column, nil)
      |> assign(:chart_label_column, nil)
      |> assign(:pending_changes, [])
      |> assign(:new_table_name, "")
      |> assign(:new_columns, [])
      |> assign(:error, error)

    if selected, do: socket |> load_schema() |> load_rows(), else: socket
  end

  # ---------------------------------------------------------------------------
  # Events — navigation
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event(event, _params, %{assigns: %{read_only: true}} = socket)
      when event in @write_events do
    {:noreply, socket}
  end

  def handle_event("select_schema", %{"schema" => schema}, socket) do
    schema = if schema in socket.assigns.schemas, do: schema, else: socket.assigns.selected_schema

    socket =
      socket
      |> assign(:selected_schema, schema)
      |> assign(:sort_by, nil)
      |> assign(:sort_dir, :asc)
      |> assign(:where_clause, "")
      |> assign(:safe_filters, [empty_filter()])
      |> assign(:page, 0)
      |> assign(:selected, MapSet.new())
      |> assign(:editing, nil)
      |> assign(:inserting, false)
      |> assign(:dialog, nil)
      |> reload_tables(nil)

    {:noreply, socket}
  end

  def handle_event("search_tables", %{"q" => query}, socket) do
    {:noreply, assign(socket, :table_search, query)}
  end

  def handle_event("set_view", %{"view" => "structure"}, socket) do
    {:noreply, socket |> assign(:active_view, :structure) |> load_table_info()}
  end

  def handle_event("set_view", %{"view" => "data"}, socket) do
    {:noreply, assign(socket, :active_view, :data)}
  end

  def handle_event("set_view", %{"view" => "sql"}, socket) do
    if sql_workspace_enabled?(socket) do
      {:noreply, assign(socket, :active_view, :sql)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("sql_change", %{"sql" => sql}, socket) do
    {:noreply, assign(socket, :sql_text, sql)}
  end

  def handle_event(
        "restore_sql_state",
        %{"saved_queries" => saved, "sql_history" => history},
        socket
      )
      when is_list(saved) and is_list(history) do
    saved =
      saved
      |> Enum.flat_map(fn
        %{"name" => name, "sql" => sql} when is_binary(name) and is_binary(sql) ->
          [%{name: name, sql: sql}]

        %{} = item ->
          name = Map.get(item, :name)
          sql = Map.get(item, :sql)
          if is_binary(name) and is_binary(sql), do: [%{name: name, sql: sql}], else: []

        _ ->
          []
      end)
      |> Enum.take(20)

    history = history |> Enum.filter(&is_binary/1) |> Enum.take(25)
    {:noreply, assign(socket, saved_queries: saved, sql_history: history)}
  end

  def handle_event("restore_sql_state", _params, socket), do: {:noreply, socket}

  def handle_event("run_sql", %{"sql" => sql, "action" => "explain"}, socket) do
    run_workspace_sql(socket, "EXPLAIN #{String.trim_trailing(sql, ";")}")
  end

  def handle_event("run_sql", %{"sql" => sql, "action" => "analyze"}, socket) do
    run_workspace_sql(socket, "EXPLAIN ANALYZE #{String.trim_trailing(sql, ";")}")
  end

  def handle_event("run_sql", %{"sql" => sql}, socket) do
    run_workspace_sql(socket, sql)
  end

  def handle_event("save_sql_query", %{"sql" => sql, "name" => name}, socket) do
    name = String.trim(name)

    if sql_workspace_enabled?(socket) and name != "" and String.trim(sql) != "" do
      saved =
        socket.assigns.saved_queries
        |> Enum.reject(&(&1.name == name))
        |> then(&[%{name: name, sql: sql} | &1])
        |> Enum.take(20)

      {:noreply,
       socket |> assign(saved_queries: saved, sql_query_name: "") |> persist_sql_state()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("load_sql_query", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         query when not is_nil(query) <- Enum.at(socket.assigns.saved_queries, index) do
      {:noreply, assign(socket, sql_text: query.sql, sql_error: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("load_sql_history", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         sql when is_binary(sql) <- Enum.at(socket.assigns.sql_history, index) do
      {:noreply, assign(socket, sql_text: sql, sql_error: nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_sql_query", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         true <- index < length(socket.assigns.saved_queries) do
      {:noreply,
       socket
       |> assign(:saved_queries, List.delete_at(socket.assigns.saved_queries, index))
       |> persist_sql_state()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("export_sql", %{"format" => format}, socket) when format in ["json", "csv"] do
    content = export_sql_content(format, socket.assigns)
    ext = if format == "json", do: "json", else: "csv"
    mime = if format == "json", do: "application/json", else: "text/csv"

    {:noreply,
     push_event(socket, "lantern:download", %{
       filename: "query-results.#{ext}",
       mime: mime,
       content: content
     })}
  end

  def handle_event("copy_sql_json", _params, socket) do
    {:noreply,
     push_event(socket, "lantern:copy", %{content: export_sql_content("json", socket.assigns)})}
  end

  def handle_event("confirm_sql", _params, socket) do
    case socket.assigns.sql_pending do
      nil -> {:noreply, socket}
      sql -> run_confirmed_sql(assign(socket, sql_pending: nil), sql)
    end
  end

  def handle_event("cancel_sql", _params, socket) do
    {:noreply, assign(socket, sql_pending: nil)}
  end

  def handle_event("toggle_column", %{"column" => column}, socket) do
    hidden = socket.assigns.hidden_columns
    visible_count = length(visible_columns(socket.assigns.result_columns, hidden))

    hidden =
      cond do
        MapSet.member?(hidden, column) ->
          MapSet.delete(hidden, column)

        visible_count > 1 ->
          MapSet.put(hidden, column)

        true ->
          hidden
      end

    {:noreply, assign(socket, :hidden_columns, hidden)}
  end

  def handle_event("show_all_columns", _params, socket) do
    {:noreply, assign(socket, :hidden_columns, MapSet.new())}
  end

  def handle_event("settings", params, socket) do
    {:noreply,
     assign(socket,
       show_row_count: Map.get(params, "show_row_count") == "true",
       bytea_display: parse_bytea_display(Map.get(params, "bytea_display")),
       editor_font_size: parse_editor_font_size(Map.get(params, "editor_font_size"))
     )
     |> load_rows()}
  end

  def handle_event("select_table", %{"table" => ""}, socket) do
    {:noreply, assign(socket, selected_table: nil, rows: [], count: nil, result_columns: [])}
  end

  def handle_event("select_table", %{"table" => table}, socket) do
    socket =
      socket
      |> assign(:selected_table, table)
      |> assign(:sql_text, default_sql(socket.assigns.selected_schema, table))
      |> assign(:sql_columns, [])
      |> assign(:sql_rows, [])
      |> assign(:sql_error, nil)
      |> assign(:sort_by, nil)
      |> assign(:sort_dir, :asc)
      |> assign(:where_clause, "")
      |> assign(:safe_filters, [empty_filter()])
      |> assign(:page, 0)
      |> assign(:selected, MapSet.new())
      |> assign(:editing, nil)
      |> assign(:inserting, false)
      |> assign(:dialog, nil)
      |> load_schema()
      |> load_rows()

    {:noreply, socket}
  end

  def handle_event("sort_column", %{"column" => col}, socket) do
    {sort_by, sort_dir} =
      if socket.assigns.sort_by == col do
        {col, toggle(socket.assigns.sort_dir)}
      else
        {col, :asc}
      end

    socket =
      socket
      |> assign(sort_by: sort_by, sort_dir: sort_dir, page: 0)
      |> load_rows()

    {:noreply, socket}
  end

  def handle_event("safe_filters", params, socket) do
    filters = parse_filter_params(params)
    {:noreply, socket |> assign(safe_filters: filters, page: 0) |> load_rows()}
  end

  def handle_event("add_safe_filter", _params, socket) do
    {:noreply, assign(socket, :safe_filters, socket.assigns.safe_filters ++ [empty_filter()])}
  end

  def handle_event("remove_safe_filter", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         true <- index < length(socket.assigns.safe_filters) do
      filters = List.delete_at(socket.assigns.safe_filters, index)
      filters = if filters == [], do: [empty_filter()], else: filters
      {:noreply, socket |> assign(:safe_filters, filters) |> load_rows()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear_safe_filters", _params, socket) do
    {:noreply, socket |> assign(safe_filters: [empty_filter()], page: 0) |> load_rows()}
  end

  # Cell actions menu → "Filter by this value": replace the active filters with a
  # single safe `column = value` filter. A read operation, so it stays out of
  # @write_events and works under :read_only.
  def handle_event("filter_by_cell", %{"column" => column, "value" => value}, socket)
      when is_binary(column) and column != "" do
    filter = %{column: column, op: "eq", value: to_string(value)}
    {:noreply, socket |> assign(safe_filters: [filter], page: 0) |> load_rows()}
  end

  def handle_event("filter_by_cell", _params, socket), do: {:noreply, socket}

  def handle_event("filter", %{"where_clause" => clause}, socket) do
    if socket.assigns.allow_raw_filter do
      {:noreply, socket |> assign(where_clause: clause, page: 0) |> load_rows()}
    else
      {:noreply, assign(socket, where_clause: "")}
    end
  end

  def handle_event("apply_filter", %{"q" => clause}, socket) do
    if socket.assigns.allow_raw_filter do
      {:noreply, socket |> assign(where_clause: clause, page: 0) |> load_rows()}
    else
      {:noreply, assign(socket, where_clause: "")}
    end
  end

  def handle_event("page", %{"dir" => dir}, socket) do
    page =
      case dir do
        "next" -> socket.assigns.page + 1
        "prev" -> max(0, socket.assigns.page - 1)
        _ -> socket.assigns.page
      end

    {:noreply, socket |> assign(:page, page) |> load_rows()}
  end

  def handle_event("refresh", _params, socket) do
    {:noreply, load_rows(socket)}
  end

  def handle_event("export", %{"format" => format}, socket) when format in ["json", "csv"] do
    content = export_content(format, socket.assigns)
    ext = if format == "json", do: "json", else: "csv"
    mime = if format == "json", do: "application/json", else: "text/csv"
    filename = "#{socket.assigns.selected_schema}-#{socket.assigns.selected_table}.#{ext}"

    {:noreply,
     push_event(socket, "lantern:download", %{filename: filename, mime: mime, content: content})}
  end

  def handle_event("export_selected", %{"format" => format}, socket)
      when format in ["json", "csv"] do
    content = export_selected_content(format, socket.assigns)
    ext = if format == "json", do: "json", else: "csv"
    mime = if format == "json", do: "application/json", else: "text/csv"

    filename =
      "#{socket.assigns.selected_schema}-#{socket.assigns.selected_table}-selected.#{ext}"

    {:noreply,
     push_event(socket, "lantern:download", %{filename: filename, mime: mime, content: content})}
  end

  def handle_event("copy_selected_json", _params, socket) do
    {:noreply,
     push_event(socket, "lantern:copy", %{
       content: export_selected_content("json", socket.assigns)
     })}
  end

  def handle_event("copy_context", _params, socket) do
    socket = load_table_info(socket)
    content = table_context(socket.assigns.table_info || %{})
    {:noreply, push_event(socket, "lantern:copy", %{content: content})}
  end

  def handle_event("open_fk", %{"column" => column, "value" => value}, socket) do
    with %{fk: %{schema: schema, table: table, column: fk_column}} <-
           socket.assigns.col_meta[column],
         {:ok, tables, table_stats, views, enums} <-
           load_table_list(socket.assigns.source, schema),
         true <- table in tables do
      socket =
        socket
        |> assign(:selected_schema, schema)
        |> assign(:tables, tables)
        |> assign(:table_stats, table_stats)
        |> assign(:views, views)
        |> assign(:enums, enums)
        |> assign(:selected_table, table)
        |> assign(:sql_text, default_sql(schema, table))
        |> assign(:sql_columns, [])
        |> assign(:sql_rows, [])
        |> assign(:sql_error, nil)
        |> assign(:safe_filters, [%{column: fk_column, op: "eq", value: value}])
        |> assign(:where_clause, "")
        |> assign(:sort_by, nil)
        |> assign(:sort_dir, :asc)
        |> assign(:page, 0)
        |> assign(:selected, MapSet.new())
        |> assign(:dialog, nil)
        |> load_schema()
        |> load_rows()

      {:noreply, socket}
    else
      _ -> {:noreply, assign(socket, :error, "Could not open referenced row")}
    end
  end

  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, not socket.assigns.sidebar_open)}
  end

  def handle_event("toggle_fullscreen", _params, socket) do
    {:noreply, assign(socket, :fullscreen, not socket.assigns.fullscreen)}
  end

  def handle_event("exit_fullscreen", _params, socket) do
    {:noreply, assign(socket, :fullscreen, false)}
  end

  # ---------------------------------------------------------------------------
  # Events — selection
  # ---------------------------------------------------------------------------

  def handle_event("toggle_row", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         true <- index < length(socket.assigns.rows) do
      selected =
        if MapSet.member?(socket.assigns.selected, index) do
          MapSet.delete(socket.assigns.selected, index)
        else
          MapSet.put(socket.assigns.selected, index)
        end

      {:noreply, assign(socket, :selected, selected)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("toggle_all", _params, socket) do
    all = 0..(length(socket.assigns.rows) - 1)//1 |> MapSet.new()

    selected =
      if MapSet.size(socket.assigns.selected) == length(socket.assigns.rows),
        do: MapSet.new(),
        else: all

    {:noreply, assign(socket, :selected, selected)}
  end

  # Row detail drawer: open/close are pure reads (just view state pointing at a
  # row index), so they stay out of @write_events and work under :read_only. The
  # index is validated against the current rows; it's reset to nil whenever rows
  # reload (sort/page/refresh) in load_rows/1, since indexes go stale.
  def handle_event("open_row", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         true <- index < length(socket.assigns.rows) do
      {:noreply, assign(socket, :open_row, index)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("close_row", _params, socket) do
    {:noreply, assign(socket, :open_row, nil)}
  end

  # Chart controls are pure reads (view state over already-loaded rows / SQL
  # results), so they stay out of @write_events and work under :read_only.
  def handle_event("set_chart_kind", %{"kind" => kind}, socket)
      when kind in ~w(bar line pie) do
    {:noreply, assign(socket, :chart_kind, String.to_existing_atom(kind))}
  end

  def handle_event("set_chart_kind", _params, socket), do: {:noreply, socket}

  # Toggle a numeric data-grid column on/off as the charted column for the
  # currently loaded @rows. Clicking the active column again clears it.
  def handle_event("chart_column", %{"column" => column}, socket)
      when is_binary(column) and column != "" do
    next = if socket.assigns.chart_column == column, do: nil, else: column
    {:noreply, assign(socket, :chart_column, next)}
  end

  def handle_event("chart_column", _params, socket), do: {:noreply, socket}

  # Pick the X (label) column for the data-grid chart. Empty value falls back to
  # the automatic pick. A read, so it stays out of @write_events.
  def handle_event("set_chart_label", %{"column" => column}, socket) do
    next = if column in socket.assigns.result_columns, do: column, else: nil
    {:noreply, assign(socket, :chart_label_column, next)}
  end

  def handle_event("set_chart_label", _params, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Events — editing
  # ---------------------------------------------------------------------------

  def handle_event("edit_row", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         true <- index < length(socket.assigns.rows) do
      {:noreply, assign(socket, editing: index, inserting: false)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("save_row", params, socket) do
    with {:ok, index} <- parse_index(params["_index"]),
         row when not is_nil(row) <- Enum.at(socket.assigns.rows, index) do
      cols = socket.assigns.result_columns
      pks = socket.assigns.primary_keys
      col_meta = socket.assigns.col_meta

      stage_existing_row(socket, params, row, cols, pks, col_meta)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("apply_pending", _params, socket) do
    case Lantern.apply_changes(
           socket.assigns.source,
           socket.assigns.selected_table,
           socket.assigns.pending_changes,
           schema: socket.assigns.selected_schema
         ) do
      {:ok, _count} ->
        {:noreply,
         socket
         |> assign(pending_changes: [], editing: nil, selected: MapSet.new())
         |> load_rows()
         |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("discard_pending", _params, socket) do
    {:noreply, assign(socket, pending_changes: [], editing: nil)}
  end

  def handle_event("remove_pending", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         true <- index < length(socket.assigns.pending_changes) do
      {:noreply,
       assign(socket, :pending_changes, List.delete_at(socket.assigns.pending_changes, index))}
    else
      _ -> {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — insert
  # ---------------------------------------------------------------------------

  def handle_event("new_row", _params, socket) do
    {:noreply, assign(socket, inserting: true, editing: nil)}
  end

  def handle_event("cancel_insert", _params, socket) do
    {:noreply, assign(socket, :inserting, false)}
  end

  def handle_event("save_insert", params, socket) do
    # Omit blank fields entirely so Postgres applies column defaults (sequences,
    # `DEFAULT`, etc.) rather than receiving an explicit NULL it might reject.
    values =
      params
      |> Map.drop(["_target"])
      |> Enum.map(fn {col, val} -> {col, blank_to_nil(val)} end)
      |> Enum.reject(fn {_col, val} -> is_nil(val) end)
      |> Map.new()

    case Lantern.insert(socket.assigns.source, socket.assigns.selected_table, values,
           schema: socket.assigns.selected_schema
         ) do
      {:ok, _row} ->
        {:noreply, socket |> assign(:inserting, false) |> load_rows() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  # ---------------------------------------------------------------------------
  # Events — delete
  # ---------------------------------------------------------------------------

  def handle_event("delete_selected", _params, socket) do
    cols = socket.assigns.result_columns
    pks = socket.assigns.primary_keys
    col_meta = socket.assigns.col_meta

    keys =
      socket.assigns.selected
      |> Enum.map(&Enum.at(socket.assigns.rows, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&pk_key(&1, cols, pks, col_meta))

    change = %{action: :delete, keys: keys}

    {:noreply,
     socket
     |> assign(
       pending_changes: socket.assigns.pending_changes ++ [change],
       selected: MapSet.new()
     )
     |> clear_error()}
  end

  # ---------------------------------------------------------------------------
  # Events — schema changes (DDL)
  # ---------------------------------------------------------------------------

  def handle_event("open_create_table", _params, socket) do
    {:noreply,
     assign(socket,
       dialog: :create_table,
       new_table_name: "",
       new_columns: [empty_column(:first)],
       editing: nil,
       inserting: false
     )
     |> clear_error()}
  end

  # Keep the create-table draft in sync so adding/removing column rows preserves
  # already-typed values. Values are echoed back verbatim, so focused inputs
  # don't lose their caret.
  def handle_event("sync_new_table", params, socket) do
    {:noreply,
     assign(socket,
       new_table_name: Map.get(params, "table", socket.assigns.new_table_name),
       new_columns: parse_columns(params)
     )}
  end

  def handle_event("add_column_row", _params, socket) do
    {:noreply, assign(socket, :new_columns, socket.assigns.new_columns ++ [empty_column(:more)])}
  end

  def handle_event("remove_column_row", %{"index" => index}, socket) do
    with {:ok, index} <- parse_index(index),
         true <- index < length(socket.assigns.new_columns) do
      columns = List.delete_at(socket.assigns.new_columns, index)
      columns = if columns == [], do: [empty_column(:first)], else: columns
      {:noreply, assign(socket, :new_columns, columns)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("create_table", params, socket) do
    name = Map.get(params, "table", "")
    columns = parse_columns(params)

    case Lantern.create_table(socket.assigns.source, name, columns,
           schema: socket.assigns.selected_schema
         ) do
      :ok ->
        {:noreply, reload_tables(socket, name)}

      {:error, reason} ->
        {:noreply,
         assign(socket, new_table_name: name, new_columns: columns, error: humanize(reason))}
    end
  end

  def handle_event("open_table_info", _params, socket) do
    case Lantern.table_info(socket.assigns.source, socket.assigns.selected_table,
           schema: socket.assigns.selected_schema
         ) do
      {:ok, info} ->
        {:noreply,
         assign(socket, dialog: :table_info, table_info: info, editing: nil, inserting: false)
         |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("open_columns", _params, socket) do
    {:noreply, assign(socket, dialog: :columns, editing: nil, inserting: false) |> clear_error()}
  end

  def handle_event("add_column", params, socket) do
    column = %{
      name: Map.get(params, "name", ""),
      type: ddl_type(params),
      nullable: Map.get(params, "nullable", "true") == "true"
    }

    case Lantern.add_column(socket.assigns.source, socket.assigns.selected_table, column,
           schema: socket.assigns.selected_schema
         ) do
      :ok ->
        # Keep the dialog open so several columns can be managed in one sitting.
        {:noreply, socket |> load_schema() |> load_rows() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("alter_column", params, socket) do
    column = Map.get(params, "column", "")
    type = ddl_type(params)
    nullable = Map.get(params, "nullable", "false") == "true"

    result =
      with :ok <-
             Lantern.alter_column_type(
               socket.assigns.source,
               socket.assigns.selected_table,
               column,
               type,
               schema: socket.assigns.selected_schema
             ),
           :ok <-
             Lantern.set_column_nullable(
               socket.assigns.source,
               socket.assigns.selected_table,
               column,
               nullable,
               schema: socket.assigns.selected_schema
             ) do
        :ok
      end

    case result do
      :ok ->
        {:noreply, socket |> load_schema() |> load_rows() |> load_table_info() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("rename_column", %{"from" => from, "name" => to}, socket) do
    case Lantern.rename_column(socket.assigns.source, socket.assigns.selected_table, from, to,
           schema: socket.assigns.selected_schema
         ) do
      :ok ->
        {:noreply, socket |> load_schema() |> load_rows() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("drop_column", %{"column" => column}, socket) do
    case Lantern.drop_column(socket.assigns.source, socket.assigns.selected_table, column,
           schema: socket.assigns.selected_schema
         ) do
      :ok ->
        {:noreply, socket |> load_schema() |> load_rows() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("drop_constraint", %{"constraint" => constraint}, socket) do
    case Lantern.drop_constraint(socket.assigns.source, socket.assigns.selected_table, constraint,
           schema: socket.assigns.selected_schema
         ) do
      :ok ->
        {:noreply, socket |> load_schema() |> load_table_info() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("create_index", params, socket) do
    columns = params |> Map.get("columns", "") |> parse_column_list()

    case Lantern.create_index(
           socket.assigns.source,
           socket.assigns.selected_table,
           Map.get(params, "name", ""),
           columns,
           schema: socket.assigns.selected_schema
         ) do
      :ok ->
        {:noreply, socket |> load_table_info() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("drop_index", %{"index" => index}, socket) do
    case Lantern.drop_index(socket.assigns.source, index, schema: socket.assigns.selected_schema) do
      :ok ->
        {:noreply, socket |> load_table_info() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("open_rename_table", _params, socket) do
    {:noreply,
     assign(socket, dialog: :rename_table, editing: nil, inserting: false) |> clear_error()}
  end

  def handle_event("rename_table", %{"name" => new_name}, socket) do
    case Lantern.rename_table(socket.assigns.source, socket.assigns.selected_table, new_name,
           schema: socket.assigns.selected_schema
         ) do
      :ok ->
        {:noreply, reload_tables(socket, new_name)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("drop_table", _params, socket) do
    case Lantern.drop_table(socket.assigns.source, socket.assigns.selected_table,
           schema: socket.assigns.selected_schema
         ) do
      :ok ->
        {:noreply, reload_tables(socket, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("close_dialog", _params, socket) do
    {:noreply, assign(socket, :dialog, nil)}
  end

  # ---------------------------------------------------------------------------
  # Data loading
  # ---------------------------------------------------------------------------

  defp load_table_list(source, schema) do
    with {:ok, tables} <- Lantern.list_tables(source, schema: schema) do
      stats =
        case Lantern.table_stats(source, schema: schema) do
          {:ok, stats} -> Map.new(stats, &{&1.name, &1})
          {:error, _reason} -> %{}
        end

      views =
        case Lantern.list_views(source, schema: schema) do
          {:ok, views} -> views
          {:error, _reason} -> []
        end

      enums =
        case Lantern.list_enums(source, schema: schema) do
          {:ok, enums} -> enums
          {:error, _reason} -> []
        end

      {:ok, tables, stats, views, enums}
    end
  end

  defp load_table_info(socket) do
    case Lantern.table_info(socket.assigns.source, socket.assigns.selected_table,
           schema: socket.assigns.selected_schema
         ) do
      {:ok, info} -> assign(socket, :table_info, info)
      {:error, _reason} -> socket
    end
  end

  defp load_schema(socket) do
    table = socket.assigns.selected_table
    source = socket.assigns.source
    schema = socket.assigns.selected_schema

    case Lantern.schema(source, table, schema: schema) do
      {:ok, %{columns: cols, primary_keys: pks, fk_options: fks}} ->
        assign(socket,
          columns: cols,
          primary_keys: pks,
          fk_options: fks,
          # Used in event handlers, so it must live in socket.assigns — not just
          # in render/1's local view.
          col_meta: Map.new(cols, &{&1.name, &1}),
          error: nil
        )

      {:error, reason} ->
        assign(socket,
          error: humanize(reason),
          columns: [],
          primary_keys: [],
          fk_options: %{},
          col_meta: %{}
        )
    end
  end

  defp run_workspace_sql(socket, sql) do
    cond do
      not sql_workspace_enabled?(socket) ->
        {:noreply, socket}

      (socket.assigns.read_only or socket.assigns.sql_mode == :read_only) and
          not read_only_sql?(sql) ->
        {:noreply, assign(socket, sql_text: sql, sql_error: "SQL workspace is in read-only mode")}

      socket.assigns.sql_mode == :guarded and destructive_sql?(sql) ->
        {:noreply, assign(socket, sql_text: sql, sql_pending: sql)}

      true ->
        case Lantern.run_query(socket.assigns.source, sql) do
          {:ok, %{columns: columns, rows: rows}} ->
            history =
              [sql | socket.assigns.sql_history]
              |> Enum.uniq()
              |> Enum.take(25)

            {:noreply,
             socket
             |> assign(
               sql_text: sql,
               sql_columns: columns,
               sql_rows: rows,
               sql_error: nil,
               sql_history: history
             )
             |> persist_sql_state()}

          {:error, reason} ->
            {:noreply, assign(socket, sql_text: sql, sql_error: humanize(reason))}
        end
    end
  end

  defp run_confirmed_sql(socket, sql) do
    case Lantern.run_query(socket.assigns.source, sql) do
      {:ok, %{columns: columns, rows: rows}} ->
        history =
          [sql | socket.assigns.sql_history]
          |> Enum.uniq()
          |> Enum.take(25)

        {:noreply,
         socket
         |> assign(
           sql_text: sql,
           sql_columns: columns,
           sql_rows: rows,
           sql_error: nil,
           sql_history: history
         )
         |> persist_sql_state()}

      {:error, reason} ->
        {:noreply, assign(socket, sql_text: sql, sql_error: humanize(reason))}
    end
  end

  defp load_rows(%{assigns: %{selected_table: nil}} = socket), do: socket

  defp load_rows(socket) do
    a = socket.assigns

    opts = [
      schema: a.selected_schema,
      where_clause: if(a.allow_raw_filter, do: a.where_clause, else: nil),
      filters: safe_filters(a.safe_filters),
      sort_by: a.sort_by,
      sort_dir: a.sort_dir,
      count: if(a.show_row_count, do: :exact, else: false),
      limit: @page_size,
      offset: a.page * @page_size
    ]

    case Lantern.query(a.source, a.selected_table, opts) do
      {:ok, %{columns: cols, rows: rows, count: count, count_kind: count_kind}} ->
        # Drop any in-flight edit/insert and selection: row indexes don't
        # survive a sort, page change, or refresh, so reusing them would
        # silently apply edits to the wrong row.
        socket
        |> assign(result_columns: cols, rows: rows, count: count, count_kind: count_kind)
        |> assign(:selected, MapSet.new())
        |> assign(:editing, nil)
        |> assign(:inserting, false)
        |> assign(:open_row, nil)
        |> assign(:chart_column, reset_chart_column(a.chart_column, cols))
        |> assign(:chart_label_column, reset_chart_column(a.chart_label_column, cols))
        |> clear_error()

      {:error, reason} ->
        assign(socket, error: humanize(reason), rows: [], count: nil, count_kind: :none)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp sql_workspace_enabled?(socket),
    do: socket.assigns.allow_sql_workspace and socket.assigns.sql_mode != :off

  defp normalize_sql_mode(mode) when mode in [:trusted, "trusted"], do: :trusted

  defp normalize_sql_mode(mode) when mode in [:read_only, "read_only", "read-only"],
    do: :read_only

  defp normalize_sql_mode(mode) when mode in [:guarded, "guarded"], do: :guarded

  defp normalize_sql_mode(_mode), do: :trusted

  defp dangerous_sql?(sql) do
    sql
    |> String.trim_leading()
    |> String.downcase()
    |> then(&(not String.starts_with?(&1, "select") and not String.starts_with?(&1, "explain")))
  end

  defp read_only_sql?(sql) do
    sql
    |> String.trim_leading()
    |> String.downcase()
    |> then(&(String.starts_with?(&1, "select") or String.starts_with?(&1, "explain")))
  end

  # Best-effort detector for statements the `:guarded` SQL mode holds for an
  # explicit confirm: DROP, TRUNCATE, and DELETE/UPDATE with no WHERE clause (a
  # full-table wipe/rewrite). Public + `@doc false` only so the detector — the
  # safety boundary — is unit-testable without a database. Heuristic, not a
  # parser: it errs toward prompting, and the WHERE check uses a word boundary so
  # a table literally named `wherehouse` can't slip a DELETE through unconfirmed.
  @doc false
  def destructive_sql?(sql) when is_binary(sql) do
    normalized = sql |> String.trim_leading() |> String.downcase()

    cond do
      String.starts_with?(normalized, "drop") -> true
      String.starts_with?(normalized, "truncate") -> true
      String.starts_with?(normalized, "delete") and not has_where_clause?(normalized) -> true
      String.starts_with?(normalized, "update") and not has_where_clause?(normalized) -> true
      true -> false
    end
  end

  def destructive_sql?(_), do: false

  defp has_where_clause?(normalized), do: normalized =~ ~r/\bwhere\b/

  defp persist_sql_state(socket) do
    push_event(socket, "lantern:persist-sql-state", %{
      saved_queries: socket.assigns.saved_queries,
      sql_history: socket.assigns.sql_history
    })
  end

  defp sql_editor_context(assigns) do
    columns = Enum.map(assigns.columns, &%{table: assigns.selected_table, name: &1.name})
    tables = Enum.map(assigns.tables, &%{schema: assigns.selected_schema, name: &1})

    %{
      schemas: assigns.schemas,
      tables: tables,
      columns: columns
    }
  end

  defp default_sql(nil, _table), do: ""
  defp default_sql(_schema, nil), do: ""

  defp default_sql(schema, table) do
    ~s(SELECT * FROM #{Lantern.SQL.quote_table(schema, table)} LIMIT 100;)
  end

  defp toggle(:asc), do: :desc
  defp toggle(:desc), do: :asc

  defp normalize_theme(theme) when theme in [:light, "light"], do: "light"
  defp normalize_theme(theme) when theme in [:dark, "dark"], do: "dark"
  defp normalize_theme(_theme), do: nil

  defp parse_index(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} when index >= 0 -> {:ok, index}
      _ -> :error
    end
  end

  defp parse_index(value) when is_integer(value) and value >= 0, do: {:ok, value}
  defp parse_index(_), do: :error

  defp root_style(editor_font_size, nil), do: "--lt-editor-font-size: #{editor_font_size};"

  defp root_style(editor_font_size, style),
    do: "--lt-editor-font-size: #{editor_font_size}; #{style}"

  defp parse_bytea_display("utf8"), do: :utf8
  defp parse_bytea_display(_), do: :hex

  defp parse_editor_font_size(size) when size in ["12px", "14px", "16px"], do: size
  defp parse_editor_font_size(_), do: "14px"

  defp visible_columns(columns, hidden), do: Enum.reject(columns, &MapSet.member?(hidden, &1))

  defp export_content("json", assigns) do
    cols = visible_columns(assigns.result_columns, assigns.hidden_columns)

    assigns.rows
    |> Enum.map(&row_to_map(&1, assigns.result_columns, cols, assigns.col_meta))
    |> Jason.encode!(pretty: true)
  end

  defp export_content("csv", assigns) do
    cols = visible_columns(assigns.result_columns, assigns.hidden_columns)
    rows = Enum.map(assigns.rows, &row_to_map(&1, assigns.result_columns, cols, assigns.col_meta))

    csv_rows(cols, rows)
  end

  defp export_selected_content("json", assigns) do
    cols = visible_columns(assigns.result_columns, assigns.hidden_columns)

    assigns.rows
    |> selected_rows(assigns.selected)
    |> Enum.map(&row_to_map(&1, assigns.result_columns, cols, assigns.col_meta))
    |> Jason.encode!(pretty: true)
  end

  defp export_selected_content("csv", assigns) do
    cols = visible_columns(assigns.result_columns, assigns.hidden_columns)

    rows =
      assigns.rows
      |> selected_rows(assigns.selected)
      |> Enum.map(&row_to_map(&1, assigns.result_columns, cols, assigns.col_meta))

    csv_rows(cols, rows)
  end

  defp selected_rows(rows, selected) do
    selected
    |> Enum.sort()
    |> Enum.map(&Enum.at(rows, &1))
    |> Enum.reject(&is_nil/1)
  end

  defp chart_points(columns, rows) when length(columns) >= 2 and rows != [] do
    numeric_index = Enum.find_index(List.first(rows), &number_like?/1)

    if numeric_index && numeric_index > 0 do
      label_index = 0
      max = rows |> Enum.map(&to_float(Enum.at(&1, numeric_index))) |> Enum.max(fn -> 0 end)

      if max > 0 do
        rows
        |> Enum.take(12)
        |> Enum.map(fn row ->
          value = to_float(Enum.at(row, numeric_index))

          %{
            label:
              row
              |> Enum.at(label_index)
              |> Coercion.display()
              |> to_string()
              |> String.slice(0, 28),
            value: value,
            width: max(4, value / max * 100)
          }
        end)
      else
        []
      end
    else
      []
    end
  end

  defp chart_points(_columns, _rows), do: []

  defp number_like?(value), do: is_integer(value) or is_float(value) or match?(%Decimal{}, value)
  defp to_float(%Decimal{} = value), do: Decimal.to_float(value)
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(value) when is_float(value), do: value

  # Build chart points for one chosen numeric column over the currently loaded
  # data-grid rows. Used by the "chart this column" affordance on numeric
  # headers. Labels come from the table's primary-key column(s) when available,
  # otherwise the 1-based row position. Non-numeric cells are skipped.
  defp chart_points_from_column(column, label_column, columns, rows, primary_keys) do
    case Enum.find_index(columns, &(&1 == column)) do
      nil ->
        []

      value_index ->
        label_indexes =
          case chart_label_index(label_column, columns, rows, primary_keys, value_index) do
            nil -> []
            idx -> [idx]
          end

        numeric_rows =
          rows
          |> Enum.with_index()
          |> Enum.filter(fn {row, _i} -> number_like?(Enum.at(row, value_index)) end)
          |> Enum.take(12)

        max =
          numeric_rows
          |> Enum.map(fn {row, _i} -> to_float(Enum.at(row, value_index)) end)
          |> Enum.max(fn -> 0 end)

        if numeric_rows == [] or max <= 0 do
          []
        else
          Enum.map(numeric_rows, fn {row, i} ->
            value = to_float(Enum.at(row, value_index))

            %{
              label: row_chart_label(row, label_indexes, i),
              value: value,
              width: max(4, value / max * 100)
            }
          end)
        end
    end
  end

  # Prefer primary-key column(s) for point labels; fall back to the first
  # non-value column; otherwise label by position (handled in row_chart_label/3).
  # Resolve the X (label) column for a single-column chart: the user's explicit
  # choice when valid, otherwise the first descriptive (non-numeric) column —
  # e.g. a name/sku — so bars/slices read meaningfully rather than by row id;
  # then a primary key, then any other column. Returns an index or nil ("#n").
  defp chart_label_index(label_column, columns, rows, primary_keys, value_index) do
    chosen = label_column && Enum.find_index(columns, &(&1 == label_column))

    if is_integer(chosen) and chosen != value_index do
      chosen
    else
      descriptive_label_index(columns, rows, value_index) ||
        pk_label_index(columns, primary_keys, value_index) ||
        first_other_index(columns, value_index)
    end
  end

  defp descriptive_label_index(columns, rows, value_index) do
    sample = List.first(rows) || []

    columns
    |> Enum.with_index()
    |> Enum.find_value(fn {_c, idx} ->
      value = Enum.at(sample, idx)
      if idx != value_index and not is_nil(value) and not number_like?(value), do: idx
    end)
  end

  defp pk_label_index(columns, primary_keys, value_index) do
    primary_keys
    |> Enum.map(&Enum.find_index(columns, fn c -> c == &1 end))
    |> Enum.find(&(is_integer(&1) and &1 != value_index))
  end

  defp first_other_index(columns, value_index) do
    columns
    |> Enum.with_index()
    |> Enum.find_value(fn {_c, idx} -> if idx != value_index, do: idx end)
  end

  defp row_chart_label(_row, [], i), do: "##{i + 1}"

  defp row_chart_label(row, indexes, _i) do
    indexes
    |> Enum.map(fn idx -> row |> Enum.at(idx) |> Coercion.display() |> to_string() end)
    |> Enum.join(" / ")
    |> String.slice(0, 28)
  end

  # Clear the charted column when it no longer exists in the freshly loaded
  # result columns (e.g. after a table change), since rows are positional.
  defp reset_chart_column(nil, _cols), do: nil
  defp reset_chart_column(column, cols), do: if(column in cols, do: column, else: nil)

  # ---- Inline SVG chart geometry (pure; keeps the HEEx declarative) ----------

  # Viewbox conventions shared by line/pie so the CSS/markup stays simple.
  @line_w 480
  @line_h 140
  @line_pad 8
  @pie_size 140

  # Line chart: evenly spaced points left-to-right, y scaled to [0, max].
  # Returns the polyline "points" string plus a list of %{x, y, label, value}
  # dots and the baseline y. Single point renders as one centered dot.
  defp line_geometry(points) do
    max = points |> Enum.map(& &1.value) |> Enum.max(fn -> 0 end)
    max = if max <= 0, do: 1.0, else: max
    n = length(points)

    inner_w = @line_w - 2 * @line_pad
    inner_h = @line_h - 2 * @line_pad
    baseline = @line_h - @line_pad

    dots =
      points
      |> Enum.with_index()
      |> Enum.map(fn {p, i} ->
        x =
          if n <= 1,
            do: @line_w / 2,
            else: @line_pad + inner_w * (i / (n - 1))

        y = baseline - inner_h * (p.value / max)
        %{x: Float.round(x, 2), y: Float.round(y, 2), label: p.label, value: p.value}
      end)

    polyline = dots |> Enum.map(fn d -> "#{d.x},#{d.y}" end) |> Enum.join(" ")

    %{width: @line_w, height: @line_h, baseline: baseline, polyline: polyline, dots: dots}
  end

  # Pie chart: one arc <path> per point, sized by value / sum. Colors cycle
  # through a small token-derived palette. Returns slices with the SVG path "d",
  # a color, the percentage, and the original label/value (for the legend).
  defp pie_geometry(points) do
    # A pie can only represent non-negative magnitudes; drop the rest so a stray
    # negative value can't produce a backwards arc.
    points = Enum.filter(points, &(&1.value > 0))
    total = points |> Enum.map(& &1.value) |> Enum.sum()

    if total <= 0 do
      %{size: @pie_size, slices: []}
    else
      r = @pie_size / 2 - 2
      cx = @pie_size / 2
      cy = @pie_size / 2

      {slices, _acc} =
        points
        |> Enum.with_index()
        |> Enum.map_reduce(0.0, fn {p, i}, start ->
          frac = p.value / total
          stop = start + frac

          slice = %{
            d: pie_slice_path(cx, cy, r, start, stop),
            color: chart_color(i),
            percent: Float.round(frac * 100, 1),
            label: p.label,
            value: p.value,
            full: frac >= 0.999
          }

          {slice, stop}
        end)

      %{size: @pie_size, slices: slices}
    end
  end

  # One pie wedge as a path: move to center, line to arc start, arc to arc end,
  # close. start/stop are fractions of the circle in [0, 1], clockwise from top.
  defp pie_slice_path(cx, cy, r, start, stop) do
    {sx, sy} = pie_point(cx, cy, r, start)
    {ex, ey} = pie_point(cx, cy, r, stop)
    large = if stop - start > 0.5, do: 1, else: 0

    "M #{f(cx)} #{f(cy)} L #{f(sx)} #{f(sy)} " <>
      "A #{f(r)} #{f(r)} 0 #{large} 1 #{f(ex)} #{f(ey)} Z"
  end

  defp pie_point(cx, cy, r, frac) do
    angle = 2 * :math.pi() * frac - :math.pi() / 2
    {cx + r * :math.cos(angle), cy + r * :math.sin(angle)}
  end

  defp f(n), do: :erlang.float_to_binary(n * 1.0, decimals: 2)

  # Small inline palette derived from the cell-type tokens plus the accent,
  # cycling so any number of slices stays themed. No new CSS vars needed.
  # (Plain list, not ~w, since the values contain parentheses.)
  @chart_palette [
    "var(--lt-cell-number)",
    "var(--lt-cell-temporal)",
    "var(--lt-cell-boolean)",
    "var(--lt-cell-json)",
    "var(--lt-accent)"
  ]
  defp chart_color(i), do: Enum.at(@chart_palette, rem(i, length(@chart_palette)))

  defp upsert_pending_change(pending, %{action: :update, key: key, changes: changes} = change) do
    {matches, others} =
      Enum.split_with(pending, fn
        %{action: :update, key: ^key} -> true
        _ -> false
      end)

    merged_changes =
      matches
      |> Enum.reduce(%{}, fn %{changes: existing}, acc -> Map.merge(acc, existing) end)
      |> Map.merge(changes)

    others ++ [%{change | changes: merged_changes}]
  end

  defp upsert_pending_change(pending, change), do: pending ++ [change]

  defp pending_sql_preview(assigns) do
    assigns.pending_changes
    |> Enum.map_join("\n\n", fn
      %{action: :update, changes: changes, key: key} ->
        set_sql = changes |> Map.keys() |> Enum.map_join(", ", &"#{quote_preview(&1)} = ?")
        where_sql = key |> Map.keys() |> Enum.map_join(" AND ", &"#{quote_preview(&1)} = ?")

        params =
          Enum.map_join(changes, "\n", fn {col, value} ->
            "--   #{col}: #{preview_value(value)}"
          end)

        "UPDATE #{quote_preview(assigns.selected_schema)}.#{quote_preview(assigns.selected_table)} SET #{set_sql} WHERE #{where_sql};\n#{params}"

      %{action: :delete, keys: keys} ->
        key_preview = keys |> Enum.take(5) |> Enum.map_join("; ", &preview_key/1)
        more = if length(keys) > 5, do: " …", else: ""

        "DELETE FROM #{quote_preview(assigns.selected_schema)}.#{quote_preview(assigns.selected_table)} WHERE #{length(keys)} selected primary key row(s);\n--   #{key_preview}#{more}"
    end)
  end

  defp pending_change_label(%{action: :update, changes: changes, key: key}) do
    fields = changes |> Map.keys() |> Enum.join(", ")

    values =
      changes |> Enum.map_join("; ", fn {col, value} -> "#{col}=#{preview_value(value)}" end)

    "Update #{fields} where #{preview_key(key)} — #{values}"
  end

  defp pending_change_label(%{action: :delete, keys: keys}),
    do: "Delete #{length(keys)} selected row(s)"

  defp preview_key(key), do: Enum.map_join(key, ", ", fn {k, v} -> "#{k}=#{preview_value(v)}" end)

  defp preview_value(nil), do: "NULL"

  defp preview_value(value) do
    value
    |> to_string()
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 140)
  end

  defp quote_preview(name), do: ~s("#{String.replace(to_string(name), "\"", "\"\"")}")

  defp export_sql_content("json", assigns) do
    assigns.sql_rows
    |> Enum.map(&row_to_map(&1, assigns.sql_columns, assigns.sql_columns, %{}))
    |> Jason.encode!(pretty: true)
  end

  defp export_sql_content("csv", assigns) do
    rows =
      Enum.map(assigns.sql_rows, &row_to_map(&1, assigns.sql_columns, assigns.sql_columns, %{}))

    csv_rows(assigns.sql_columns, rows)
  end

  defp csv_rows(cols, rows) do
    ([Enum.map_join(cols, ",", &csv_escape/1)] ++
       Enum.map(rows, fn row -> Enum.map_join(cols, ",", &csv_escape(Map.get(row, &1))) end))
    |> Enum.join("\n")
  end

  defp row_to_map(row, all_cols, visible_cols, col_meta) do
    all_cols
    |> Enum.zip(row)
    |> Enum.filter(fn {col, _value} -> col in visible_cols end)
    |> Map.new(fn {col, value} -> {col, export_value(value, col_meta[col])} end)
  end

  defp export_value(value, col_meta) do
    case Coercion.display(value, col_meta && col_meta[:type]) do
      :null -> nil
      string -> string
    end
  end

  defp csv_escape(nil), do: ""

  defp csv_escape(value) do
    value = to_string(value)
    value = if String.starts_with?(value, ["=", "+", "-", "@"]), do: "'" <> value, else: value

    if String.contains?(value, [",", "\"", "\n", "\r"]) do
      ~s("#{String.replace(value, "\"", "\"\"")}")
    else
      value
    end
  end

  defp table_context(%{schema: schema, name: name} = info) do
    columns =
      Enum.map_join(
        info.columns || [],
        "\n",
        &"- #{&1.name}: #{&1.type}#{if &1.nullable, do: "", else: " NOT NULL"}"
      )

    constraints = Enum.map_join(info.constraints || [], "\n", &"- #{&1.name}: #{&1.definition}")
    indexes = Enum.map_join(info.indexes || [], "\n", &"- #{&1.name}: #{&1.definition}")

    """
    # #{schema}.#{name}

    Rows estimate: #{Map.get(info, :estimated_rows, 0)}
    RLS: #{if Map.get(info, :row_level_security?), do: "enabled", else: "disabled"}

    ## Columns
    #{columns}

    ## Constraints
    #{constraints}

    ## Indexes
    #{indexes}
    """
  end

  defp table_context(_), do: ""

  defp empty_filter, do: %{column: nil, op: "contains", value: ""}

  defp parse_filter_params(%{"filters" => filters}) when is_map(filters) do
    filters
    |> Enum.flat_map(fn {idx, attrs} ->
      case parse_index(idx) do
        {:ok, idx} -> [{idx, attrs}]
        :error -> []
      end
    end)
    |> Enum.sort_by(fn {idx, _attrs} -> idx end)
    |> Enum.map(fn {_idx, attrs} ->
      %{
        column: Map.get(attrs, "column", ""),
        op: Map.get(attrs, "op", "contains"),
        value: Map.get(attrs, "value", "")
      }
    end)
    |> then(fn filters -> if filters == [], do: [empty_filter()], else: filters end)
  end

  defp parse_filter_params(_), do: [empty_filter()]

  defp safe_filters(filters) when is_list(filters) do
    Enum.flat_map(filters, fn
      %{column: column, value: value, op: op} when is_binary(column) and column != "" ->
        [%{column: column, op: op, value: value}]

      _ ->
        []
    end)
  end

  defp safe_filters(_), do: []

  defp visible_cells(row, columns, hidden) do
    columns
    |> Enum.zip(row)
    |> Enum.reject(fn {col, _cell} -> MapSet.member?(hidden, col) end)
  end

  defp table_visible?(_table, ""), do: true

  defp table_visible?(table, query),
    do: String.contains?(String.downcase(table), String.downcase(query))

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_column_list(value) do
    value
    |> to_string()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp clear_error(socket), do: assign(socket, :error, nil)

  defp stage_existing_row(socket, params, row, cols, pks, col_meta) do
    # Only send columns whose submitted value actually differs from the row's
    # current value, so untouched fields (e.g. a microsecond-precision
    # timestamptz the input rendered as ms) don't round-trip through
    # truncation.
    changes =
      params
      |> Map.drop(["_index", "_target"])
      |> Enum.reject(fn {col, _} -> col in pks end)
      |> Enum.flat_map(&diff_field(&1, row, cols, col_meta))
      |> Map.new()

    cond do
      changes == %{} ->
        {:noreply, socket |> assign(:editing, nil) |> clear_error()}

      true ->
        case validate_json_changes(changes, col_meta) do
          :ok ->
            change = %{action: :update, changes: changes, key: pk_key(row, cols, pks, col_meta)}

            {:noreply,
             socket
             |> assign(
               editing: nil,
               pending_changes: upsert_pending_change(socket.assigns.pending_changes, change)
             )
             |> clear_error()}

          {:error, reason} ->
            {:noreply, assign(socket, :error, reason)}
        end
    end
  end

  defp validate_json_changes(changes, col_meta) do
    Enum.reduce_while(changes, :ok, fn {col, value}, :ok ->
      type = col_meta[col] && col_meta[col][:type]

      if type in ["json", "jsonb"] and not is_nil(value) do
        case Jason.decode(to_string(value)) do
          {:ok, _decoded} ->
            {:cont, :ok}

          {:error, error} ->
            {:halt, {:error, "Invalid JSON in #{col}: #{Exception.message(error)}"}}
        end
      else
        {:cont, :ok}
      end
    end)
  end

  # Returns `[{col, value}]` (or `[]`) for a submitted form field, only when
  # the user actually changed it relative to the row's current display.
  defp diff_field({col, submitted}, row, columns, col_meta) do
    meta = col_meta[col]
    type = meta && meta[:type]

    kind =
      cond do
        meta && meta[:enum_values] -> :enum
        meta -> Coercion.input_type(meta.type)
        true -> :text
      end

    cell = value_at(row, columns, col)

    original =
      case kind do
        k when k in [:date, :datetime, :time, :integer, :decimal] ->
          Coercion.control_value(cell, k)

        _ ->
          Coercion.edit_value(cell, type)
      end

    submitted = submitted || ""

    if changed?(kind, original, submitted) do
      [{col, blank_to_nil(submitted)}]
    else
      []
    end
  end

  # Whitespace-and-key-order-insensitive equality for JSON; semantic numeric
  # equality for decimals (so `3.10` and `3.1` are the same); plain text
  # equality otherwise.
  defp changed?(:json, original, submitted) do
    case {Jason.decode(original), Jason.decode(submitted)} do
      {{:ok, a}, {:ok, b}} -> a != b
      _ -> original != submitted
    end
  end

  defp changed?(:decimal, original, submitted) do
    with {a, ""} <- Decimal.parse(original),
         {b, ""} <- Decimal.parse(submitted) do
      not Decimal.equal?(a, b)
    else
      _ -> original != submitted
    end
  end

  defp changed?(_kind, original, submitted), do: original != submitted

  defp pk_key(row, columns, primary_keys, col_meta) do
    Map.new(primary_keys, fn pk ->
      type = col_meta[pk] && col_meta[pk][:type]
      {pk, Coercion.edit_value(value_at(row, columns, pk), type)}
    end)
  end

  defp value_at(row, columns, col) do
    case Enum.find_index(columns, &(&1 == col)) do
      nil -> nil
      idx -> Enum.at(row, idx)
    end
  end

  defp total_pages(nil), do: nil
  defp total_pages(count) when count <= 0, do: 1
  defp total_pages(count), do: div(count - 1, @page_size) + 1

  defp row_count_label(nil, _kind), do: "Row count off"
  defp row_count_label(count, :exact), do: "#{count} row(s)"
  defp row_count_label(count, _kind), do: "~#{count} row(s)"

  defp page_label(page, nil, _kind), do: "Page #{page + 1}"
  defp page_label(page, pages, _kind), do: "Page #{page + 1} of #{pages}"

  defp next_disabled?(_page, _pages, :none, rows), do: length(rows) < @page_size
  defp next_disabled?(page, pages, _kind, _rows), do: page + 1 >= pages

  defp humanize(reason) when is_binary(reason), do: reason
  defp humanize(:no_primary_key), do: "This table has no primary key, so rows cannot be edited."
  defp humanize(:key_mismatch), do: "Could not match the row's primary key."
  defp humanize(:no_fields), do: "Nothing to save."
  defp humanize(:no_key), do: "Cannot identify the row to update."
  defp humanize(:no_rows), do: "No rows selected."
  # Anything else (incl. a raw %DBConnection.ConnectionError{} reaching us from a
  # load path) goes through the shared humanizer — never inspect a struct.
  defp humanize(reason), do: Lantern.Errors.humanize(reason)

  # The first column of a brand-new table defaults to an auto-incrementing
  # primary key; subsequent rows start as plain nullable text.
  defp empty_column(:first),
    do: %{
      name: "id",
      type: "bigserial",
      nullable: false,
      primary_key: true,
      length: "",
      scale: ""
    }

  defp empty_column(:more),
    do: %{name: "", type: "text", nullable: true, primary_key: false, length: "", scale: ""}

  # Parses the nested `col[i][...]` params of the create-table form back into an
  # ordered list of column specs.
  defp parse_columns(%{"col" => cols}) when is_map(cols) do
    cols
    |> Enum.flat_map(fn {idx, attrs} ->
      case parse_index(idx) do
        {:ok, idx} -> [{idx, attrs}]
        :error -> []
      end
    end)
    |> Enum.sort_by(fn {idx, _attrs} -> idx end)
    |> Enum.map(fn {_idx, attrs} ->
      %{
        name: Map.get(attrs, "name", ""),
        type: ddl_type(attrs),
        nullable: Map.get(attrs, "nullable", "true") == "true",
        primary_key: Map.get(attrs, "primary_key", "false") == "true",
        length: Map.get(attrs, "length", ""),
        scale: Map.get(attrs, "scale", "")
      }
    end)
  end

  defp parse_columns(_), do: []

  defp base_type(type) when is_binary(type), do: type |> String.split("(", parts: 2) |> hd()
  defp base_type(_), do: "text"

  defp ddl_type(attrs) do
    base = Map.get(attrs, "type", "text")
    length = attrs |> Map.get("length", "") |> to_string() |> String.trim()
    scale = attrs |> Map.get("scale", "") |> to_string() |> String.trim()

    cond do
      length == "" -> base
      scale == "" -> "#{base}(#{length})"
      true -> "#{base}(#{length},#{scale})"
    end
  end

  # Curated type menu — every value passes Lantern.SQL.validate_type/1, so the
  # picker can't produce a rejected type. Listed explicitly (not ~w) so the
  # multi-word "double precision" stays a single option.
  defp type_options do
    [
      "text",
      "varchar",
      "character varying",
      "char",
      "integer",
      "bigint",
      "smallint",
      "serial",
      "bigserial",
      "numeric",
      "decimal",
      "real",
      "double precision",
      "boolean",
      "uuid",
      "json",
      "jsonb",
      "date",
      "time",
      "timestamp",
      "timestamptz",
      "bytea",
      "inet"
    ]
  end

  # Re-lists tables after a structural change and re-selects sensibly: the named
  # table if it still exists (create/rename), otherwise the first remaining one
  # (drop). Resets the per-table view so stale sort/filter/page state can't leak.
  defp reload_tables(socket, prefer) do
    case load_table_list(socket.assigns.source, socket.assigns.selected_schema) do
      {:ok, tables, table_stats, views, enums} ->
        selected = if prefer && prefer in tables, do: prefer, else: List.first(tables)

        socket =
          socket
          |> assign(
            tables: tables,
            table_stats: table_stats,
            views: views,
            enums: enums,
            selected_table: selected,
            dialog: nil,
            sort_by: nil,
            sort_dir: :asc,
            where_clause: "",
            page: 0,
            selected: MapSet.new(),
            editing: nil,
            inserting: false
          )
          |> clear_error()

        if selected do
          socket |> load_schema() |> load_rows()
        else
          assign(socket,
            columns: [],
            primary_keys: [],
            fk_options: %{},
            col_meta: %{},
            rows: [],
            count: 0,
            result_columns: []
          )
        end

      {:error, reason} ->
        assign(socket, :error, humanize(reason))
    end
  end

  defp table_size_title(nil), do: nil

  defp table_size_title(stat) do
    "Total #{stat.total_size} · Table #{stat.table_size} · Indexes #{stat.index_size}"
  end

  defp dialog_title(:create_table), do: "New table"
  defp dialog_title(:table_info), do: "Table info"
  defp dialog_title(:columns), do: "Edit columns"
  defp dialog_title(:rename_table), do: "Rename table"
  defp dialog_title(_), do: ""

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        # `editable` gates editing/deleting EXISTING rows — that needs a primary
        # key to address a row. `insertable` gates ADDING rows, which a table can
        # always do (a PK isn't required to INSERT), so it's on for any loaded
        # table. A PK-less table is therefore insert-only: add rows, but no
        # inline edit or delete. `:read_only` forces both off so the grid is
        # browse-only (and DDL + write SQL are hidden/blocked too).
        editable: assigns.primary_keys != [] and not assigns.read_only,
        insertable: assigns.result_columns != [] and not assigns.read_only,
        # The data-grid actions column carries the edit pencil (editable) and/or
        # insert controls AND the row-detail expand button. The expand button is
        # a read affordance available for every data row — including read-only —
        # so the column must exist whenever there are rows to expand.
        has_row_actions:
          (assigns.primary_keys != [] and not assigns.read_only) or
            (assigns.result_columns != [] and not assigns.read_only) or assigns.rows != [],
        page_size: @page_size,
        pages: total_pages(assigns.count),
        visible_result_columns: visible_columns(assigns.result_columns, assigns.hidden_columns)
      )

    ~H"""
    <div
      id={@dom_id}
      class={["lantern", @class, @fullscreen && "lt-fullscreen"]}
      data-theme={@theme}
      style={root_style(@editor_font_size, @style)}
      role="region"
      aria-label={@title}
      phx-hook="LanternGrid"
      data-table={@selected_table}
      phx-window-keydown={@fullscreen && "exit_fullscreen"}
      phx-key="Escape"
      phx-target={@myself}
    >
      <header class="lt-topbar">
        <div class="lt-topbar-group">
          <button
            type="button"
            class={["lt-iconbtn", @sidebar_open && "lt-iconbtn-on"]}
            phx-click="toggle_sidebar"
            phx-target={@myself}
            title="Toggle tables"
            aria-label="Toggle tables sidebar"
            aria-pressed={to_string(@sidebar_open)}
          >
            <.icon name="hero-bars-3" class="lt-icon" />
          </button>
          <div class="lt-identity">
            <.icon name="hero-table-cells" class="lt-icon lt-identity-icon" />
            <span :if={@selected_table} class="lt-crumb">
              <span class="lt-crumb-schema">{@selected_schema}</span>
              <span class="lt-crumb-sep" aria-hidden="true">/</span>
              <span class="lt-crumb-table">{@selected_table}</span>
            </span>
            <span :if={is_nil(@selected_table)} class="lt-crumb-table">{@title}</span>
          </div>
        </div>
        <div class="lt-topbar-group">
          <div :if={@allow_sql_workspace and @selected_table} class="lt-view-tabs" role="tablist">
            <button
              type="button"
              role="tab"
              aria-selected={to_string(@active_view == :data)}
              class={[@active_view == :data && "lt-active"]}
              phx-click="set_view"
              phx-value-view="data"
              phx-target={@myself}
            >
              Data
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={to_string(@active_view == :sql)}
              class={[@active_view == :sql && "lt-active"]}
              phx-click="set_view"
              phx-value-view="sql"
              phx-target={@myself}
            >
              SQL
            </button>
          </div>
          <details class="lt-menu lt-settings-menu">
            <summary class="lt-iconbtn lt-menu-summary" title="Settings" aria-label="Settings">
              <.icon name="hero-cog-6-tooth" class="lt-icon" />
            </summary>
            <form phx-change="settings" phx-target={@myself} class="lt-menu-panel lt-settings-panel">
              <p class="lt-menu-heading">Display settings</p>
              <label class="lt-settings-toggle">
                <input type="hidden" name="show_row_count" value="false" />
                <input type="checkbox" name="show_row_count" value="true" checked={@show_row_count} />
                <span>Exact row count</span>
              </label>
              <label class="lt-settings-field">
                <span>Bytea display</span>
                <select name="bytea_display" class="lt-input">
                  <option value="hex" selected={@bytea_display == :hex}>Hex</option>
                  <option value="utf8" selected={@bytea_display == :utf8}>UTF-8</option>
                </select>
              </label>
              <label class="lt-settings-field">
                <span>Editor font size</span>
                <select name="editor_font_size" class="lt-input">
                  <option value="12px" selected={@editor_font_size == "12px"}>12px</option>
                  <option value="14px" selected={@editor_font_size == "14px"}>14px</option>
                  <option value="16px" selected={@editor_font_size == "16px"}>16px</option>
                </select>
              </label>
            </form>
          </details>
          <button
            type="button"
            class={["lt-iconbtn", @fullscreen && "lt-iconbtn-on"]}
            phx-click="toggle_fullscreen"
            phx-target={@myself}
            title={if @fullscreen, do: "Exit fullscreen (Esc)", else: "Fullscreen"}
            aria-label={if @fullscreen, do: "Exit fullscreen", else: "Enter fullscreen"}
          >
            <.icon
              name={if @fullscreen, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
              class="lt-icon"
            />
          </button>
        </div>
      </header>

      <div :if={@error} class="lt-error">{@error}</div>

      <div class="lt-body">
        <aside :if={@sidebar_open} class="lt-sidebar">
          <div class="lt-sidebar-head">
            <span class="lt-sidebar-title">Tables</span>
            <button
              :if={not @read_only}
              type="button"
              class="lt-iconbtn"
              phx-click="open_create_table"
              phx-target={@myself}
              title="New table"
              aria-label="Create a new table"
            >
              <.icon name="hero-plus" class="lt-icon" />
            </button>
          </div>
          <form :if={length(@schemas) > 1} phx-change="select_schema" phx-target={@myself} class="lt-schema-form">
            <label class="lt-sidebar-title" for={"#{@dom_id}-schema"}>Schema</label>
            <select id={"#{@dom_id}-schema"} name="schema" class="lt-input lt-schema-select">
              <option :for={schema <- @schemas} value={schema} selected={schema == @selected_schema}>
                {schema}
              </option>
            </select>
          </form>
          <form phx-change="search_tables" phx-target={@myself} class="lt-search-form">
            <input type="text" name="q" value={@table_search} placeholder="Search tables…" class="lt-input" />
          </form>
          <nav class="lt-table-list">
            <button
              :for={t <- Enum.filter(@tables, &table_visible?(&1, @table_search))}
              type="button"
              class={["lt-table-item", t == @selected_table && "lt-active"]}
              phx-click="select_table"
              phx-value-table={t}
              phx-target={@myself}
              title={table_size_title(@table_stats[t])}
            >
              <span class="lt-table-name">{t}</span>
              <span :if={@table_stats[t]} class="lt-table-size">{@table_stats[t].total_size}</span>
            </button>
          </nav>
          <details :if={@views != []} class="lt-sidebar-section">
            <summary>Views ({length(@views)})</summary>
            <div class="lt-sidebar-meta-list">
              <span :for={view <- @views} class="lt-sidebar-meta-item">{view}</span>
            </div>
          </details>
          <details :if={@enums != []} class="lt-sidebar-section">
            <summary>Enums ({length(@enums)})</summary>
            <div class="lt-sidebar-meta-list">
              <span :for={enum <- @enums} class="lt-sidebar-meta-item" title={Enum.join(enum.values, ", ")}>{enum.name}</span>
            </div>
          </details>
        </aside>

        <div class="lt-content">
          <div :if={is_nil(@selected_table)} class="lt-empty">
            Select a table to browse and edit its rows.
          </div>

          <div :if={@selected_table} class="lt-main">
            <div :if={@active_view == :data and @pending_changes != []} class="lt-pending-bar">
              <div>
                <strong>{length(@pending_changes)} pending change(s)</strong>
                <p>Review generated SQL before applying. Changes save in one transaction.</p>
              </div>
              <div class="lt-pending-actions">
                <button type="button" class="lt-btn lt-btn-primary" phx-click="apply_pending" phx-target={@myself}>Apply changes</button>
                <button type="button" class="lt-btn" phx-click="discard_pending" phx-target={@myself}>Discard</button>
              </div>
              <details class="lt-pending-preview">
                <summary>SQL preview</summary>
                <pre>{pending_sql_preview(assigns)}</pre>
                <div class="lt-pending-list">
                  <div :for={{change, i} <- Enum.with_index(@pending_changes)} class="lt-pending-item">
                    <span>{pending_change_label(change)}</span>
                    <button type="button" class="lt-iconbtn" phx-click="remove_pending" phx-value-index={i} phx-target={@myself} aria-label="Remove pending change"><.icon name="hero-x-mark" class="lt-icon" /></button>
                  </div>
                </div>
              </details>
            </div>

            <div :if={@active_view == :data} class="lt-toolbar">
              <form :if={!@allow_raw_filter} phx-change="safe_filters" phx-submit="safe_filters" phx-target={@myself} class="lt-filter-form lt-safe-filter-form">
                <div :for={{filter, i} <- Enum.with_index(@safe_filters)} class="lt-filter-row">
                  <select name={"filters[#{i}][column]"} class="lt-input">
                    <option value="">Filter column…</option>
                    <option :for={col <- @result_columns} value={col} selected={filter.column == col}>{col}</option>
                  </select>
                  <select name={"filters[#{i}][op]"} class="lt-input">
                    <option value="contains" selected={filter.op == "contains"}>contains</option>
                    <option value="eq" selected={filter.op == "eq"}>equals</option>
                    <option value="neq" selected={filter.op == "neq"}>not equals</option>
                    <option value="gt" selected={filter.op == "gt"}>greater than</option>
                    <option value="lt" selected={filter.op == "lt"}>less than</option>
                    <option value="is_null" selected={filter.op == "is_null"}>is null</option>
                    <option value="is_not_null" selected={filter.op == "is_not_null"}>is not null</option>
                  </select>
                  <input type="text" name={"filters[#{i}][value]"} value={filter.value} placeholder="Value" class="lt-input" />
                  <button type="button" class="lt-iconbtn" phx-click="remove_safe_filter" phx-value-index={i} phx-target={@myself} aria-label="Remove filter" title="Remove filter">
                    <.icon name="hero-x-mark" class="lt-icon" />
                  </button>
                </div>
                <div class="lt-filter-actions">
                  <button type="button" class="lt-btn lt-btn-sm" phx-click="add_safe_filter" phx-target={@myself}>Add filter</button>
                  <button type="button" class="lt-btn lt-btn-sm" phx-click="clear_safe_filters" phx-target={@myself}>Clear</button>
                </div>
              </form>
              <form
                :if={@allow_raw_filter}
                phx-change="filter"
                phx-submit="filter"
                phx-target={@myself}
                class="lt-filter-form"
              >
                <div class="lt-filter-wrap">
                  <input
                    type="text"
                    name="where_clause"
                    value={@where_clause}
                    phx-debounce="400"
                    placeholder="Filter rows, e.g. username LIKE '%a%'"
                    class="lt-input lt-filter"
                  />
                  <details class="lt-help">
                    <summary class="lt-help-btn" title="Filter syntax">?</summary>
                    <div class="lt-help-panel">
                      <p class="lt-help-note">
                        Type a condition only — no <code>WHERE</code>. Quote text with single
                        quotes (<code>'…'</code>), not double quotes. Click an example to apply it.
                      </p>
                      <button
                        :for={ex <- filter_examples()}
                        type="button"
                        class="lt-help-example"
                        phx-click="apply_filter"
                        phx-value-q={ex}
                        phx-target={@myself}
                      >
                        <code>{ex}</code>
                      </button>
                    </div>
                  </details>
                </div>
              </form>
              <div class="lt-actions">
                <details :if={MapSet.size(@selected) > 0} class="lt-menu">
                  <summary class="lt-btn">Selected ({MapSet.size(@selected)})</summary>
                  <div class="lt-menu-panel">
                    <button type="button" class="lt-menu-item" phx-click="copy_selected_json" phx-target={@myself}>Copy selected JSON</button>
                    <button type="button" class="lt-menu-item" phx-click="export_selected" phx-value-format="json" phx-target={@myself}>Export selected JSON</button>
                    <button type="button" class="lt-menu-item" phx-click="export_selected" phx-value-format="csv" phx-target={@myself}>Export selected CSV</button>
                    <button
                      :if={@editable}
                      type="button"
                      class="lt-menu-item lt-menu-item-danger"
                      phx-click="delete_selected"
                      phx-target={@myself}
                      data-confirm={"Delete #{MapSet.size(@selected)} row(s)?"}
                    >
                      <.icon name="hero-trash" class="lt-icon" /> Delete selected
                    </button>
                  </div>
                </details>
                <details class="lt-menu">
                  <summary class="lt-btn" title="Columns">Columns</summary>
                  <div class="lt-menu-panel lt-columns-panel">
                    <button type="button" class="lt-menu-item" phx-click="show_all_columns" phx-target={@myself}>Show all</button>
                    <button
                      :for={col <- @result_columns}
                      type="button"
                      class="lt-menu-item"
                      phx-click="toggle_column"
                      phx-value-column={col}
                      phx-target={@myself}
                    >
                      <span>{if MapSet.member?(@hidden_columns, col), do: "☐", else: "☑"}</span> {col}
                    </button>
                  </div>
                </details>
                <button
                  :if={@insertable}
                  type="button"
                  class="lt-btn"
                  phx-click="new_row"
                  phx-target={@myself}
                >
                  <.icon name="hero-plus" class="lt-icon" /> New row
                </button>
                <button
                  :if={@active_view == :data}
                  type="button"
                  class="lt-btn lt-btn-icon"
                  phx-click="refresh"
                  phx-target={@myself}
                  title="Refresh"
                  aria-label="Refresh"
                >
                  <.icon name="hero-arrow-path" class="lt-icon" />
                </button>
                <details class="lt-menu">
                  <summary class="lt-menu-btn" title="Table actions" aria-label="Table actions">
                    <.icon name="hero-ellipsis-vertical" class="lt-icon" />
                  </summary>
                  <div class="lt-menu-panel">
                    <button
                      type="button"
                      class="lt-menu-item"
                      phx-click="open_table_info"
                      phx-target={@myself}
                    >
                      <.icon name="hero-information-circle" class="lt-icon" /> Table info
                    </button>
                    <button type="button" class="lt-menu-item" phx-click="export" phx-value-format="json" phx-target={@myself}>Export visible JSON</button>
                    <button type="button" class="lt-menu-item" phx-click="export" phx-value-format="csv" phx-target={@myself}>Export visible CSV</button>
                    <button type="button" class="lt-menu-item" phx-click="copy_context" phx-target={@myself}>Copy schema context</button>
                    <button
                      :if={not @read_only}
                      type="button"
                      class="lt-menu-item"
                      phx-click="open_columns"
                      phx-target={@myself}
                    >
                      <.icon name="hero-table-cells" class="lt-icon" /> Edit columns
                    </button>
                    <button
                      :if={not @read_only}
                      type="button"
                      class="lt-menu-item"
                      phx-click="open_rename_table"
                      phx-target={@myself}
                    >
                      <.icon name="hero-pencil-square" class="lt-icon" /> Rename table
                    </button>
                    <button
                      :if={not @read_only}
                      type="button"
                      class="lt-menu-item lt-menu-item-danger"
                      phx-click="drop_table"
                      phx-target={@myself}
                      data-confirm={"Drop table \"#{@selected_table}\"? This permanently deletes the table and all its data."}
                    >
                      <.icon name="hero-trash" class="lt-icon" /> Drop table
                    </button>
                  </div>
                </details>
              </div>
            </div>

            <div :if={@active_view == :sql} class="lt-sql-workspace">
              <form phx-submit="run_sql" phx-change="sql_change" phx-target={@myself} class="lt-sql-form">
                <.editor
                  id={"#{@dom_id}-sql-editor"}
                  name="sql"
                  rows={8}
                  language={LiveCode.Languages.SQL}
                  value={@sql_text}
                  context={sql_editor_context(assigns)}
                  diagnostics={if @sql_error, do: [%LiveCode.Diagnostic{message: @sql_error, severity: :error}], else: []}
                  class="lt-sql-editor"
                />
                <div class="lt-sql-actions">
                  <span class="lt-note">
                    {cond do
                      @read_only or @sql_mode == :read_only -> "Read-only SQL mode. SELECT and EXPLAIN only."
                      @sql_mode == :guarded -> "Write-enabled · DROP, TRUNCATE, and unqualified DELETE/UPDATE require confirmation."
                      true -> "Trusted operator SQL. Runs with the supplied connection role."
                    end}
                  </span>
                  <div class="lt-sql-buttons">
                    <button id={"#{@dom_id}-run-sql"} type="submit" name="action" value="run" class="lt-btn lt-btn-primary" data-confirm={@sql_mode not in [:guarded] and dangerous_sql?(@sql_text) && "Run potentially destructive SQL?"}>Run query</button>
                    <button type="submit" name="action" value="explain" class="lt-btn">Explain</button>
                    <button type="submit" name="action" value="analyze" class="lt-btn">Analyze</button>
                  </div>
                </div>
              </form>
              <form phx-submit="save_sql_query" phx-target={@myself} class="lt-sql-save-form">
                <input type="text" name="name" value={@sql_query_name} placeholder="Saved query name" class="lt-input" />
                <input type="hidden" name="sql" value={@sql_text} />
                <button type="submit" class="lt-btn">Save query</button>
              </form>
              <div class="lt-sql-panels">
                <section class="lt-sql-panel">
                  <h4>Saved</h4>
                  <div :for={{query, i} <- Enum.with_index(@saved_queries)} class="lt-saved-query-row">
                    <button type="button" class="lt-menu-item" phx-click="load_sql_query" phx-value-index={i} phx-target={@myself}>{query.name}</button>
                    <button type="button" class="lt-iconbtn" phx-click="delete_sql_query" phx-value-index={i} phx-target={@myself} aria-label={"Delete saved query #{query.name}"}>
                      <.icon name="hero-x-mark" class="lt-icon" />
                    </button>
                  </div>
                  <p :if={@saved_queries == []} class="lt-info-empty">No saved queries.</p>
                </section>
                <section class="lt-sql-panel">
                  <h4>History</h4>
                  <button :for={{sql, i} <- Enum.with_index(@sql_history)} type="button" class="lt-menu-item" phx-click="load_sql_history" phx-value-index={i} phx-target={@myself}>{String.slice(sql, 0, 80)}</button>
                  <p :if={@sql_history == []} class="lt-info-empty">No query history.</p>
                </section>
              </div>
              <div :if={@sql_columns != []} class="lt-sql-result-actions">
                <button type="button" class="lt-btn lt-btn-sm" phx-click="copy_sql_json" phx-target={@myself}>Copy JSON</button>
                <button type="button" class="lt-btn lt-btn-sm" phx-click="export_sql" phx-value-format="json" phx-target={@myself}>Export JSON</button>
                <button type="button" class="lt-btn lt-btn-sm" phx-click="export_sql" phx-value-format="csv" phx-target={@myself}>Export CSV</button>
              </div>
              <% sql_chart_points = chart_points(@sql_columns, @sql_rows) %>
              <.chart_render
                :if={sql_chart_points != []}
                points={sql_chart_points}
                kind={@chart_kind}
                title="Quick chart"
                myself={@myself}
              />
              <div :if={@sql_error} class="lt-error">{@sql_error}</div>
              <div class="lt-grid lt-sql-results">
                <table class="lt-table">
                  <thead>
                    <tr>
                      <th :for={col <- @sql_columns} class="lt-th">{col}</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={row <- @sql_rows} class="lt-row">
                      <td :for={cell <- row} class="lt-td">{render_cell(cell, nil, @bytea_display)}</td>
                    </tr>
                    <tr :if={@sql_columns == [] and @sql_error == nil}>
                      <td class="lt-empty-row">Run a SQL query to see results.</td>
                    </tr>
                    <tr :if={@sql_columns != [] and @sql_rows == []}>
                      <td colspan={length(@sql_columns)} class="lt-empty-row">No rows returned.</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <div :if={@active_view == :data and @insertable and not @editable} class="lt-note">
              This table has no primary key — you can add rows, but existing rows can't be edited or deleted.
            </div>

            <div
              :if={@active_view == :data}
              id={"#{@dom_id}-grid"}
              class="lt-grid"
            >
              <table class="lt-table">
                <thead>
                  <tr>
                    <th :if={@editable} class="lt-check">
                      <input
                        type="checkbox"
                        phx-click="toggle_all"
                        phx-target={@myself}
                        checked={MapSet.size(@selected) == length(@rows) and @rows != []}
                        aria-label="Select all rows"
                      />
                    </th>
                    <th
                      :for={col <- @visible_result_columns}
                      data-col={col}
                      class={["lt-th", numeric_col?(@col_meta[col]) && "lt-th-num"]}
                    >
                      <span
                        class="lt-sort"
                        phx-click="sort_column"
                        phx-value-column={col}
                        phx-target={@myself}
                      >
                        {col}
                        <.icon
                          :if={@sort_by == col}
                          name={
                            if @sort_dir == :asc, do: "hero-chevron-up", else: "hero-chevron-down"
                          }
                          class="lt-icon lt-icon-sm"
                        />
                      </span>
                      <span :if={@col_meta[col] && @col_meta[col].type} class="lt-th-type">{@col_meta[col].type}</span>
                      <button
                        :if={numeric_col?(@col_meta[col])}
                        type="button"
                        class={["lt-iconbtn lt-th-chart", @chart_column == col && "lt-iconbtn-on"]}
                        phx-click="chart_column"
                        phx-value-column={col}
                        phx-target={@myself}
                        title={if @chart_column == col, do: "Hide chart", else: "Chart this column"}
                        aria-label={if @chart_column == col, do: "Hide chart for #{col}", else: "Chart #{col}"}
                        aria-pressed={to_string(@chart_column == col)}
                      >
                        <.icon name="hero-chart-bar" class="lt-icon lt-icon-sm" />
                      </button>
                      <span class="lt-resize" data-col={col} />
                    </th>
                    <th :if={@has_row_actions} class="lt-th-actions"></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@inserting} class="lt-row lt-row-insert">
                    <td :if={@editable} class="lt-check"></td>
                    <td :for={col <- @visible_result_columns} class="lt-td-edit">
                      <.field_input
                        form={"#{@dom_id}-insert"}
                        name={col}
                        col={@col_meta[col]}
                        fk={@fk_options[col]}
                        value={nil}
                      />
                    </td>
                    <td :if={@editable or @insertable} class="lt-td-edit">
                      <form
                        id={"#{@dom_id}-insert"}
                        phx-submit="save_insert"
                        phx-target={@myself}
                        class="lt-rowform"
                      >
                        <button type="submit" class="lt-iconbtn lt-iconbtn-save" title="Save" aria-label="Save row">
                          <.icon name="hero-check" class="lt-icon" />
                        </button>
                        <button
                          type="button"
                          phx-click="cancel_insert"
                          phx-target={@myself}
                          class="lt-iconbtn"
                          title="Cancel"
                          aria-label="Cancel insert"
                        >
                          <.icon name="hero-x-mark" class="lt-icon" />
                        </button>
                      </form>
                    </td>
                  </tr>

                  <tr :for={{row, index} <- Enum.with_index(@rows)} class="lt-row">
                    <td :if={@editable} class="lt-check">
                      <input
                        type="checkbox"
                        phx-click="toggle_row"
                        phx-value-index={index}
                        phx-target={@myself}
                        checked={MapSet.member?(@selected, index)}
                        aria-label={"Select row #{index + 1}"}
                      />
                    </td>

                    <%= if @editing == index do %>
                      <td :for={{col, cell} <- visible_cells(row, @result_columns, @hidden_columns)} class="lt-td-edit">
                        <.field_input
                          :if={col not in @primary_keys}
                          form={"#{@dom_id}-edit-#{index}"}
                          name={col}
                          col={@col_meta[col]}
                          fk={@fk_options[col]}
                          value={cell}
                        />
                        <span :if={col in @primary_keys} class="lt-pk">{render_cell(cell, @col_meta[col], @bytea_display)}</span>
                      </td>
                      <td class="lt-td-edit">
                        <form
                          id={"#{@dom_id}-edit-#{index}"}
                          phx-submit="save_row"
                          phx-target={@myself}
                          class="lt-rowform"
                        >
                          <input type="hidden" name="_index" value={index} />
                          <button type="submit" class="lt-iconbtn lt-iconbtn-save" title="Save" aria-label="Save row">
                            <.icon name="hero-check" class="lt-icon" />
                          </button>
                          <button
                            type="button"
                            phx-click="cancel_edit"
                            phx-target={@myself}
                            class="lt-iconbtn"
                            title="Cancel"
                            aria-label="Cancel edit"
                          >
                            <.icon name="hero-x-mark" class="lt-icon" />
                          </button>
                        </form>
                      </td>
                    <% else %>
                      <td
                        :for={{col, cell} <- visible_cells(row, @result_columns, @hidden_columns)}
                        data-col={col}
                        data-fk={fk_clickable?(@col_meta[col], cell) && "1"}
                        data-fk-value={fk_clickable?(@col_meta[col], cell) && Coercion.edit_value(cell, @col_meta[col] && @col_meta[col].type)}
                        class={["lt-td", cell_type_class(cell, @col_meta[col])]}
                      >
                        <button
                          :if={fk_clickable?(@col_meta[col], cell)}
                          type="button"
                          class="lt-fk-link"
                          phx-click="open_fk"
                          phx-value-column={col}
                          phx-value-value={Coercion.edit_value(cell, @col_meta[col] && @col_meta[col].type)}
                          phx-target={@myself}
                          title="Open referenced row"
                        >
                          {render_cell(cell, @col_meta[col], @bytea_display)}
                        </button>
                        <span :if={!fk_clickable?(@col_meta[col], cell)}>
                          {render_cell(cell, @col_meta[col], @bytea_display)}
                        </span>
                      </td>
                      <td :if={@has_row_actions} class="lt-td-actions">
                        <button
                          type="button"
                          phx-click="open_row"
                          phx-value-index={index}
                          phx-target={@myself}
                          class="lt-iconbtn lt-row-expand"
                          aria-label={"View row #{index + 1} detail"}
                          title="View row detail"
                        >
                          <.icon name="hero-chevron-right" class="lt-icon" />
                        </button>
                        <button
                          :if={@editable}
                          type="button"
                          phx-click="edit_row"
                          phx-value-index={index}
                          phx-target={@myself}
                          class="lt-iconbtn"
                          aria-label={"Edit row #{index + 1}"}
                          title="Edit"
                        >
                          <.icon name="hero-pencil-square" class="lt-icon" />
                        </button>
                      </td>
                    <% end %>
                  </tr>

                  <tr :if={@rows == [] and not @inserting}>
                    <td colspan={length(@result_columns) + 2} class="lt-empty-row">No rows.</td>
                  </tr>
                </tbody>
              </table>
            </div>

            <% column_chart_points =
              if @active_view == :data and @chart_column,
                do:
                  chart_points_from_column(
                    @chart_column,
                    @chart_label_column,
                    @result_columns,
                    @rows,
                    @primary_keys
                  ),
                else: [] %>
            <.chart_render
              :if={column_chart_points != []}
              points={column_chart_points}
              kind={@chart_kind}
              title={"#{@chart_column}"}
              label_options={Enum.reject(@result_columns, &(&1 == @chart_column))}
              label_column={@chart_label_column}
              on_label="set_chart_label"
              myself={@myself}
              on_close="chart_column"
              close_value={@chart_column}
            />

            <div :if={@active_view == :data} class="lt-footer">
              <span>{row_count_label(@count, @count_kind)}</span>
              <div class="lt-pager">
                <button
                  type="button"
                  class="lt-btn"
                  phx-click="page"
                  phx-value-dir="prev"
                  phx-target={@myself}
                  disabled={@page == 0}
                >
                  Prev
                </button>
                <span>{page_label(@page, @pages, @count_kind)}</span>
                <button
                  type="button"
                  class="lt-btn"
                  phx-click="page"
                  phx-value-dir="next"
                  phx-target={@myself}
                  disabled={next_disabled?(@page, @pages, @count_kind, @rows)}
                >
                  Next
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.portal :if={@dialog} id={"#{@dom_id}-dialog-portal"} target="body">
        <div
          class={["lantern lt-dialog-portal", @class]}
          data-theme={@theme}
          style={root_style(@editor_font_size, @style)}
        >
          <div class="lt-modal">
            <button
              type="button"
              class="lt-modal-backdrop"
              phx-click="close_dialog"
              phx-target={@myself}
              aria-label="Close dialog"
            />
            <div class={"lt-modal-card #{if @dialog in [:table_info, :columns], do: "lt-modal-card-wide"}"} role="dialog" aria-modal="true" aria-labelledby={"#{@dom_id}-dialog-title"}>
              <div class="lt-modal-head">
                <h3 id={"#{@dom_id}-dialog-title"} class="lt-modal-title">{dialog_title(@dialog)}</h3>
                <button
                  type="button"
                  class="lt-iconbtn"
                  phx-click="close_dialog"
                  phx-target={@myself}
                  aria-label="Close"
                >
                  <.icon name="hero-x-mark" class="lt-icon" />
                </button>
              </div>

              <div :if={@error} class="lt-error">{@error}</div>

              <div class="lt-modal-body">
                <%= case @dialog do %>
                  <% :create_table -> %>
                    <form
                      phx-change="sync_new_table"
                      phx-submit="create_table"
                      phx-target={@myself}
                      class="lt-form"
                    >
                      <label class="lt-form-label">
                        Table name
                        <input
                          type="text"
                          name="table"
                          value={@new_table_name}
                          placeholder="my_table"
                          autocomplete="off"
                          class="lt-input"
                        />
                      </label>

                      <div class="lt-form-section">
                        <div class="lt-form-section-head">
                          <span>Columns</span>
                          <button
                            type="button"
                            class="lt-btn lt-btn-sm"
                            phx-click="add_column_row"
                            phx-target={@myself}
                          >
                            <.icon name="hero-plus" class="lt-icon" /> Add
                          </button>
                        </div>

                        <div class="lt-colgrid">
                          <div :for={{c, i} <- Enum.with_index(@new_columns)} class="lt-colgrid-row">
                            <input
                              type="text"
                              name={"col[#{i}][name]"}
                              value={c.name}
                              placeholder="column_name"
                              autocomplete="off"
                              class="lt-input"
                            />
                            <select name={"col[#{i}][type]"} class="lt-input" aria-label="Column type">
                              <option :for={t <- type_options()} value={t} selected={base_type(c.type) == t}>
                                {t}
                              </option>
                            </select>
                            <input
                              type="number"
                              min="1"
                              name={"col[#{i}][length]"}
                              value={Map.get(c, :length, "")}
                              placeholder="len/precision"
                              aria-label="Length or precision"
                              class="lt-input"
                            />
                            <input
                              type="number"
                              min="0"
                              name={"col[#{i}][scale]"}
                              value={Map.get(c, :scale, "")}
                              placeholder="scale"
                              aria-label="Scale"
                              class="lt-input"
                            />
                            <label class="lt-check-label" title="Allow NULL">
                              <input type="hidden" name={"col[#{i}][nullable]"} value="false" />
                              <input
                                type="checkbox"
                                name={"col[#{i}][nullable]"}
                                value="true"
                                checked={c.nullable}
                              /> Null
                            </label>
                            <label class="lt-check-label" title="Primary key">
                              <input type="hidden" name={"col[#{i}][primary_key]"} value="false" />
                              <input
                                type="checkbox"
                                name={"col[#{i}][primary_key]"}
                                value="true"
                                checked={c.primary_key}
                              /> PK
                            </label>
                            <button
                              type="button"
                              class="lt-iconbtn"
                              phx-click="remove_column_row"
                              phx-value-index={i}
                              phx-target={@myself}
                              title="Remove column"
                              aria-label="Remove column"
                            >
                              <.icon name="hero-x-mark" class="lt-icon" />
                            </button>
                          </div>
                        </div>
                      </div>

                      <div class="lt-modal-foot">
                        <button
                          type="button"
                          class="lt-btn"
                          phx-click="close_dialog"
                          phx-target={@myself}
                        >
                          Cancel
                        </button>
                        <button type="submit" class="lt-btn lt-btn-primary">Create table</button>
                      </div>
                    </form>
                  <% :table_info -> %>
                    <div :if={@table_info} class="lt-info">
                      <div class="lt-info-grid">
                        <div class="lt-info-card">
                          <span class="lt-info-label">Table</span>
                          <strong>{@table_info.schema}.{@table_info.name}</strong>
                        </div>
                        <div class="lt-info-card">
                          <span class="lt-info-label">Rows</span>
                          <strong>{@count}</strong>
                          <small>estimate: {@table_info.estimated_rows}</small>
                        </div>
                        <div class="lt-info-card">
                          <span class="lt-info-label">Total size</span>
                          <strong>{@table_info.stats && @table_info.stats.total_size}</strong>
                          <small>
                            table {@table_info.stats && @table_info.stats.table_size} · indexes {@table_info.stats && @table_info.stats.index_size}
                          </small>
                        </div>
                        <div class="lt-info-card">
                          <span class="lt-info-label">RLS</span>
                          <strong>{if @table_info.row_level_security?, do: "Enabled", else: "Disabled"}</strong>
                        </div>
                      </div>

                      <section class="lt-info-section">
                        <h4>Columns</h4>
                        <div class="lt-info-list">
                          <div :for={c <- @table_info.columns} class="lt-info-row">
                            <code>{c.name}</code>
                            <span>{c.type}</span>
                            <span :if={c.name in @table_info.primary_keys} class="lt-pill">PK</span>
                            <span :if={!c.nullable} class="lt-pill">NOT NULL</span>
                            <span :if={c.fk} class="lt-pill">FK → {c.fk.schema}.{c.fk.table}.{c.fk.column}</span>
                          </div>
                        </div>
                      </section>

                      <section class="lt-info-section">
                        <h4>Constraints</h4>
                        <div class="lt-info-list">
                          <div :for={con <- @table_info.constraints} class="lt-info-row lt-info-row-stack">
                            <div class="lt-info-row-head">
                              <code>{con.name}</code>
                              <button
                                :if={not @read_only}
                                type="button"
                                class="lt-btn lt-btn-sm lt-btn-danger"
                                phx-click="drop_constraint"
                                phx-value-constraint={con.name}
                                phx-target={@myself}
                                data-confirm={"Drop constraint #{con.name}?"}
                              >
                                Drop
                              </button>
                            </div>
                            <span class="lt-pill">{con.type}</span>
                            <span>{con.definition}</span>
                          </div>
                          <p :if={@table_info.constraints == []} class="lt-info-empty">No constraints.</p>
                        </div>
                      </section>

                      <section class="lt-info-section">
                        <h4>Indexes</h4>
                        <div class="lt-info-list">
                          <div :for={idx <- @table_info.indexes} class="lt-info-row lt-info-row-stack">
                            <div class="lt-info-row-head">
                              <code>{idx.name}</code>
                              <button
                                :if={not @read_only}
                                type="button"
                                class="lt-btn lt-btn-sm lt-btn-danger"
                                phx-click="drop_index"
                                phx-value-index={idx.name}
                                phx-target={@myself}
                                data-confirm={"Drop index #{idx.name}?"}
                              >
                                Drop
                              </button>
                            </div>
                            <span>{idx.definition}</span>
                          </div>
                          <p :if={@table_info.indexes == []} class="lt-info-empty">No indexes.</p>
                        </div>
                        <form
                          :if={not @read_only}
                          phx-submit="create_index"
                          phx-target={@myself}
                          class="lt-index-form"
                        >
                          <input type="text" name="name" placeholder="index_name" class="lt-input" />
                          <input type="text" name="columns" placeholder="columns, comma-separated" class="lt-input" />
                          <button type="submit" class="lt-btn">Create index</button>
                        </form>
                      </section>
                    </div>
                  <% :columns -> %>
                    <div class="lt-cols">
                      <div :for={c <- @columns} class="lt-col-row">
                        <form phx-submit="rename_column" phx-target={@myself} class="lt-col-rename">
                          <input type="hidden" name="from" value={c.name} />
                          <input
                            type="text"
                            name="name"
                            value={c.name}
                            autocomplete="off"
                            aria-label={"Rename column #{c.name}"}
                            class="lt-input"
                          />
                          <button
                            type="submit"
                            class="lt-iconbtn lt-iconbtn-save"
                            title="Rename column"
                            aria-label={"Rename #{c.name}"}
                          >
                            <.icon name="hero-check" class="lt-icon" />
                          </button>
                        </form>
                        <form phx-submit="alter_column" phx-target={@myself} class="lt-col-alter">
                          <input type="hidden" name="column" value={c.name} />
                          <select name="type" class="lt-input" aria-label={"Type for #{c.name}"}>
                            <option :for={t <- type_options()} value={t} selected={base_type(c.type) == t}>{t}</option>
                          </select>
                          <input type="number" min="1" name="length" placeholder="len/precision" class="lt-input" aria-label={"Length or precision for #{c.name}"} />
                          <input type="number" min="0" name="scale" placeholder="scale" class="lt-input" aria-label={"Scale for #{c.name}"} />
                          <label class="lt-check-label" title="Allow NULL">
                            <input type="hidden" name="nullable" value="false" />
                            <input type="checkbox" name="nullable" value="true" checked={c.nullable} /> Null
                          </label>
                          <button type="submit" class="lt-btn lt-btn-sm">Apply</button>
                        </form>
                        <button
                          type="button"
                          class="lt-iconbtn"
                          phx-click="drop_column"
                          phx-value-column={c.name}
                          phx-target={@myself}
                          data-confirm={"Drop column \"#{c.name}\"? This permanently deletes its data."}
                          title="Drop column"
                          aria-label={"Drop #{c.name}"}
                        >
                          <.icon name="hero-trash" class="lt-icon" />
                        </button>
                      </div>

                      <form phx-submit="add_column" phx-target={@myself} class="lt-col-add">
                        <input
                          type="text"
                          name="name"
                          placeholder="new_column"
                          autocomplete="off"
                          aria-label="New column name"
                          class="lt-input"
                        />
                        <select name="type" class="lt-input" aria-label="New column type">
                          <option :for={t <- type_options()} value={t} selected={t == "text"}>{t}</option>
                        </select>
                        <input type="number" min="1" name="length" placeholder="len/precision" class="lt-input" aria-label="New column length or precision" />
                        <input type="number" min="0" name="scale" placeholder="scale" class="lt-input" aria-label="New column scale" />
                        <label class="lt-check-label" title="Allow NULL">
                          <input type="hidden" name="nullable" value="false" />
                          <input type="checkbox" name="nullable" value="true" checked /> Null
                        </label>
                        <button type="submit" class="lt-btn">
                          <.icon name="hero-plus" class="lt-icon" /> Add
                        </button>
                      </form>
                    </div>
                  <% :rename_table -> %>
                    <form phx-submit="rename_table" phx-target={@myself} class="lt-form">
                      <label class="lt-form-label">
                        New name for "{@selected_table}"
                        <input
                          type="text"
                          name="name"
                          value={@selected_table}
                          autocomplete="off"
                          class="lt-input"
                        />
                      </label>
                      <div class="lt-modal-foot">
                        <button
                          type="button"
                          class="lt-btn"
                          phx-click="close_dialog"
                          phx-target={@myself}
                        >
                          Cancel
                        </button>
                        <button type="submit" class="lt-btn lt-btn-primary">Rename</button>
                      </div>
                    </form>
                  <% _ -> %>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </.portal>

      <.portal :if={@open_row != nil} id={"#{@dom_id}-row-portal"} target="body">
        <div
          class={["lantern lt-dialog-portal", @class]}
          data-theme={@theme}
          style={root_style(@editor_font_size, @style)}
        >
          <div
            class="lt-drawer"
            phx-window-keydown="close_row"
            phx-key="Escape"
            phx-target={@myself}
          >
            <button
              type="button"
              class="lt-drawer-backdrop"
              phx-click="close_row"
              phx-target={@myself}
              aria-label="Close row detail"
            />
            <div
              class="lt-drawer-panel"
              role="dialog"
              aria-modal="true"
              aria-labelledby={"#{@dom_id}-drawer-title"}
            >
              <div class="lt-drawer-head">
                <h3 id={"#{@dom_id}-drawer-title"} class="lt-drawer-title">Row detail</h3>
                <button
                  type="button"
                  class="lt-iconbtn"
                  phx-click="close_row"
                  phx-target={@myself}
                  aria-label="Close"
                >
                  <.icon name="hero-x-mark" class="lt-icon" />
                </button>
              </div>
              <div class="lt-drawer-body">
                <div
                  :for={{col, cell} <- Enum.zip(@result_columns, Enum.at(@rows, @open_row) || [])}
                  class="lt-drawer-field"
                >
                  <div class="lt-drawer-field-head">
                    <span class="lt-drawer-field-name">{col}</span>
                    <span :if={@col_meta[col] && @col_meta[col].type} class="lt-drawer-field-type">{@col_meta[col].type}</span>
                  </div>
                  <button
                    :if={fk_clickable?(@col_meta[col], cell)}
                    type="button"
                    class="lt-drawer-field-value lt-drawer-field-fk"
                    phx-click="open_fk"
                    phx-value-column={col}
                    phx-value-value={Coercion.edit_value(cell, @col_meta[col] && @col_meta[col].type)}
                    phx-target={@myself}
                    title="Open referenced row"
                  >
                    {render_cell(cell, @col_meta[col], @bytea_display)}
                  </button>
                  <div :if={!fk_clickable?(@col_meta[col], cell)} class="lt-drawer-field-value">
                    {render_cell(cell, @col_meta[col], @bytea_display)}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </.portal>

      <.portal :if={@sql_pending} id={"#{@dom_id}-confirm-portal"} target="body">
        <div class={["lantern lt-dialog-portal", @class]} data-theme={@theme} style={root_style(@editor_font_size, @style)}>
          <div class="lt-modal" role="alertdialog" aria-modal="true" aria-labelledby={"#{@dom_id}-confirm-title"} aria-describedby={"#{@dom_id}-confirm-desc"}>
            <div class="lt-modal-backdrop" />
            <div class="lt-modal-card">
              <div class="lt-modal-head">
                <h3 id={"#{@dom_id}-confirm-title"} class="lt-modal-title">Confirm destructive SQL</h3>
              </div>
              <div class="lt-modal-body">
                <p id={"#{@dom_id}-confirm-desc"} class="lt-note">This statement permanently modifies or removes data and cannot be undone. Review it carefully before running.</p>
                <pre class="lt-code-preview">{@sql_pending}</pre>
              </div>
              <div class="lt-modal-foot">
                <button type="button" class="lt-btn" phx-click="cancel_sql" phx-target={@myself}>Cancel</button>
                <button type="button" class="lt-btn lt-btn-danger" phx-click="confirm_sql" phx-target={@myself}>Run anyway</button>
              </div>
            </div>
          </div>
        </div>
      </.portal>
    </div>
    """
  end

  defp filter_examples do
    [
      "status = 'active'",
      "age >= 18",
      "name LIKE '%smith%'",
      "role IN ('admin', 'editor')",
      "deleted_at IS NULL",
      "active = true AND age > 21"
    ]
  end

  defp fk_clickable?(%{fk: fk}, value), do: not is_nil(fk) and not is_nil(value)
  defp fk_clickable?(_col_meta, _value), do: false

  @numeric_types ~w(
    int2 int4 int8 integer bigint smallint numeric decimal
    float4 float8 real double precision
  )

  # True when a column's declared type is numeric — used to right-align both the
  # header cell and (via lt-cell-number) its data cells.
  defp numeric_col?(%{type: type}), do: type in @numeric_types
  defp numeric_col?(_), do: false

  defp cell_type_class(nil, _col_meta), do: "lt-cell-null"

  defp cell_type_class(value, col_meta) do
    type = col_meta && col_meta[:type]

    cond do
      type in ["json", "jsonb"] ->
        "lt-cell-json"

      type in ["bool", "boolean"] ->
        "lt-cell-boolean"

      type in [
        "date",
        "time",
        "timestamp",
        "timestamptz",
        "timestamp without time zone",
        "timestamp with time zone"
      ] ->
        "lt-cell-temporal"

      type in [
        "int2",
        "int4",
        "int8",
        "integer",
        "bigint",
        "smallint",
        "numeric",
        "decimal",
        "float4",
        "float8",
        "real",
        "double precision"
      ] ->
        "lt-cell-number"

      value == "" ->
        "lt-cell-empty"

      true ->
        nil
    end
  end

  defp render_cell(value, col_meta, bytea_display) do
    type = col_meta && col_meta[:type]

    display =
      if type == "bytea" and bytea_display == :utf8 and is_binary(value) and String.valid?(value) do
        value
      else
        Coercion.display(value, type)
      end

    cond do
      display == :null ->
        Phoenix.HTML.raw(~s(<span class="lt-null-text">NULL</span>))

      value === true ->
        Phoenix.HTML.raw(~s(<span class="lt-bool-true">true</span>))

      value === false ->
        Phoenix.HTML.raw(~s(<span class="lt-bool-false">false</span>))

      type in ["json", "jsonb"] ->
        Phoenix.HTML.raw(~s(<code class="lt-json-display">#{highlight_json(display)}</code>))

      true ->
        display
    end
  end

  defp highlight_json(value) do
    LiveCode.Languages.JSON.tokenize(to_string(value))
    |> Enum.map_join(fn token ->
      text = token.text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
      ~s(<span class="lc-token lc-token-#{token.kind}">#{text}</span>)
    end)
  end

  defp dom_suffix(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
  end

  # A type-aware editing control. Booleans and enums become dropdowns, dates and
  # timestamps use native pickers, numbers use number inputs, JSON gets a
  # textarea, and everything else falls back to text. Nullable columns get a
  # blank option so a value can be cleared back to SQL NULL.
  attr(:form, :string, required: true)
  attr(:name, :string, required: true)
  attr(:col, :map, default: nil)
  attr(:fk, :list, default: nil)
  attr(:value, :any, default: nil)

  defp field_input(assigns) do
    meta = assigns.col

    kind =
      cond do
        assigns.fk -> :fk
        meta && meta[:enum_values] -> :enum
        meta -> Coercion.input_type(meta.type)
        true -> :text
      end

    assigns = assign(assigns, kind: kind, nullable: meta == nil or meta.nullable)

    ~H"""
    <div class="lt-field">
      <%= case @kind do %>
        <% :fk -> %>
          <select form={@form} name={@name} aria-label={@name} class="lt-input">
            <option :if={@nullable} value="" selected={is_nil(@value)}>∅</option>
            <option
              :for={{val, label} <- @fk}
              value={val}
              selected={Coercion.edit_value(@value) == val}
            >
              {label}
            </option>
          </select>
        <% :boolean -> %>
          <select form={@form} name={@name} aria-label={@name} class="lt-input">
            <option :if={@nullable} value="" selected={is_nil(@value)}>∅</option>
            <option value="true" selected={@value == true}>true</option>
            <option value="false" selected={@value == false}>false</option>
          </select>
        <% :enum -> %>
          <select form={@form} name={@name} aria-label={@name} class="lt-input">
            <option :if={@nullable} value="" selected={is_nil(@value)}>∅</option>
            <option :for={opt <- @col.enum_values} value={opt} selected={to_string(@value) == opt}>
              {opt}
            </option>
          </select>
        <% :json -> %>
          <.editor
            id={"#{dom_suffix(@form)}-#{dom_suffix(@name)}-json"}
            form={@form}
            name={@name}
            aria-label={@name}
            rows={4}
            language={LiveCode.Languages.JSON}
            value={Coercion.edit_value(@value, @col && @col[:type])}
            class="lt-json-editor"
          />
        <% :integer -> %>
          <input
            type="number"
            step="1"
            form={@form}
            name={@name} aria-label={@name}
            value={Coercion.control_value(@value, :integer)}
            class="lt-input"
          />
        <% :decimal -> %>
          <input
            type="number"
            step="any"
            form={@form}
            name={@name} aria-label={@name}
            value={Coercion.control_value(@value, :decimal)}
            class="lt-input"
          />
        <% :date -> %>
          <DatePicker.date_picker
            id={"#{dom_suffix(@form)}-#{dom_suffix(@name)}-date"}
            form={@form}
            name={@name}
            aria-label={@name}
            value={Coercion.control_value(@value, :date)}
            size="sm"
            class="lt-field-picker"
          />
        <% :datetime -> %>
          <DatePicker.date_time_picker
            id={"#{dom_suffix(@form)}-#{dom_suffix(@name)}-datetime"}
            form={@form}
            name={@name}
            aria-label={@name}
            value={Coercion.control_value(@value, :datetime)}
            precision={:millisecond}
            size="sm"
            class="lt-field-picker"
          />
        <% :time -> %>
          <DatePicker.time_picker
            id={"#{dom_suffix(@form)}-#{dom_suffix(@name)}-time"}
            form={@form}
            name={@name}
            aria-label={@name}
            value={Coercion.control_value(@value, :time)}
            precision={:millisecond}
            size="sm"
            class="lt-field-picker"
          />
        <% _ -> %>
          <input
            type="text"
            form={@form}
            name={@name}
            aria-label={@name}
            value={Coercion.edit_value(@value, @col && @col[:type])}
            class="lt-input"
          />
      <% end %>
      <button
        :if={@nullable}
        type="button"
        class="lt-null"
        title="Set NULL"
        aria-label={"Set #{@name} to NULL"}
      >
        ∅
      </button>
    </div>
    """
  end

  # Reusable quick-chart panel: a Bar | Line | Pie segmented control plus the
  # selected rendering, all inline SVG/CSS (no chart library). Shared by the SQL
  # results panel and the data-grid "chart this column" panel. All reads — works
  # under :read_only.
  attr(:points, :list, required: true)
  attr(:kind, :atom, required: true)
  attr(:title, :string, required: true)
  attr(:myself, :any, required: true)
  attr(:on_close, :string, default: nil)
  attr(:close_value, :string, default: nil)
  attr(:label_options, :list, default: [])
  attr(:label_column, :any, default: nil)
  attr(:on_label, :string, default: nil)

  defp chart_render(assigns) do
    ~H"""
    <div class="lt-chart-panel">
      <div class="lt-chart-head">
        <span class="lt-chart-title">{@title}</span>
        <form
          :if={@on_label && @label_options != []}
          phx-change={@on_label}
          phx-target={@myself}
          class="lt-chart-by-form"
        >
          <select name="column" class="lt-input lt-chart-by" aria-label="Label column (x-axis)">
            <option value="">Auto label</option>
            <option :for={c <- @label_options} value={c} selected={@label_column == c}>by {c}</option>
          </select>
        </form>
        <div class="lt-chart-kinds lt-view-tabs" role="tablist" aria-label="Chart type">
          <button
            :for={{value, label} <- [{"bar", "Bar"}, {"line", "Line"}, {"pie", "Pie"}]}
            type="button"
            role="tab"
            aria-selected={to_string(@kind == String.to_existing_atom(value))}
            class={[@kind == String.to_existing_atom(value) && "lt-active"]}
            phx-click="set_chart_kind"
            phx-value-kind={value}
            phx-target={@myself}
          >
            {label}
          </button>
        </div>
        <button
          :if={@on_close}
          type="button"
          class="lt-iconbtn lt-chart-close"
          phx-click={@on_close}
          phx-value-column={@close_value}
          phx-target={@myself}
          title="Close chart"
          aria-label="Close chart"
        >
          <.icon name="hero-x-mark" class="lt-icon lt-icon-sm" />
        </button>
      </div>

      <div :if={@kind == :bar} class="lt-chart-bars">
        <div :for={point <- @points} class="lt-chart-row">
          <span class="lt-chart-label">{point.label}</span>
          <span class="lt-chart-track"><span class="lt-chart-bar" style={"width: #{point.width}%"}></span></span>
          <span class="lt-chart-value">{point.value}</span>
        </div>
      </div>

      <div :if={@kind == :line} class="lt-chart-line">
        <% geo = line_geometry(@points) %>
        <svg
          class="lt-chart-svg"
          viewBox={"0 0 #{geo.width} #{geo.height}"}
          preserveAspectRatio="none"
          role="img"
          aria-label={"#{@title} line chart"}
        >
          <line
            x1="0"
            x2={geo.width}
            y1={geo.baseline}
            y2={geo.baseline}
            class="lt-chart-axis"
          />
          <polyline :if={length(@points) > 1} points={geo.polyline} class="lt-chart-polyline" />
        </svg>
        <div class="lt-chart-xaxis">
          <span :for={d <- geo.dots} class="lt-chart-xlabel" title={d.label}>{d.label}</span>
        </div>
      </div>

      <div :if={@kind == :pie} class="lt-chart-pie">
        <% geo = pie_geometry(@points) %>
        <svg
          class="lt-chart-pie-svg"
          viewBox={"0 0 #{geo.size} #{geo.size}"}
          role="img"
          aria-label={"#{@title} pie chart"}
        >
          <circle
            :if={match?([%{full: true}], geo.slices)}
            cx={geo.size / 2}
            cy={geo.size / 2}
            r={geo.size / 2 - 2}
            fill={hd(geo.slices).color}
          />
          <path
            :for={slice <- geo.slices}
            :if={not slice.full}
            d={slice.d}
            fill={slice.color}
            class="lt-chart-slice"
          >
            <title>{slice.label}: {slice.value} ({slice.percent}%)</title>
          </path>
        </svg>
        <ul class="lt-chart-legend">
          <li :for={slice <- geo.slices} class="lt-chart-legend-item">
            <span class="lt-chart-swatch" style={"background: #{slice.color}"}></span>
            <span class="lt-chart-legend-label" title={slice.label}>{slice.label}</span>
            <span class="lt-chart-legend-value">{slice.value} · {slice.percent}%</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # Self-contained icon component — inlines Heroicons (MIT) so Lantern needs no
  # icon library or CSS plugin in the host application.
  attr(:name, :string, required: true)
  attr(:class, :string, default: nil)

  defp icon(assigns) do
    ~H"""
    <svg
      class={["lt-icon", @class]}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      aria-hidden="true"
    >
      {Phoenix.HTML.raw(icon_path(@name))}
    </svg>
    """
  end

  # The full Heroicons (MIT) OUTLINE set, read at COMPILE time from the heroicons
  # source dep (deps/heroicons) — every `hero-*` name resolves, with no
  # hand-maintained subset to drift out of date. icon/1 wraps its own
  # <svg stroke="currentColor">, so we keep only each icon's inner <path> markup
  # (the SVG body). Add the heroicons build dep (see mix.exs) to change the set.
  @heroicons_glob "deps/heroicons/optimized/24/outline/*.svg"

  @icons (for p <- Path.wildcard(@heroicons_glob), into: %{} do
            inner =
              p
              |> File.read!()
              |> String.replace(~r/<svg[^>]*>/, "")
              |> String.replace("</svg>", "")
              |> String.trim()

            {"hero-" <> Path.basename(p, ".svg"), inner}
          end)

  # Fail the build loudly rather than silently render blank icons if the
  # heroicons source isn't where we expect (e.g. the dep didn't fetch).
  if map_size(@icons) < 100 do
    raise "lantern: heroicons not found at #{@heroicons_glob} " <>
            "(found #{map_size(@icons)}). Is the :heroicons build dep present?"
  end

  defp icon_path(name), do: Map.get(@icons, name, "")
end
