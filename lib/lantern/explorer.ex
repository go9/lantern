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
    * `:allow_raw_filter` — when `true`, exposes a raw SQL filter input that
      is appended after `WHERE`. Default `false`. **Enable only for trusted
      operators**: a user-supplied fragment can execute arbitrary SQL (data-
      modifying CTEs, sub-selects, etc.) under the connection role's
      privileges. Lantern explicitly never sees the filter as
      parameterizable input — it's a literal SQL fragment.

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

  @page_size 50

  @impl true
  def update(assigns, socket) do
    source_changed? =
      socket.assigns[:loaded] == true and socket.assigns[:source] != assigns.source

    socket =
      socket
      |> assign(:source, assigns.source)
      |> assign(:allow_raw_filter, Map.get(assigns, :allow_raw_filter, false))
      |> assign(:title, Map.get(assigns, :title, "Data"))
      |> assign(:dom_id, Map.get(assigns, :id, "lantern"))

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
    {tables, error} =
      case Lantern.list_tables(socket.assigns.source) do
        {:ok, tables} -> {tables, nil}
        {:error, reason} -> {[], reason}
      end

    # Default to the first table so the grid is populated on load.
    selected = List.first(tables)

    socket =
      socket
      |> assign(:loaded, true)
      |> assign(:tables, tables)
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
      |> assign(:sidebar_open, true)
      |> assign(:fullscreen, false)
      |> assign(:dialog, nil)
      |> assign(:new_table_name, "")
      |> assign(:new_columns, [])
      |> assign(:error, error)

    if selected, do: socket |> load_schema() |> load_rows(), else: socket
  end

  # ---------------------------------------------------------------------------
  # Events — navigation
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("select_table", %{"table" => ""}, socket) do
    {:noreply, assign(socket, selected_table: nil, rows: [], count: 0, result_columns: [])}
  end

  def handle_event("select_table", %{"table" => table}, socket) do
    socket =
      socket
      |> assign(:selected_table, table)
      |> assign(:sort_by, nil)
      |> assign(:sort_dir, :asc)
      |> assign(:where_clause, "")
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

  def handle_event("filter", %{"where_clause" => clause}, socket) do
    {:noreply, socket |> assign(where_clause: clause, page: 0) |> load_rows()}
  end

  def handle_event("apply_filter", %{"q" => clause}, socket) do
    {:noreply, socket |> assign(where_clause: clause, page: 0) |> load_rows()}
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
    index = String.to_integer(index)

    selected =
      if MapSet.member?(socket.assigns.selected, index) do
        MapSet.delete(socket.assigns.selected, index)
      else
        MapSet.put(socket.assigns.selected, index)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  def handle_event("toggle_all", _params, socket) do
    all = 0..(length(socket.assigns.rows) - 1)//1 |> MapSet.new()

    selected =
      if MapSet.size(socket.assigns.selected) == length(socket.assigns.rows),
        do: MapSet.new(),
        else: all

    {:noreply, assign(socket, :selected, selected)}
  end

  # ---------------------------------------------------------------------------
  # Events — editing
  # ---------------------------------------------------------------------------

  def handle_event("edit_row", %{"index" => index}, socket) do
    {:noreply, assign(socket, editing: String.to_integer(index), inserting: false)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("save_row", params, socket) do
    index = String.to_integer(params["_index"])
    row = Enum.at(socket.assigns.rows, index)
    cols = socket.assigns.result_columns
    pks = socket.assigns.primary_keys
    col_meta = socket.assigns.col_meta

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
        key = pk_key(row, cols, pks, col_meta)

        case Lantern.update(socket.assigns.source, socket.assigns.selected_table, changes, key) do
          {:ok, _updated} ->
            {:noreply, socket |> assign(:editing, nil) |> load_rows() |> clear_error()}

          {:error, reason} ->
            {:noreply, assign(socket, :error, humanize(reason))}
        end
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

    case Lantern.insert(socket.assigns.source, socket.assigns.selected_table, values) do
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

    case Lantern.delete(socket.assigns.source, socket.assigns.selected_table, keys) do
      {:ok, _n} ->
        {:noreply, socket |> assign(:selected, MapSet.new()) |> load_rows() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
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
    columns = List.delete_at(socket.assigns.new_columns, String.to_integer(index))
    columns = if columns == [], do: [empty_column(:first)], else: columns
    {:noreply, assign(socket, :new_columns, columns)}
  end

  def handle_event("create_table", params, socket) do
    name = Map.get(params, "table", "")
    columns = parse_columns(params)

    case Lantern.create_table(socket.assigns.source, name, columns) do
      :ok ->
        {:noreply, reload_tables(socket, name)}

      {:error, reason} ->
        {:noreply,
         assign(socket, new_table_name: name, new_columns: columns, error: humanize(reason))}
    end
  end

  def handle_event("open_columns", _params, socket) do
    {:noreply, assign(socket, dialog: :columns, editing: nil, inserting: false) |> clear_error()}
  end

  def handle_event("add_column", params, socket) do
    column = %{
      name: Map.get(params, "name", ""),
      type: Map.get(params, "type", "text"),
      nullable: Map.get(params, "nullable", "true") == "true"
    }

    case Lantern.add_column(socket.assigns.source, socket.assigns.selected_table, column) do
      :ok ->
        # Keep the dialog open so several columns can be managed in one sitting.
        {:noreply, socket |> load_schema() |> load_rows() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("rename_column", %{"from" => from, "name" => to}, socket) do
    case Lantern.rename_column(socket.assigns.source, socket.assigns.selected_table, from, to) do
      :ok ->
        {:noreply, socket |> load_schema() |> load_rows() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("drop_column", %{"column" => column}, socket) do
    case Lantern.drop_column(socket.assigns.source, socket.assigns.selected_table, column) do
      :ok ->
        {:noreply, socket |> load_schema() |> load_rows() |> clear_error()}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("open_rename_table", _params, socket) do
    {:noreply,
     assign(socket, dialog: :rename_table, editing: nil, inserting: false) |> clear_error()}
  end

  def handle_event("rename_table", %{"name" => new_name}, socket) do
    case Lantern.rename_table(socket.assigns.source, socket.assigns.selected_table, new_name) do
      :ok ->
        {:noreply, reload_tables(socket, new_name)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, humanize(reason))}
    end
  end

  def handle_event("drop_table", _params, socket) do
    case Lantern.drop_table(socket.assigns.source, socket.assigns.selected_table) do
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

  defp load_schema(socket) do
    table = socket.assigns.selected_table
    source = socket.assigns.source

    case Lantern.schema(source, table) do
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

  defp load_rows(%{assigns: %{selected_table: nil}} = socket), do: socket

  defp load_rows(socket) do
    a = socket.assigns

    opts = [
      where_clause: a.where_clause,
      sort_by: a.sort_by,
      sort_dir: a.sort_dir,
      limit: @page_size,
      offset: a.page * @page_size
    ]

    case Lantern.query(a.source, a.selected_table, opts) do
      {:ok, %{columns: cols, rows: rows, count: count}} ->
        # Drop any in-flight edit/insert and selection: row indexes don't
        # survive a sort, page change, or refresh, so reusing them would
        # silently apply edits to the wrong row.
        socket
        |> assign(result_columns: cols, rows: rows, count: count)
        |> assign(:selected, MapSet.new())
        |> assign(:editing, nil)
        |> assign(:inserting, false)
        |> clear_error()

      {:error, reason} ->
        assign(socket, error: humanize(reason), rows: [], count: 0)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp toggle(:asc), do: :desc
  defp toggle(:desc), do: :asc

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp clear_error(socket), do: assign(socket, :error, nil)

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

  defp total_pages(count) when count <= 0, do: 1
  defp total_pages(count), do: div(count - 1, @page_size) + 1

  defp humanize(reason) when is_binary(reason), do: reason
  defp humanize(:no_primary_key), do: "This table has no primary key, so rows cannot be edited."
  defp humanize(:key_mismatch), do: "Could not match the row's primary key."
  defp humanize(:no_fields), do: "Nothing to save."
  defp humanize(:no_key), do: "Cannot identify the row to update."
  defp humanize(:no_rows), do: "No rows selected."
  defp humanize(reason), do: inspect(reason)

  # The first column of a brand-new table defaults to an auto-incrementing
  # primary key; subsequent rows start as plain nullable text.
  defp empty_column(:first),
    do: %{name: "id", type: "bigserial", nullable: false, primary_key: true}

  defp empty_column(:more), do: %{name: "", type: "text", nullable: true, primary_key: false}

  # Parses the nested `col[i][...]` params of the create-table form back into an
  # ordered list of column specs.
  defp parse_columns(%{"col" => cols}) when is_map(cols) do
    cols
    |> Enum.sort_by(fn {idx, _} -> String.to_integer(idx) end)
    |> Enum.map(fn {_idx, attrs} ->
      %{
        name: Map.get(attrs, "name", ""),
        type: Map.get(attrs, "type", "text"),
        nullable: Map.get(attrs, "nullable", "true") == "true",
        primary_key: Map.get(attrs, "primary_key", "false") == "true"
      }
    end)
  end

  defp parse_columns(_), do: []

  # Curated type menu — every value passes Lantern.SQL.validate_type/1, so the
  # picker can't produce a rejected type. Listed explicitly (not ~w) so the
  # multi-word "double precision" stays a single option.
  defp type_options do
    [
      "text",
      "varchar",
      "integer",
      "bigint",
      "smallint",
      "serial",
      "bigserial",
      "numeric",
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
    case Lantern.list_tables(socket.assigns.source) do
      {:ok, tables} ->
        selected = if prefer && prefer in tables, do: prefer, else: List.first(tables)

        socket =
          socket
          |> assign(
            tables: tables,
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

  defp dialog_title(:create_table), do: "New table"
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
        # inline edit or delete.
        editable: assigns.primary_keys != [],
        insertable: assigns.result_columns != [],
        page_size: @page_size,
        pages: total_pages(assigns.count)
      )

    ~H"""
    <div
      class={["lantern", @fullscreen && "lt-fullscreen"]}
      phx-window-keydown={@fullscreen && "exit_fullscreen"}
      phx-key="Escape"
      phx-target={@myself}
    >
      <div class="lt-header">
        <div class="lt-title">
          <.icon name="hero-table-cells" class="lt-icon lt-icon-lg" />
          <h2 class="lt-title-text">{@title}</h2>
        </div>
        <div class="lt-header-actions">
          <button
            type="button"
            class="lt-iconbtn"
            phx-click="toggle_sidebar"
            phx-target={@myself}
            title="Toggle tables"
            aria-label="Toggle tables sidebar"
          >
            <.icon name="hero-bars-3" class="lt-icon" />
          </button>
          <button
            type="button"
            class={if @fullscreen, do: "lt-btn", else: "lt-iconbtn"}
            phx-click="toggle_fullscreen"
            phx-target={@myself}
            title={if @fullscreen, do: "Exit fullscreen (Esc)", else: "Fullscreen"}
            aria-label={if @fullscreen, do: "Exit fullscreen", else: "Enter fullscreen"}
          >
            <.icon
              name={if @fullscreen, do: "hero-arrows-pointing-in", else: "hero-arrows-pointing-out"}
              class="lt-icon"
            />
            <span :if={@fullscreen}>Exit fullscreen</span>
          </button>
        </div>
      </div>

      <div :if={@error} class="lt-error">{@error}</div>

      <div class="lt-body">
        <aside :if={@sidebar_open} class="lt-sidebar">
          <div class="lt-sidebar-head">
            <span class="lt-sidebar-title">Tables</span>
            <button
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
          <nav class="lt-table-list">
            <button
              :for={t <- @tables}
              type="button"
              class={["lt-table-item", t == @selected_table && "lt-active"]}
              phx-click="select_table"
              phx-value-table={t}
              phx-target={@myself}
            >
              {t}
            </button>
          </nav>
        </aside>

        <div class="lt-content">
          <div :if={is_nil(@selected_table)} class="lt-empty">
            Select a table to browse and edit its rows.
          </div>

          <div :if={@selected_table} class="lt-main">
            <div class="lt-toolbar">
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
                <button
                  :if={MapSet.size(@selected) > 0 and @editable}
                  type="button"
                  class="lt-btn lt-btn-danger"
                  phx-click="delete_selected"
                  phx-target={@myself}
                  data-confirm={"Delete #{MapSet.size(@selected)} row(s)?"}
                >
                  <.icon name="hero-trash" class="lt-icon" /> Delete ({MapSet.size(@selected)})
                </button>
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
                      phx-click="open_columns"
                      phx-target={@myself}
                    >
                      <.icon name="hero-table-cells" class="lt-icon" /> Edit columns
                    </button>
                    <button
                      type="button"
                      class="lt-menu-item"
                      phx-click="open_rename_table"
                      phx-target={@myself}
                    >
                      <.icon name="hero-pencil-square" class="lt-icon" /> Rename table
                    </button>
                    <button
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

            <div :if={not @editable} class="lt-note">
              This table has no primary key — you can add rows, but existing rows can't be edited or deleted.
            </div>

            <div
              id={"#{@dom_id}-grid"}
              phx-hook="LanternGrid"
              data-table={@selected_table}
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
                    <th :for={col <- @result_columns} data-col={col} class="lt-th">
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
                      <span class="lt-resize" data-col={col} />
                    </th>
                    <th :if={@editable or @insertable} class="lt-th-actions"></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@inserting} class="lt-row lt-row-insert">
                    <td :if={@editable} class="lt-check"></td>
                    <td :for={col <- @result_columns} class="lt-td-edit">
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
                      <td :for={{col, cell} <- Enum.zip(@result_columns, row)} class="lt-td-edit">
                        <.field_input
                          :if={col not in @primary_keys}
                          form={"#{@dom_id}-edit-#{index}"}
                          name={col}
                          col={@col_meta[col]}
                          fk={@fk_options[col]}
                          value={cell}
                        />
                        <span :if={col in @primary_keys} class="lt-pk">{render_cell(cell, @col_meta[col])}</span>
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
                        :for={{col, cell} <- Enum.zip(@result_columns, row)}
                        class="lt-td"
                      >
                        {render_cell(cell, @col_meta[col])}
                      </td>
                      <td :if={@editable or @insertable} class="lt-td-actions">
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

            <div class="lt-footer">
              <span>{@count} row(s)</span>
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
                <span>Page {@page + 1} of {@pages}</span>
                <button
                  type="button"
                  class="lt-btn"
                  phx-click="page"
                  phx-value-dir="next"
                  phx-target={@myself}
                  disabled={@page + 1 >= @pages}
                >
                  Next
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div :if={@dialog} class="lt-modal">
        <button
          type="button"
          class="lt-modal-backdrop"
          phx-click="close_dialog"
          phx-target={@myself}
          aria-label="Close dialog"
        />
        <div class="lt-modal-card" role="dialog" aria-modal="true">
          <div class="lt-modal-head">
            <h3 class="lt-modal-title">{dialog_title(@dialog)}</h3>
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
                          <option :for={t <- type_options()} value={t} selected={c.type == t}>
                            {t}
                          </option>
                        </select>
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
                    <span class="lt-col-type">{c.type}</span>
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

  defp render_cell(value, col_meta) do
    type = col_meta && col_meta[:type]

    case Coercion.display(value, type) do
      :null -> Phoenix.HTML.raw(~s(<span class="lt-null-text">NULL</span>))
      string -> string
    end
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
          <textarea
            form={@form}
            name={@name}
            aria-label={@name}
            rows="1"
            class="lt-input lt-json"
          >{Coercion.edit_value(@value, @col && @col[:type])}</textarea>
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
          <input
            type="date"
            form={@form}
            name={@name} aria-label={@name}
            value={Coercion.control_value(@value, :date)}
            class="lt-input"
          />
        <% :datetime -> %>
          <input
            type="datetime-local"
            step="0.001"
            form={@form}
            name={@name}
            aria-label={@name}
            value={Coercion.control_value(@value, :datetime)}
            class="lt-input"
          />
        <% :time -> %>
          <input
            type="time"
            step="0.001"
            form={@form}
            name={@name}
            aria-label={@name}
            value={Coercion.control_value(@value, :time)}
            class="lt-input"
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
        :if={@nullable and @kind not in [:boolean, :enum, :fk]}
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

  defp icon_path("hero-table-cells"),
    do:
      ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M3.375 19.5h17.25M3.375 19.5a1.125 1.125 0 0 1-1.125-1.125V5.625c0-.621.504-1.125 1.125-1.125h17.25c.621 0 1.125.504 1.125 1.125v12.75c0 .621-.504 1.125-1.125 1.125M3.375 19.5h7.5M2.25 9h19.5M2.25 14.25h19.5M11.25 5.25v14.25"/>)

  defp icon_path("hero-trash"),
    do:
      ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"/>)

  defp icon_path("hero-plus"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15"/>)

  defp icon_path("hero-arrow-path"),
    do:
      ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99"/>)

  defp icon_path("hero-chevron-up"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m4.5 15.75 7.5-7.5 7.5 7.5"/>)

  defp icon_path("hero-chevron-down"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5"/>)

  defp icon_path("hero-check"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5"/>)

  defp icon_path("hero-x-mark"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12"/>)

  defp icon_path("hero-bars-3"),
    do:
      ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5"/>)

  defp icon_path("hero-arrows-pointing-out"),
    do:
      ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"/>)

  defp icon_path("hero-arrows-pointing-in"),
    do:
      ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M9 9V4.5M9 9H4.5M9 9 3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5 5.25 5.25"/>)

  defp icon_path("hero-pencil-square"),
    do:
      ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10"/>)

  defp icon_path("hero-ellipsis-vertical"),
    do:
      ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5ZM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5ZM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5Z"/>)

  defp icon_path(_), do: ""
end
