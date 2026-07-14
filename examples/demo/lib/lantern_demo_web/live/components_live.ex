defmodule LanternDemoWeb.ComponentsLive do
  @moduledoc """
  The lantern-ui components reference — Fluxon-style docs layout: a fixed
  sidebar with grouped component nav, one component per route
  (`/components/:slug`), each rendered live with its HEEx source. Dogfoods
  lantern-ui: the page chrome itself is built from the components and themed by
  the real tokens, with light/dark + density toggles.
  """
  use Phoenix.LiveView

  alias LanternUI.Charts
  alias LanternUI.Components.Alert
  alias LanternUI.Components.Button
  alias LanternUI.Components.Calendar
  alias LanternUI.Components.DatePicker
  alias LanternUI.Components.DatetimeField
  alias LanternUI.Components.Badge
  alias LanternUI.Components.Breadcrumb
  alias LanternUI.Components.Checkbox
  alias LanternUI.Components.Dropdown
  alias LanternUI.Components.EmptyState
  alias LanternUI.Components.Form
  alias LanternUI.Components.Pagination
  alias LanternUI.Components.Radio
  alias LanternUI.Components.Select
  alias LanternUI.Components.Separator
  alias LanternUI.Components.Switch
  alias LanternUI.Components.Table
  alias LanternUI.Components.Tabs
  alias LanternUI.Components.Textarea
  alias LanternUI.Components.Toast
  alias LanternUI.Components.Tooltip
  alias LanternUI.Components.Icon
  alias LanternUI.Components.Layout
  alias LanternUI.Components.Modal

  @groups LanternDemoWeb.DocsShell.component_groups()

  @labels Map.new(Enum.flat_map(@groups, fn {_g, items} -> items end))
  @default_slug "button"

  @snippets %{
    "app-shell" => ~S"""
    <.app_shell id="app">
      <:brand><.icon name="bolt" /> <span class="lui-brand-name">Acme</span></:brand>
      <:header><.breadcrumb>…</.breadcrumb></:header>
      <:actions><.button variant="outline" size="sm">Account</.button></:actions>

      <:sidebar>
        <.nav_group label="Workspace">
          <.nav_item label="Dashboard" icon="chart-bar" navigate={~p"/"} active />
          <.nav_item label="Buckets" icon="cloud" navigate={~p"/buckets"} />
        </.nav_group>
      </:sidebar>

      <%!-- page content --%>
    </.app_shell>
    """,
    "button" => ~S"""
    <.button variant="solid" color="primary">Save</.button>
    <.button size="icon" aria-label="Add"><.icon name="plus" /></.button>
    <.button_group>
      <.button>Years</.button> <.button>Months</.button>
    </.button_group>
    """,
    "icon" => ~S"""
    <.icon name="calendar-days" />
    """,
    "input" => ~S"""
    <.input field={@form[:email]} label="Email" help_text="We never share it." />
    """,
    "datetime-field" => ~S"""
    <.datetime_field id="f" name="at" mode={:datetime} precision={:millisecond} value="2026-07-08T14:30:00.000" />
    """,
    "calendar" => ~S"""
    <.calendar id="cal" selected={@date} week_start={1} min="2026-01-01" />
    """,
    "date-picker" => ~S"""
    <.date_picker field={@form[:due]} label="Due date" />
    <.date_time_picker field={@form[:starts_at]} precision={:millisecond} />
    <.time_picker name="alarm" value="08:45:00.000" />
    """,
    "area-chart" => ~S"""
    <.area_chart id="rev" series={@daily_revenue} height={220} value_format={:currency} />
    """,
    "line-chart" => ~S"""
    <.line_chart
      id="cpu"
      series={[
        %{label: "web-1", color: "var(--lantern-accent)", points: @web1},
        %{label: "web-2", color: "var(--lantern-fg-subtle)", points: @web2}
      ]}
    />
    """,
    "bar-chart" => ~S"""
    <.bar_chart id="q" series={[%{label: "Q1", value: 42}, %{label: "Q2", value: 31}]} />
    """,
    "badge" => ~S"""
    <.badge color="success">Shipped</.badge>
    <.badge color="danger" variant="solid" size="sm">Failed</.badge>
    """,
    "table" => ~S"""
    <.table>
      <.table_head><:col>Name</:col><:col class="lui-th-num">Total</:col></.table_head>
      <.table_body>
        <.table_row :for={o <- @orders} selected={o.id in @selected}>
          <:cell>{o.name}</:cell><:cell class="lui-td-num">{o.total}</:cell>
        </.table_row>
      </.table_body>
    </.table>
    """,
    "tabs" => ~S"""
    <.tabs_list active_tab={@tab}>
      <:tab name="all" patch={~p"/orders?tab=all"}>All <.badge size="sm">{@count}</.badge></:tab>
      <:tab name="pending" patch={~p"/orders?tab=pending"}>Pending</:tab>
    </.tabs_list>
    """,
    "select" => ~S"""
    <.select field={@form[:channel]} label="Channel" options={["eBay", "Shopify"]} />
    <.select name="tags" label="Multiple" multiple value={["a"]} options={["a", "b", "c"]} />
    <.select name="country" label="Searchable" searchable options={@countries} />
    <.select name="size" native value={25} options={[10, 25, 50]} />
    """,
    "pagination" => ~S"""
    <.pagination meta={@meta} patch_fn={fn p -> ~p"/orders?#{p}" end} />
    """,
    "sparkline" => ~S"""
    <.sparkline id="s" series={[3, 5, 4, 8, 6, 9]} height={48} />
    """,
    "checkbox" => ~S"""
    <.checkbox field={@form[:accept]} label="Accept the terms" />
    <.checkbox name="notify" checked label="Email me" description="At most one per day." />
    """,
    "modal" => ~S"""
    <.button phx-click={LanternUI.open_dialog("confirm")}>Delete…</.button>

    <.modal id="confirm">
      <h2>Delete 3 objects?</h2>
      <p>This cannot be undone.</p>
      <.button phx-click={LanternUI.close_dialog("confirm")}>Cancel</.button>
      <.button variant="solid" color="danger" phx-click="delete">Delete</.button>
    </.modal>
    """,
    "dropdown" => ~S"""
    <.dropdown id="row-actions" placement="bottom-end">
      <:toggle>
        <.button size="icon" aria-label="Actions"><.icon name="ellipsis-horizontal" /></.button>
      </:toggle>
      <.dropdown_header>object.png</.dropdown_header>
      <.dropdown_button phx-click="download">Download</.dropdown_button>
      <.dropdown_separator />
      <.dropdown_button phx-click="delete" data-danger>Delete</.dropdown_button>
    </.dropdown>
    """,
    "breadcrumb" => ~S"""
    <.breadcrumb>
      <:item phx-click="close_bucket">my-bucket</:item>
      <:item phx-click="navigate" phx-value-prefix="photos/">photos</:item>
      <:item current>2026</:item>
    </.breadcrumb>
    """,
    "empty-state" => ~S"""
    <.empty_state icon="folder-open" title="No objects">
      Drop files here to upload them.
      <:action><.button size="sm">Upload</.button></:action>
    </.empty_state>
    """,
    "switch" => ~S"""
    <.switch name="dark" label="Dark mode" />
    <.switch name="notify" checked label="Notifications" description="Push alerts." />
    <.switch name="off" label="Disabled" disabled />
    """,
    "radio" => ~S"""
    <.radio name="plan" value="pro" label="Plan">
      <:radio value="basic" label="Basic" />
      <:radio value="pro" label="Pro" sublabel="Popular" />
      <:radio value="enterprise" label="Enterprise" />
    </.radio>

    <.radio name="tier" variant="cards" label="Tier">
      <:radio value="free" label="Free" description="Hobby projects" />
      <:radio value="team" label="Team" description="Collaboration" />
    </.radio>
    """,
    "textarea" => ~S"""
    <.textarea name="notes" label="Notes" help_text="A short intro." rows={4} />
    <.textarea name="bio" label="Bio" value="too short" errors={["is too short"]} />
    """,
    "alert" => ~S"""
    <.alert color="success" title="Saved">Your changes were stored.</.alert>
    <.alert color="warning" title="Unsaved" hide_close={false}>
      Discard or save before leaving.
    </.alert>
    """,
    "separator" => ~S"""
    <.separator />
    <.separator text="or" />
    <.separator vertical />
    """,
    "tooltip" => ~S"""
    <.tooltip id="tip-1" value="More info" placement="top">
      <.button size="sm">Hover me</.button>
    </.tooltip>

    <.tooltip id="tip-2" placement="bottom" arrow={false}>
      <.button size="sm">No arrow</.button>
      <:content><strong>Bold</strong> tip</:content>
    </.tooltip>
    """,
    "toast" => ~S"""
    <Toast.toast_group id="demo-toasts" />

    <.button phx-click="demo_toast" phx-value-kind="info">Info</.button>
    <.button phx-click="demo_toast" phx-value-kind="success">Success</.button>
    """
  }

  def mount(_params, _session, socket) do
    today = Date.utc_today()

    area =
      for i <- 0..29 do
        %{date: Date.add(today, i - 29), value: 40 + :math.sin(i / 4) * 12 + i * 0.8}
      end

    line = [
      %{
        label: "web-1",
        color: "var(--lantern-accent)",
        points:
          for(
            i <- 0..23,
            do: {DateTime.add(~U[2026-07-07 00:00:00Z], i * 3600), 0.3 + :math.sin(i / 3) * 0.2}
          )
      },
      %{
        label: "web-2",
        color: "var(--lantern-fg-subtle)",
        points:
          for(
            i <- 0..23,
            do: {DateTime.add(~U[2026-07-07 00:00:00Z], i * 3600), 0.5 + :math.cos(i / 4) * 0.15}
          )
      }
    ]

    {:ok,
     assign(socket,
       groups: @groups,
       snippets: @snippets,
       theme: "light",
       demo_tab: "one",
       density: "compact",
       area: area,
       line: line,
       bars: [
         %{label: "Q1", value: 42},
         %{label: "Q2", value: 31},
         %{label: "Q3", value: 55},
         %{label: "Q4", value: 47}
       ],
       spark: [3, 5, 4, 8, 6, 9, 7, 11, 9, 12]
     )}
  end

  def handle_params(params, _uri, socket) do
    slug =
      case Map.fetch(params, "slug") do
        {:ok, s} when is_map_key(@labels, s) -> s
        _ -> @default_slug
      end

    {:noreply,
     assign(socket,
       current: slug,
       label: Map.fetch!(@labels, slug),
       page_title: "#{Map.fetch!(@labels, slug)} — lantern-ui"
     )}
  end

  def handle_event("demo_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :demo_tab, tab)}
  end

  def handle_event("demo_toast", %{"kind" => kind}, socket) do
    {:noreply,
     LanternUI.send_toast(socket, kind, "This is a #{kind} toast", title: String.capitalize(kind))}
  end

  def handle_event("theme", _params, socket) do
    {:noreply,
     assign(socket, theme: if(socket.assigns.theme == "dark", do: "light", else: "dark"))}
  end

  def handle_event("density", _params, socket) do
    {:noreply,
     assign(socket,
       density: if(socket.assigns.density == "compact", do: "comfortable", else: "compact")
     )}
  end

  def render(assigns) do
    ~H"""
    <LanternDemoWeb.DocsShell.shell current={@current} theme={@theme} density={@density}>
        <:actions>
          <Button.button variant="outline" size="sm" phx-click="theme">
            <Icon.icon name={if @theme == "dark", do: "check", else: "minus"} /> Dark
          </Button.button>
          <Button.button variant="outline" size="sm" phx-click="density">
            {String.capitalize(@density)}
          </Button.button>
        </:actions>

        <article :if={@current == "app-shell"} class="docs-body">
          <h1>App shell</h1>
          <p>
            The chrome around this page — the top bar (brand · breadcrumb · actions), the
            fixed collapsible sidebar, and the main column — <strong>is</strong>
            <code>&lt;.app_shell&gt;</code>, built from lantern-ui components. Slots:
            <code>:brand</code> (corner logo), <code>:header</code> (inline
            breadcrumbs/switchers), <code>:actions</code> (top-right), and
            <code>:sidebar</code> (<code>nav_group</code> / <code>nav_item</code>). The
            collapse control at the sidebar foot persists per <code>id</code>.
          </p>
          <div class="docs-demo">
            <div class="docs-navdemo">
              <Layout.nav_group label="Workspace">
                <Layout.nav_item label="Dashboard" icon="chart-bar" href="#" active />
                <Layout.nav_item label="Buckets" icon="cloud" href="#" />
                <Layout.nav_item label="Settings" icon="squares-2x2" href="#" />
              </Layout.nav_group>
            </div>
            <p class="docs-caption">
              Live <code>nav_item</code>s — icon, label, active state. The top bar and the
              persisted collapse come from the surrounding <code>app_shell</code>.
            </p>
          </div>
          <pre class="docs-code"><code>{@snippets["app-shell"]}</code></pre>
        </article>

        <article :if={@current == "button"} class="docs-body">
          <h1>Button</h1>
          <p>
            Variants × colors, sizes, and icon buttons.
            Defaults: <code>variant="outline" color="primary" size="md"</code>.
          </p>
          <div class="docs-demo">
            <div class="docs-row">
              <Button.button :for={v <- ~w(solid soft surface outline dashed ghost)} variant={v}>
                {v}
              </Button.button>
            </div>
            <div class="docs-row">
              <Button.button :for={c <- ~w(primary danger warning success info)} variant="solid" color={c}>
                {c}
              </Button.button>
            </div>
            <div class="docs-row">
              <Button.button :for={s <- ~w(xs sm md lg xl)} size={s}>{s}</Button.button>
              <Button.button size="icon" aria-label="Add"><Icon.icon name="plus" /></Button.button>
              <Button.button variant="solid" disabled>disabled</Button.button>
            </div>
            <div class="docs-row">
              <Button.button_group>
                <Button.button>Years</Button.button>
                <Button.button>Months</Button.button>
                <Button.button>Days</Button.button>
              </Button.button_group>
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["button"]}</code></pre>
        </article>

        <article :if={@current == "icon"} class="docs-body">
          <h1>Icon</h1>
          <p>Inline heroicons (outline), sized by font-size.</p>
          <div class="docs-demo">
            <div class="docs-row docs-icons">
              <span
                :for={
                  n <-
                    ~w(plus minus check x-mark chevron-down chevron-up chevron-left chevron-right arrow-right calendar-days clock magnifying-glass ellipsis-horizontal exclamation-circle)
                }
                class="docs-icon-cell"
              >
                <Icon.icon name={n} />
                <code>{n}</code>
              </span>
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["icon"]}</code></pre>
        </article>

        <article :if={@current == "input"} class="docs-body">
          <h1>Input</h1>
          <p>
            Text field with label, sublabel, help text, and error states.
            Accepts a <code>Phoenix.HTML.FormField</code>.
          </p>
          <div class="docs-demo">
            <div class="docs-grid2">
              <Form.input id="in-1" name="name" label="Name" placeholder="Ada Lovelace" value={nil} />
              <Form.input
                id="in-2"
                name="email"
                label="Email"
                sublabel="Required"
                help_text="We never share it."
                placeholder="you@example.com"
                value={nil}
              />
              <Form.input
                id="in-3"
                name="handle"
                label="Handle"
                value="not valid!"
                errors={["must not contain spaces"]}
              />
              <Form.input id="in-4" name="ro" label="Disabled" value="read only" disabled />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["input"]}</code></pre>
        </article>

        <article :if={@current == "datetime-field"} class="docs-body">
          <h1>Datetime field</h1>
          <p>
            Segmented, keyboard-first entry: type straight into a segment,
            <kbd>↑</kbd><kbd>↓</kbd> to step, <kbd>←</kbd><kbd>→</kbd> to move.
            Backs a hidden input with the canonical value.
          </p>
          <div class="docs-demo">
            <div class="docs-row">
              <DatetimeField.datetime_field id="dtf-date" name="dtf1" mode={:date} value="2026-07-08" />
              <DatetimeField.datetime_field
                id="dtf-time"
                name="dtf2"
                mode={:time}
                precision={:millisecond}
                value="14:30:00.000"
              />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["datetime-field"]}</code></pre>
        </article>

        <article :if={@current == "calendar"} class="docs-body">
          <h1>Calendar</h1>
          <p>
            APG-grid month calendar: arrow keys move by day/week,
            <kbd>PgUp</kbd>/<kbd>PgDn</kbd> by month, <kbd>t</kbd> jumps to today.
          </p>
          <div class="docs-demo">
            <div class="docs-cal-box">
              <Calendar.calendar id="cal-demo" selected={Date.utc_today()} />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["calendar"]}</code></pre>
        </article>

        <article :if={@current == "date-picker"} class="docs-body">
          <h1>Date &amp; time pickers</h1>
          <p>
            Fluxon-compatible API. Segmented trigger + calendar popover with a time pane
            (<code>date_time_picker</code>). <code>time_picker</code>
            is segments-only — a lantern-ui extension.
          </p>
          <div class="docs-demo">
            <div class="docs-grid2">
              <DatePicker.date_picker id="pk-date" name="due" label="Due date" value="2026-07-08" />
              <DatePicker.date_time_picker
                id="pk-dt"
                name="starts_at"
                label="Starts at"
                precision={:millisecond}
                value="2026-07-08T09:15:00.000"
              />
              <DatePicker.time_picker id="pk-time" name="alarm" label="Alarm" value="08:45:00.000" />
              <DatePicker.date_picker
                id="pk-err"
                name="bad"
                label="With error"
                value={nil}
                errors={["can't be blank"]}
              />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["date-picker"]}</code></pre>
        </article>


        <article :if={@current == "checkbox"} class="docs-body">
          <h1>Checkbox</h1>
          <p>
            Fluxon-compatible, <code>FormField</code>-aware. A hidden input submits the
            unchecked value so forms always receive the param.
          </p>
          <div class="docs-demo">
            <div class="docs-row" style="flex-direction: column; align-items: flex-start; gap: .75rem;">
              <Checkbox.checkbox id="ck-1" name="accept" label="Accept the terms" />
              <Checkbox.checkbox
                id="ck-2"
                name="notify"
                checked
                label="Email me about activity"
                description="At most one email per day."
              />
              <Checkbox.checkbox id="ck-3" name="dis" label="Disabled" disabled />
              <Checkbox.checkbox id="ck-4" name="err" label="Required" errors={["must be accepted"]} />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["checkbox"]}</code></pre>
        </article>

        <article :if={@current == "modal"} class="docs-body">
          <h1>Modal</h1>
          <p>
            Dialog on the shared overlay runtime: focus trap, <kbd>Esc</kbd>/outside dismissal,
            token-driven fade. Open from the client with <code>LanternUI.open_dialog/1</code> or
            the server with <code>LanternUI.open_dialog(socket, id)</code>.
          </p>
          <div class="docs-demo">
            <div class="docs-row">
              <Button.button phx-click={LanternUI.open_dialog("demo-modal")}>Open modal</Button.button>
            </div>
            <Modal.modal id="demo-modal">
              <h2 style="margin: 0 0 .4rem; font-size: 1.05rem;">Delete 3 objects?</h2>
              <p style="margin: 0 0 1rem; color: var(--lantern-fg-muted); font-size: .85rem;">
                This action cannot be undone.
              </p>
              <div style="display: flex; gap: .5rem; justify-content: flex-end;">
                <Button.button phx-click={LanternUI.close_dialog("demo-modal")}>Cancel</Button.button>
                <Button.button
                  variant="solid"
                  color="danger"
                  phx-click={LanternUI.close_dialog("demo-modal")}
                >
                  Delete
                </Button.button>
              </div>
            </Modal.modal>
          </div>
          <pre class="docs-code"><code>{@snippets["modal"]}</code></pre>
        </article>

        <article :if={@current == "dropdown"} class="docs-body">
          <h1>Dropdown menu</h1>
          <p>
            Fluxon-compatible family with WAI-ARIA menu semantics — <kbd>↑</kbd><kbd>↓</kbd>
            move through items, <kbd>Esc</kbd> closes, focus returns to the trigger.
          </p>
          <div class="docs-demo">
            <div class="docs-row">
              <Dropdown.dropdown id="dd-demo" label="Actions">
                <Dropdown.dropdown_header>object.png</Dropdown.dropdown_header>
                <Dropdown.dropdown_button>
                  <Icon.icon name="arrow-down-tray" /> Download
                </Dropdown.dropdown_button>
                <Dropdown.dropdown_button>
                  <Icon.icon name="arrow-path" /> Rename
                </Dropdown.dropdown_button>
                <Dropdown.dropdown_separator />
                <Dropdown.dropdown_button data-danger>
                  <Icon.icon name="trash" /> Delete
                </Dropdown.dropdown_button>
              </Dropdown.dropdown>
              <Dropdown.dropdown id="dd-icon" placement="bottom-end">
                <:toggle>
                  <Button.button size="icon" aria-label="More">
                    <Icon.icon name="ellipsis-horizontal" />
                  </Button.button>
                </:toggle>
                <Dropdown.dropdown_button>Duplicate</Dropdown.dropdown_button>
                <Dropdown.dropdown_button>Move…</Dropdown.dropdown_button>
              </Dropdown.dropdown>
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["dropdown"]}</code></pre>
        </article>

        <article :if={@current == "breadcrumb"} class="docs-body">
          <h1>Breadcrumb</h1>
          <p>
            Path navigation for file/tree UIs — a lantern-ui extension. Items render as links,
            event buttons, or the <code>aria-current</code> page.
          </p>
          <div class="docs-demo">
            <Breadcrumb.breadcrumb>
              <:item href="#">my-bucket</:item>
              <:item href="#">photos</:item>
              <:item href="#">2026</:item>
              <:item current>07-vacation</:item>
            </Breadcrumb.breadcrumb>
          </div>
          <pre class="docs-code"><code>{@snippets["breadcrumb"]}</code></pre>
        </article>

        <article :if={@current == "empty-state"} class="docs-body">
          <h1>Empty state</h1>
          <p>Quiet zero states for tables, lists, and panels — a lantern-ui extension.</p>
          <div class="docs-demo">
            <EmptyState.empty_state icon="folder-open" title="No objects">
              Drop files here to upload them, or create a folder to get organized.
              <:action><Button.button size="sm">Upload</Button.button></:action>
              <:action><Button.button size="sm" variant="ghost">New folder</Button.button></:action>
            </EmptyState.empty_state>
          </div>
          <pre class="docs-code"><code>{@snippets["empty-state"]}</code></pre>
        </article>

        <article :if={@current == "area-chart"} class="docs-body">
          <h1>Area chart</h1>
          <p>
            Server-rendered SVG — geometry computed in Elixir, one hover hook, no chart
            library. Catmull-Rom smoothing under a density threshold.
          </p>
          <div class="docs-demo">
            <Charts.area_chart id="ch-area" series={@area} height={220} value_format={:currency} />
          </div>
          <pre class="docs-code"><code>{@snippets["area-chart"]}</code></pre>
        </article>

        <article :if={@current == "line-chart"} class="docs-body">
          <h1>Line chart</h1>
          <p>Multi-series line chart with a shared crosshair + tooltip and a legend.</p>
          <div class="docs-demo">
            <Charts.line_chart id="ch-line" series={@line} height={220} />
          </div>
          <pre class="docs-code"><code>{@snippets["line-chart"]}</code></pre>
        </article>

        <article :if={@current == "bar-chart"} class="docs-body">
          <h1>Bar chart</h1>
          <p>Categorical bars with value labels.</p>
          <div class="docs-demo">
            <Charts.bar_chart id="ch-bar" series={@bars} height={200} />
          </div>
          <pre class="docs-code"><code>{@snippets["bar-chart"]}</code></pre>
        </article>


        <article :if={@current == "badge"} class="docs-body">
          <h1>Badge</h1>
          <p>Status pills — colors × variants × sizes.</p>
          <div class="docs-demo">
            <div class="docs-row">
              <Badge.badge :for={c <- ~w(neutral primary accent success warning danger)} color={c}>
                {c}
              </Badge.badge>
            </div>
            <div class="docs-row">
              <Badge.badge :for={v <- ~w(soft solid outline)} variant={v} color="accent">{v}</Badge.badge>
              <Badge.badge size="sm" color="success">sm</Badge.badge>
              <Badge.badge size="lg" color="danger">lg</Badge.badge>
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["badge"]}</code></pre>
        </article>

        <article :if={@current == "table"} class="docs-body">
          <h1>Table</h1>
          <p>
            The presentational family <code>data_table</code> composes — use it directly
            for simple, non-Flop tables.
          </p>
          <div class="docs-demo">
            <Table.table>
              <Table.table_head>
                <:col>Name</:col>
                <:col>Role</:col>
                <:col class="lui-th-num">Commits</:col>
              </Table.table_head>
              <Table.table_body>
                <Table.table_row>
                  <:cell>Ada Lovelace</:cell>
                  <:cell>Analyst</:cell>
                  <:cell class="lui-td-num">1,842</:cell>
                </Table.table_row>
                <Table.table_row selected>
                  <:cell>Grace Hopper</:cell>
                  <:cell>Rear Admiral</:cell>
                  <:cell class="lui-td-num">2,214</:cell>
                </Table.table_row>
              </Table.table_body>
            </Table.table>
          </div>
          <pre class="docs-code"><code>{@snippets["table"]}</code></pre>
        </article>

        <article :if={@current == "tabs"} class="docs-body">
          <h1>Tabs</h1>
          <p>
            Segmented or underline tab lists with server-driven active state; tabs given
            <code>patch</code> render as links so tab state can live in the URL.
          </p>
          <div class="docs-demo">
            <Tabs.tabs id="demo-tabs">
              <Tabs.tabs_list active_tab={@demo_tab}>
                <:tab name="one" phx-click="demo_tab">First <Badge.badge size="sm">12</Badge.badge></:tab>
                <:tab name="two" phx-click="demo_tab">Second</:tab>
                <:tab name="three" phx-click="demo_tab">Third</:tab>
              </Tabs.tabs_list>
              <Tabs.tabs_panel name="one" active={@demo_tab == "one"}>First panel content.</Tabs.tabs_panel>
              <Tabs.tabs_panel name="two" active={@demo_tab == "two"}>Second panel content.</Tabs.tabs_panel>
              <Tabs.tabs_panel name="three" active={@demo_tab == "three"}>Third panel content.</Tabs.tabs_panel>
            </Tabs.tabs>
            <Tabs.tabs_list active_tab="b" variant="underline" size="sm">
              <:tab name="a">Underline</:tab>
              <:tab name="b">Variant</:tab>
            </Tabs.tabs_list>
          </div>
          <pre class="docs-code"><code>{@snippets["tabs"]}</code></pre>
        </article>

        <article :if={@current == "select"} class="docs-body">
          <h1>Select</h1>
          <p>
            FormField-aware select (Fluxon API): rich listbox with keyboard nav +
            type-ahead over a hidden input, or a <code>native</code> fallback.
          </p>
          <div class="docs-demo">
            <div class="docs-grid2">
              <Select.select
                id="sel-1"
                name="channel"
                label="Channel"
                options={[{"eBay", "ebay"}, {"Shopify", "shopify"}, {"Direct", "direct"}]}
                placeholder="Pick a channel"
              />
              <Select.select
                id="sel-2"
                name="status"
                label="Status"
                value="active"
                options={[{"Active", "active"}, {"Archived", "archived"}]}
              />
              <Select.select id="sel-3" name="size" label="Native" native value={25} options={[10, 25, 50]} />
              <Select.select
                id="sel-4"
                name="bad"
                label="With error"
                options={["a"]}
                errors={["can't be blank"]}
              />
              <Select.select
                id="sel-5"
                name="tags"
                label="Multiple"
                multiple
                value={["elixir", "phoenix"]}
                options={[
                  {"Elixir", "elixir"},
                  {"Phoenix", "phoenix"},
                  {"LiveView", "liveview"},
                  {"Ecto", "ecto"}
                ]}
              />
              <Select.select
                id="sel-6"
                name="country"
                label="Searchable"
                searchable
                placeholder="Pick a country"
                options={[
                  "Argentina", "Australia", "Brazil", "Canada", "Denmark", "Estonia",
                  "France", "Germany", "Iceland", "Japan", "Mexico", "Netherlands",
                  "Norway", "Portugal", "Sweden", "United States"
                ]}
              />
              <Select.select
                id="sel-7"
                name="team"
                label="Multi + search"
                multiple
                searchable
                options={["Ada", "Alan", "Barbara", "Donald", "Edsger", "Grace", "Ken", "Radia"]}
              />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["select"]}</code></pre>
        </article>

        <article :if={@current == "pagination"} class="docs-body">
          <h1>Pagination</h1>
          <p>
            Pager + page-size control, duck-typed to <code>Flop.Meta</code> (no flop
            dependency) — all patch navigation. Fluxon has no equivalent; this replaces
            flop_phoenix's pager.
          </p>
          <div class="docs-demo">
            <Pagination.pagination
              id="pg-demo"
              meta={%{current_page: 5, total_pages: 20, page_size: 25, total_count: 487}}
              patch_fn={fn params -> "/components/pagination?" <> Plug.Conn.Query.encode(params) end}
            />
          </div>
          <pre class="docs-code"><code>{@snippets["pagination"]}</code></pre>
        </article>

        <article :if={@current == "switch"} class="docs-body">
          <h1>Switch</h1>
          <p>
            Toggle switch for binary settings. Sizes <code>sm</code>/<code>md</code>/<code>lg</code>,
            with optional label and description.
          </p>
          <div class="docs-demo">
            <div class="docs-row" style="flex-direction: column; align-items: flex-start; gap: .75rem;">
              <Switch.switch id="sw-1" name="sw_off" label="Unchecked" />
              <Switch.switch id="sw-2" name="sw_on" checked label="Checked" />
              <Switch.switch id="sw-3" name="sw_dis" label="Disabled" disabled />
              <div class="docs-row">
                <Switch.switch id="sw-sm" name="sw_sm" size="sm" label="sm" checked />
                <Switch.switch id="sw-md" name="sw_md" size="md" label="md" checked />
                <Switch.switch id="sw-lg" name="sw_lg" size="lg" label="lg" checked />
              </div>
              <Switch.switch
                id="sw-4"
                name="sw_desc"
                checked
                label="Email notifications"
                description="At most one email per day."
              />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["switch"]}</code></pre>
        </article>

        <article :if={@current == "radio"} class="docs-body">
          <h1>Radio</h1>
          <p>
            Exclusive single selection — <code>list</code> (default) or <code>cards</code> variant.
          </p>
          <div class="docs-demo">
            <div class="docs-grid2">
              <Radio.radio id="rd-list" name="plan" value="pro" label="Plan" variant="list">
                <:radio value="basic" label="Basic" />
                <:radio value="pro" label="Pro" sublabel="Popular" />
                <:radio value="enterprise" label="Enterprise" />
              </Radio.radio>
              <Radio.radio id="rd-cards" name="tier" value="team" label="Tier" variant="cards">
                <:radio value="free" label="Free" description="Hobby projects" />
                <:radio value="team" label="Team" description="Collaboration" />
                <:radio value="scale" label="Scale" description="Growing teams" />
              </Radio.radio>
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["radio"]}</code></pre>
        </article>

        <article :if={@current == "textarea"} class="docs-body">
          <h1>Textarea</h1>
          <p>
            Multi-line text input with the same label, help text, and error chrome as
            <code>input</code>.
          </p>
          <div class="docs-demo">
            <div class="docs-grid2">
              <Textarea.textarea id="ta-1" name="notes" label="Notes" placeholder="Write something…" value={nil} />
              <Textarea.textarea
                id="ta-2"
                name="bio"
                label="Bio"
                help_text="A short intro for your profile."
                value={nil}
              />
              <Textarea.textarea
                id="ta-3"
                name="bad"
                label="With error"
                value="too short"
                errors={["is too short (minimum is 20 characters)"]}
              />
              <Textarea.textarea id="ta-4" name="ro" label="Disabled" value="Read only content" disabled />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["textarea"]}</code></pre>
        </article>

        <article :if={@current == "alert"} class="docs-body">
          <h1>Alert</h1>
          <p>
            Inline status alerts — colors, optional close button, and hideable icon.
          </p>
          <div class="docs-demo">
            <Alert.alert color="neutral" title="Note">A neutral status message.</Alert.alert>
            <Alert.alert color="info" title="Info">Something you should know.</Alert.alert>
            <Alert.alert color="success" title="Saved">Your changes were stored.</Alert.alert>
            <Alert.alert color="warning" title="Careful">Review before continuing.</Alert.alert>
            <Alert.alert color="danger" title="Failed">The request could not be completed.</Alert.alert>
            <Alert.alert id="alert-close" color="warning" title="Unsaved" hide_close={false}>
              Discard or save before leaving.
            </Alert.alert>
            <Alert.alert color="info" title="No icon" hide_icon>
              Icon hidden via <code>hide_icon</code>.
            </Alert.alert>
          </div>
          <pre class="docs-code"><code>{@snippets["alert"]}</code></pre>
        </article>

        <article :if={@current == "separator"} class="docs-body">
          <h1>Separator</h1>
          <p>Visual divider — horizontal, labeled, or vertical.</p>
          <div class="docs-demo">
            <p style="margin: 0; font-size: .875rem; color: var(--lantern-fg-muted);">Above the line</p>
            <Separator.separator />
            <p style="margin: 0; font-size: .875rem; color: var(--lantern-fg-muted);">Below the line</p>
            <Separator.separator text="or" />
            <div class="docs-row" style="align-items: stretch; gap: 1rem;">
              <p style="margin: 0; font-size: .875rem; color: var(--lantern-fg-muted); max-width: 12rem;">
                Left column with a short note about primary content.
              </p>
              <Separator.separator vertical />
              <p style="margin: 0; font-size: .875rem; color: var(--lantern-fg-muted); max-width: 12rem;">
                Right column for secondary detail or actions.
              </p>
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["separator"]}</code></pre>
        </article>

        <article :if={@current == "tooltip"} class="docs-body">
          <h1>Tooltip</h1>
          <p>
            Hover/focus tips with placement and optional arrow. Content can be a string or a
            <code>:content</code> slot.
          </p>
          <div class="docs-demo">
            <div class="docs-row">
              <Tooltip.tooltip id="tip-top" value="Placed on top" placement="top">
                <Button.button size="sm">Top</Button.button>
              </Tooltip.tooltip>
              <Tooltip.tooltip id="tip-bottom" value="Placed on bottom" placement="bottom">
                <Button.button size="sm">Bottom</Button.button>
              </Tooltip.tooltip>
              <Tooltip.tooltip id="tip-content" placement="top">
                <Button.button size="sm">Rich content</Button.button>
                <:content>
                  <strong>Bold</strong> tip with <em>markup</em>
                </:content>
              </Tooltip.tooltip>
              <Tooltip.tooltip id="tip-no-arrow" value="No arrow" placement="bottom" arrow={false}>
                <Button.button size="sm">No arrow</Button.button>
              </Tooltip.tooltip>
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["tooltip"]}</code></pre>
        </article>

        <article :if={@current == "toast"} class="docs-body">
          <h1>Toast</h1>
          <p>
            Stacked notifications via <code>toast_group</code> and
            <code>LanternUI.send_toast/4</code>. Fire one of each kind below.
          </p>
          <div class="docs-demo">
            <Toast.toast_group id="demo-toasts" />
            <div class="docs-row">
              <Button.button phx-click="demo_toast" phx-value-kind="info">Info</Button.button>
              <Button.button phx-click="demo_toast" phx-value-kind="success" color="success">
                Success
              </Button.button>
              <Button.button phx-click="demo_toast" phx-value-kind="warning" color="warning">
                Warning
              </Button.button>
              <Button.button phx-click="demo_toast" phx-value-kind="danger" color="danger">
                Danger
              </Button.button>
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["toast"]}</code></pre>
        </article>

        <article :if={@current == "sparkline"} class="docs-body">
          <h1>Sparkline</h1>
          <p>Tiny inline trend line — no axes, no hooks.</p>
          <div class="docs-demo">
            <div class="docs-spark-box">
              <Charts.sparkline id="ch-spark" series={@spark} height={48} />
            </div>
          </div>
          <pre class="docs-code"><code>{@snippets["sparkline"]}</code></pre>
        </article>
      <style>
        .docs-topbar { display: flex; justify-content: space-between; align-items: center;
          gap: 1rem; padding-bottom: 1rem; border-bottom: 1px solid var(--lantern-border);
          margin-bottom: 2rem; }
        .docs-crumb { font-size: .8125rem; color: var(--lantern-fg-muted); }
        .docs-crumb span { margin: 0 .4rem; opacity: .5; }
        .docs-toggles { display: flex; gap: .5rem; }
        .docs-body { max-width: 760px; }
        .docs-body h1 { font-size: 1.5rem; font-weight: 700; letter-spacing: -.02em; margin: 0 0 .4rem; }
        .docs-body > p { font-size: .875rem; color: var(--lantern-fg-muted); margin: 0 0 1.25rem;
          line-height: 1.6; }
        .docs-body p code, .docs-body kbd { font-family: var(--lantern-font-mono); font-size: .8em;
          background: var(--lantern-surface-sunken); border: 1px solid var(--lantern-border);
          border-radius: 4px; padding: 0 .3em; }
        .docs-demo { border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-lg);
          padding: 1.5rem; background: var(--lantern-surface-raised); display: flex;
          flex-direction: column; gap: .875rem; }
        .docs-navdemo { max-width: 15rem; border: 1px solid var(--lantern-border);
          border-radius: var(--lantern-radius-md); padding: .6rem; background: var(--lantern-surface); }
        .docs-caption { font-size: .8125rem; color: var(--lantern-fg-muted); margin: 0; }
        .docs-row { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
        .docs-grid2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; }
        .docs-icons { gap: .875rem; }
        .docs-icon-cell { display: inline-flex; flex-direction: column; align-items: center;
          gap: .3rem; font-size: 1.1rem; color: var(--lantern-fg); }
        .docs-icon-cell code { font-size: .625rem; color: var(--lantern-fg-subtle); }
        .docs-cal-box { max-width: 320px; }
        .docs-spark-box { max-width: 220px; }
        .docs-code { margin: .75rem 0 0; padding: .875rem 1rem; border-radius: var(--lantern-radius-md);
          background: var(--lantern-surface-sunken); border: 1px solid var(--lantern-border);
          overflow-x: auto; }
        .docs-code code { font-family: var(--lantern-font-mono); font-size: .75rem; line-height: 1.6;
          color: var(--lantern-fg); }
      </style>
    </LanternDemoWeb.DocsShell.shell>
    """
  end
end
