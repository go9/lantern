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
  alias LanternUI.Components.Button
  alias LanternUI.Components.Calendar
  alias LanternUI.Components.DatePicker
  alias LanternUI.Components.DatetimeField
  alias LanternUI.Components.Breadcrumb
  alias LanternUI.Components.Checkbox
  alias LanternUI.Components.Dropdown
  alias LanternUI.Components.EmptyState
  alias LanternUI.Components.Form
  alias LanternUI.Components.Icon
  alias LanternUI.Components.Modal

  @groups LanternDemoWeb.DocsShell.component_groups()

  @labels Map.new(Enum.flat_map(@groups, fn {_g, items} -> items end))
  @default_slug "button"

  @snippets %{
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
        <div class="docs-topbar">
          <div class="docs-crumb">Components <span>/</span> {@label}</div>
          <div class="docs-toggles">
            <Button.button variant="outline" size="sm" phx-click="theme">
              <Icon.icon name={if @theme == "dark", do: "check", else: "minus"} /> Dark
            </Button.button>
            <Button.button variant="outline" size="sm" phx-click="density">
              {String.capitalize(@density)}
            </Button.button>
          </div>
        </div>

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
