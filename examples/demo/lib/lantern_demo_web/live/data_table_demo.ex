defmodule LanternDemoWeb.DataTableDemo do
  @moduledoc """
  Fully interactive `data_table` reference: an in-memory order list filtered,
  sorted, and paginated by parsing the same URL params Flop uses — so search,
  filter selects, tabs, sort headers, pagination, and the cards toggle all
  work end-to-end without a database (and demonstrate that the component's
  whole state lives in the URL).

  In a real app this module's `handle_params` is replaced by one
  `Flop.validate_and_run/3` call.
  """
  use Phoenix.LiveView

  alias LanternUI.Components.Badge
  alias LanternUI.Components.Button
  alias LanternUI.Components.DataTable
  alias LanternUI.Components.Dropdown
  alias LanternUI.Components.Icon

  @channels ~w(eBay Shopify Direct)
  @statuses ~w(pending shipped refunded)

  @orders (for i <- 1..57 do
             %{
               id: i,
               reference: "##{4800 + i}",
               buyer:
                 Enum.at(~w(Ada Alan Grace Edsger Barbara Donald Radia Ken), rem(i, 8)) <>
                   " " <>
                   Enum.at(
                     ~w(Lovelace Turing Hopper Dijkstra Liskov Knuth Perlman Thompson),
                     rem(i * 3, 8)
                   ),
               channel: Enum.at(@channels, rem(i, 3)),
               status: Enum.at(@statuses, rem(i * 7, 3)),
               total: :erlang.phash2(i, 40_000) / 100 + 5
             }
           end)

  def mount(_params, _session, socket) do
    {:ok, assign(socket, selected: MapSet.new(), page_title: "data_table — lantern-ui")}
  end

  def handle_params(params, _uri, socket) do
    filters = parse_filters(params["filters"])
    order_by = List.first(params["order_by"] || []) || "reference"
    dir = List.first(params["order_directions"] || []) || "asc"
    page_size = parse_int(params["page_size"], 10)
    page = parse_int(params["page"], 1)

    filtered = Enum.filter(@orders, &matches?(&1, filters))
    sorted = sort(filtered, order_by, dir)
    total_pages = max(ceil(length(sorted) / page_size), 1)
    page = min(page, total_pages)
    rows = Enum.slice(sorted, (page - 1) * page_size, page_size)

    meta = %{
      flop: %{page_size: page_size, order_by: [order_by], order_directions: [dir]},
      params: Map.take(params, ~w(filters order_by order_directions page_size view)),
      current_page: page,
      total_pages: total_pages,
      page_size: page_size,
      total_count: length(sorted)
    }

    counts = Enum.frequencies_by(@orders, & &1.status)

    {:noreply,
     assign(socket,
       rows: rows,
       matching_ids: Enum.map(sorted, & &1.id),
       meta: meta,
       counts: counts,
       view: params["view"] || "table",
       revenue: @orders |> Enum.map(& &1.total) |> Enum.sum() |> Float.round(2)
     )}
  end

  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = String.to_integer(id)
    sel = socket.assigns.selected

    {:noreply,
     assign(
       socket,
       :selected,
       if(id in sel, do: MapSet.delete(sel, id), else: MapSet.put(sel, id))
     )}
  end

  def handle_event("select_all_page", _params, socket) do
    page_ids = MapSet.new(socket.assigns.rows, & &1.id)
    sel = socket.assigns.selected

    {:noreply,
     assign(
       socket,
       :selected,
       if(MapSet.subset?(page_ids, sel),
         do: MapSet.difference(sel, page_ids),
         else: MapSet.union(sel, page_ids)
       )
     )}
  end

  def handle_event("select_all_matching", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new(socket.assigns.matching_ids))}
  end

  def handle_event("clear_selection", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("bulk-archive", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "#{MapSet.size(socket.assigns.selected)} orders archived (demo)")
     |> assign(:selected, MapSet.new())}
  end

  def render(assigns) do
    ~H"""
    <LanternDemoWeb.DocsShell.shell current="data-table" theme="system" density="compact">
      <article class="docs-body docs-body-wide">
        <h1>Data table</h1>
        <p>
          The admin table: Flop-driven sort/pagination, built-in debounced search and
          filter selects, tabs with filter presets, a collapsible stat overview, bulk
          selection, and a cards view — with the entire table state living in the URL.
          Everything below is live against an in-memory dataset.
        </p>

        <DataTable.data_table
          id="orders"
          rows={@rows}
          meta={@meta}
          path="/components/data-table"
          selected_ids={@selected}
          search_field={:q}
          search_placeholder="Search buyer or reference…"
          view={@view}
          subtitle="57 in-memory orders — every control patches the URL"
          info_modal_id="orders-info"
        >
          <:stat label="Revenue (all)" value={"$#{@revenue}"} />
          <:stat label="Orders" value={length(@rows)} />
          <:stat label="Pending" value={@counts["pending"]} />
          <:stat label="Refunded" value={@counts["refunded"]} />

          <:tab label="All" count={57} />
          <:tab
            label="Pending"
            count={@counts["pending"]}
            filters={[%{field: "status", value: "pending"}]}
          />
          <:tab
            label="Shipped"
            count={@counts["shipped"]}
            filters={[%{field: "status", value: "shipped"}]}
          />
          <:tab
            label="Refunded"
            count={@counts["refunded"]}
            filters={[%{field: "status", value: "refunded"}]}
          />

          <:filter field={:buyer} type={:text} label="Buyer" placeholder="Any buyer" />
          <:filter field={:channel} label="Channel" multiple searchable options={["eBay", "Shopify", "Direct"]} />
          <:filter
            field={:status}
            label="Status"
            options={[{"Pending", "pending"}, {"Shipped", "shipped"}, {"Refunded", "refunded"}]}
          />
          <:filter field={:total} type={:range} label="Total ($)" />

          <:col :let={o} label="Order" field={:reference} sortable>
            <span style="font-family: var(--lantern-font-mono); font-size: 0.75rem;">
              {o.reference}
            </span>
          </:col>
          <:col :let={o} label="Buyer" field={:buyer} sortable>{o.buyer}</:col>
          <:col :let={o} label="Channel" field={:channel} sortable>{o.channel}</:col>
          <:col :let={o} label="Status" field={:status} sortable>
            <Badge.badge size="sm" color={status_color(o.status)}>{o.status}</Badge.badge>
          </:col>
          <:col :let={o} label="Total" field={:total} sortable td_class="lui-td-num">
            ${:erlang.float_to_binary(o.total, decimals: 2)}
          </:col>

          <:bulk_action label="Archive" icon="arrow-down-tray" event="bulk-archive" />

          <:row_action :let={o}>
            <Dropdown.dropdown id={"row-#{o.id}"} placement="bottom-end">
              <:toggle>
                <Button.button size="icon" variant="ghost" aria-label="Actions">
                  <Icon.icon name="ellipsis-horizontal" />
                </Button.button>
              </:toggle>
              <Dropdown.dropdown_button>View {o.reference}</Dropdown.dropdown_button>
              <Dropdown.dropdown_button data-danger>Refund</Dropdown.dropdown_button>
            </Dropdown.dropdown>
          </:row_action>

          <:card :let={o}>
            <div style="display:flex; justify-content:space-between; margin-bottom:.4rem;">
              <strong style="font-family: var(--lantern-font-mono); font-size:.75rem;">
                {o.reference}
              </strong>
              <Badge.badge size="sm" color={status_color(o.status)}>{o.status}</Badge.badge>
            </div>
            <div style="font-size:.8125rem;">{o.buyer}</div>
            <div style="font-size:.75rem; color: var(--lantern-fg-muted); margin-top:.2rem;">
              {o.channel} · ${:erlang.float_to_binary(o.total, decimals: 2)}
            </div>
          </:card>

          <:empty>No orders match — clear the search or filters above.</:empty>
        </DataTable.data_table>

        <LanternUI.Components.Modal.modal id="orders-info">
          <h3 style="margin:0 0 .4rem; font-size:1rem;">About this table</h3>
          <p style="margin:0; font-size:.85rem; color: var(--lantern-fg-muted);">
            Demo dataset. In a real app, rows/meta come from one
            <code>Flop.validate_and_run/3</code> call; this page hand-parses the same
            URL params to stay database-free.
          </p>
        </LanternUI.Components.Modal.modal>

        <pre class="docs-code" style="margin-top:1.25rem;"><code>{snippet()}</code></pre>
      </article>
    </LanternDemoWeb.DocsShell.shell>
    """
  end

  defp status_color("shipped"), do: "success"
  defp status_color("pending"), do: "warning"
  defp status_color("refunded"), do: "danger"

  # ── In-memory "Flop" — a real app replaces all of this with Flop.validate_and_run ──

  defp parse_filters(nil), do: []

  defp parse_filters(filters) when is_map(filters) do
    filters
    |> Map.values()
    |> Enum.map(fn f -> %{field: f["field"], op: f["op"], value: f["value"]} end)
    |> Enum.reject(&(&1.value in [nil, ""]))
  end

  defp matches?(order, filters) do
    Enum.all?(filters, fn
      %{field: "q", value: q} ->
        q = String.downcase(q)

        String.contains?(String.downcase(order.buyer), q) or
          String.contains?(String.downcase(order.reference), q)

      %{field: "buyer", value: v} ->
        String.contains?(String.downcase(order.buyer), String.downcase(v))

      %{field: "total", op: ">=", value: v} ->
        case Float.parse(to_string(v)) do
          {min, _} -> order.total >= min
          _ -> true
        end

      %{field: "total", op: "<=", value: v} ->
        case Float.parse(to_string(v)) do
          {max, _} -> order.total <= max
          _ -> true
        end

      %{field: "channel", op: "in", value: vs} ->
        order.channel in List.wrap(vs)

      %{field: "channel", value: v} ->
        order.channel == v

      %{field: "status", value: v} ->
        order.status == v

      _ ->
        true
    end)
  end

  defp sort(orders, field, dir) do
    key =
      case field do
        "buyer" -> & &1.buyer
        "total" -> & &1.total
        "channel" -> & &1.channel
        "status" -> & &1.status
        _ -> & &1.reference
      end

    Enum.sort_by(orders, key, if(dir == "desc", do: :desc, else: :asc))
  end

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) do
    case Integer.parse(to_string(value)) do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp snippet do
    ~S"""
    <.data_table id="orders" rows={@orders} meta={@meta} path={~p"/orders"}
      selected_ids={@selected} search_field={:q}>
      <:stat label="Revenue (30d)" value={@revenue} />
      <:tab label="Pending" count={@counts.pending}
            filters={[%{field: "status", value: "pending"}]} />
      <:filter field={:channel} options={@channels} />
      <:col :let={o} label="Order" field={:reference} sortable>{o.reference}</:col>
      <:bulk_action label="Archive" icon="archive-box" event="bulk-archive" />
      <:row_action :let={o}>…</:row_action>
      <:card :let={o}>…</:card>
    </.data_table>
    """
  end
end
