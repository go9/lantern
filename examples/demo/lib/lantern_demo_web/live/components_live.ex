defmodule LanternDemoWeb.ComponentsLive do
  @moduledoc """
  The lantern-ui components reference — every component rendered live with its
  HEEx source, themed by the real tokens, with light/dark + density toggles.
  Dogfoods lantern-ui: the page chrome itself is built from the components.
  """
  use Phoenix.LiveView

  alias LanternUI.Charts
  alias LanternUI.Components.Button
  alias LanternUI.Components.Calendar
  alias LanternUI.Components.DatePicker
  alias LanternUI.Components.DatetimeField
  alias LanternUI.Components.Form
  alias LanternUI.Components.Icon

  @snippets %{
    button: ~S"""
    <.button variant="solid" color="primary">Save</.button>
    <.button size="icon" aria-label="Add"><.icon name="plus" /></.button>
    <.button_group>
      <.button>Years</.button> <.button>Months</.button>
    </.button_group>
    """,
    icon: ~S"""
    <.icon name="calendar-days" />
    """,
    input: ~S"""
    <.input field={@form[:email]} label="Email" help_text="We never share it." />
    """,
    datetime_field: ~S"""
    <.datetime_field id="f" name="at" mode={:datetime} precision={:millisecond} value="2026-07-08T14:30:00.000" />
    """,
    calendar: ~S"""
    <.calendar id="cal" selected={@date} week_start={1} min="2026-01-01" />
    """,
    pickers: ~S"""
    <.date_picker field={@form[:due]} label="Due date" />
    <.date_time_picker field={@form[:starts_at]} precision={:millisecond} />
    <.time_picker name="alarm" value="08:45:00.000" />
    """,
    charts: ~S"""
    <.area_chart id="rev" series={@daily_revenue} value_format={:currency} />
    <.line_chart id="cpu" series={[%{label: "web-1", color: "var(--lantern-accent)", points: @points}]} />
    <.bar_chart id="q" series={[%{label: "Q1", value: 42}]} />
    <.sparkline id="s" series={[3, 5, 4, 8]} />
    """
  }

  @sections [
    {"button", "Button"},
    {"icon", "Icon"},
    {"input", "Input"},
    {"datetime-field", "Datetime field"},
    {"calendar", "Calendar"},
    {"pickers", "Date & time pickers"},
    {"charts", "Charts"}
  ]

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
       page_title: "Components — lantern-ui",
       sections: @sections,
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
    <div
      class={["cmp-page", @theme == "dark" && "dark"]}
      data-lantern-density={@density}
    >
      <header class="cmp-header">
        <div>
          <a href="/" class="cmp-back">← lantern demo</a>
          <h1 class="cmp-title">lantern-ui components</h1>
          <p class="cmp-sub">
            Native LiveView components — server-rendered, one JS hook bundle, themed by
            <code>--lantern-*</code> tokens.
            <a href="https://hex.pm/packages/lantern_ui">hex.pm/packages/lantern_ui</a>
          </p>
        </div>
        <div class="cmp-toggles">
          <Button.button variant="outline" size="sm" phx-click="theme">
            <Icon.icon name={if @theme == "dark", do: "check", else: "minus"} /> Dark
          </Button.button>
          <Button.button variant="outline" size="sm" phx-click="density">
            {String.capitalize(@density)}
          </Button.button>
        </div>
      </header>

      <nav class="cmp-nav">
        <a :for={{id, label} <- @sections} href={"##{id}"}>{label}</a>
      </nav>

      <section id="button" class="cmp-section">
        <h2>Button</h2>
        <p>Variants × colors, sizes, and icon buttons. Defaults: <code>variant="outline" color="primary" size="md"</code>.</p>

        <div class="cmp-demo">
          <div class="cmp-row">
            <Button.button :for={v <- ~w(solid soft surface outline dashed ghost)} variant={v}>
              {v}
            </Button.button>
          </div>
          <div class="cmp-row">
            <Button.button :for={c <- ~w(primary danger warning success info)} variant="solid" color={c}>
              {c}
            </Button.button>
          </div>
          <div class="cmp-row">
            <Button.button :for={s <- ~w(xs sm md lg xl)} size={s}>{s}</Button.button>
            <Button.button size="icon" aria-label="Add"><Icon.icon name="plus" /></Button.button>
            <Button.button variant="solid" disabled>disabled</Button.button>
          </div>
          <div class="cmp-row">
            <Button.button_group>
              <Button.button>Years</Button.button>
              <Button.button>Months</Button.button>
              <Button.button>Days</Button.button>
            </Button.button_group>
          </div>
        </div>
        <pre class="cmp-code"><code>{@snippets.button}</code></pre>
      </section>

      <section id="icon" class="cmp-section">
        <h2>Icon</h2>
        <p>Inline heroicons (outline), sized by font-size.</p>
        <div class="cmp-demo">
          <div class="cmp-row cmp-icons">
            <span :for={n <- ~w(plus minus check x-mark chevron-down chevron-up chevron-left chevron-right arrow-right calendar-days clock magnifying-glass ellipsis-horizontal exclamation-circle)} class="cmp-icon-cell">
              <Icon.icon name={n} />
              <code>{n}</code>
            </span>
          </div>
        </div>
        <pre class="cmp-code"><code>{@snippets.icon}</code></pre>
      </section>

      <section id="input" class="cmp-section">
        <h2>Input</h2>
        <p>Text field with label, sublabel, help text, and error states. Accepts a <code>Phoenix.HTML.FormField</code>.</p>
        <div class="cmp-demo">
          <div class="cmp-grid2">
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
            <Form.input id="in-3" name="handle" label="Handle" value="not valid!" errors={["must not contain spaces"]} />
            <Form.input id="in-4" name="ro" label="Disabled" value="read only" disabled />
          </div>
        </div>
        <pre class="cmp-code"><code>{@snippets.input}</code></pre>
      </section>

      <section id="datetime-field" class="cmp-section">
        <h2>Datetime field</h2>
        <p>
          Segmented, keyboard-first entry: type straight into a segment, <kbd>↑</kbd><kbd>↓</kbd> to step,
          <kbd>←</kbd><kbd>→</kbd> to move. Backs a hidden input with the canonical value.
        </p>
        <div class="cmp-demo">
          <div class="cmp-row">
            <DatetimeField.datetime_field id="dtf-date" name="dtf1" mode={:date} value="2026-07-08" />
            <DatetimeField.datetime_field id="dtf-time" name="dtf2" mode={:time} precision={:millisecond} value="14:30:00.000" />
          </div>
        </div>
        <pre class="cmp-code"><code>{@snippets.datetime_field}</code></pre>
      </section>

      <section id="calendar" class="cmp-section">
        <h2>Calendar</h2>
        <p>APG-grid month calendar: arrow keys move by day/week, <kbd>PgUp</kbd>/<kbd>PgDn</kbd> by month, <kbd>t</kbd> jumps to today.</p>
        <div class="cmp-demo">
          <div class="cmp-cal-box">
            <Calendar.calendar id="cal-demo" selected={Date.utc_today()} />
          </div>
        </div>
        <pre class="cmp-code"><code>{@snippets.calendar}</code></pre>
      </section>

      <section id="pickers" class="cmp-section">
        <h2>Date &amp; time pickers</h2>
        <p>
          Fluxon-compatible API. Segmented trigger + calendar popover with a time pane
          (<code>date_time_picker</code>). <code>time_picker</code> is segments-only — a lantern-ui extension.
        </p>
        <div class="cmp-demo">
          <div class="cmp-grid2">
            <DatePicker.date_picker id="pk-date" name="due" label="Due date" value="2026-07-08" />
            <DatePicker.date_time_picker
              id="pk-dt"
              name="starts_at"
              label="Starts at"
              precision={:millisecond}
              value="2026-07-08T09:15:00.000"
            />
            <DatePicker.time_picker id="pk-time" name="alarm" label="Alarm" value="08:45:00.000" />
            <DatePicker.date_picker id="pk-err" name="bad" label="With error" value={nil} errors={["can't be blank"]} />
          </div>
        </div>
        <pre class="cmp-code"><code>{@snippets.pickers}</code></pre>
      </section>

      <section id="charts" class="cmp-section">
        <h2>Charts</h2>
        <p>Server-rendered SVG — geometry computed in Elixir, one hover hook, no chart library.</p>
        <div class="cmp-demo">
          <div class="cmp-grid2">
            <div class="cmp-chart-card">
              <h3>area_chart</h3>
              <Charts.area_chart id="ch-area" series={@area} height={180} value_format={:currency} />
            </div>
            <div class="cmp-chart-card">
              <h3>line_chart</h3>
              <Charts.line_chart id="ch-line" series={@line} height={180} />
            </div>
            <div class="cmp-chart-card">
              <h3>bar_chart</h3>
              <Charts.bar_chart id="ch-bar" series={@bars} height={160} />
            </div>
            <div class="cmp-chart-card">
              <h3>sparkline</h3>
              <Charts.sparkline id="ch-spark" series={@spark} height={48} />
            </div>
          </div>
        </div>
        <pre class="cmp-code"><code>{@snippets.charts}</code></pre>
      </section>

      <style>
        .cmp-page { max-width: 980px; margin: 0 auto; padding: 2.5rem 1.5rem 5rem;
          font-family: var(--lantern-font); background: var(--lantern-surface);
          color: var(--lantern-fg); transition: background .15s, color .15s; }
        .cmp-header { display: flex; justify-content: space-between; align-items: flex-start; gap: 1rem; }
        .cmp-back { font-size: .8125rem; color: var(--lantern-fg-muted); text-decoration: none; }
        .cmp-back:hover { color: var(--lantern-accent); }
        .cmp-title { font-size: 1.75rem; font-weight: 700; letter-spacing: -.02em; margin: .4rem 0 .3rem; }
        .cmp-sub { font-size: .875rem; color: var(--lantern-fg-muted); margin: 0; max-width: 34rem; }
        .cmp-sub a { color: var(--lantern-accent); }
        .cmp-sub code { font-family: var(--lantern-font-mono); font-size: .8em; }
        .cmp-toggles { display: flex; gap: .5rem; flex-shrink: 0; }
        .cmp-nav { display: flex; flex-wrap: wrap; gap: .25rem 1rem; margin: 1.5rem 0 0;
          padding: .75rem 0; border-bottom: 1px solid var(--lantern-border); }
        .cmp-nav a { font-size: .8125rem; color: var(--lantern-fg-muted); text-decoration: none; }
        .cmp-nav a:hover { color: var(--lantern-accent); }
        .cmp-section { margin-top: 3rem; }
        .cmp-section h2 { font-size: 1.125rem; font-weight: 650; letter-spacing: -.01em; margin: 0 0 .3rem; }
        .cmp-section > p { font-size: .875rem; color: var(--lantern-fg-muted); margin: 0 0 1rem; max-width: 44rem; }
        .cmp-section p code, .cmp-section kbd { font-family: var(--lantern-font-mono); font-size: .8em;
          background: var(--lantern-surface-sunken); border: 1px solid var(--lantern-border);
          border-radius: 4px; padding: 0 .3em; }
        .cmp-demo { border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-lg);
          padding: 1.25rem; background: var(--lantern-surface-raised); display: flex;
          flex-direction: column; gap: .875rem; }
        .cmp-row { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
        .cmp-grid2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; }
        .cmp-icons { gap: .875rem; }
        .cmp-icon-cell { display: inline-flex; flex-direction: column; align-items: center; gap: .3rem;
          font-size: 1.1rem; color: var(--lantern-fg); }
        .cmp-icon-cell code { font-size: .625rem; color: var(--lantern-fg-subtle); }
        .cmp-cal-box { max-width: 320px; }
        .cmp-chart-card h3 { font-size: .75rem; font-weight: 600; color: var(--lantern-fg-muted);
          font-family: var(--lantern-font-mono); margin: 0 0 .5rem; }
        .cmp-code { margin: .625rem 0 0; padding: .875rem 1rem; border-radius: var(--lantern-radius-md);
          background: var(--lantern-surface-sunken); border: 1px solid var(--lantern-border);
          overflow-x: auto; }
        .cmp-code code { font-family: var(--lantern-font-mono); font-size: .75rem; line-height: 1.6;
          color: var(--lantern-fg); }
        .cmp-footer { margin-top: 4rem; padding-top: 1rem; border-top: 1px solid var(--lantern-border);
          font-size: .8125rem; color: var(--lantern-fg-muted); }
        .cmp-footer a { color: var(--lantern-accent); text-decoration: none; }
        .cmp-soon { color: var(--lantern-fg-subtle); }
      </style>

      <footer class="cmp-footer">
        <a href="https://github.com/go9/lantern-ui">GitHub</a> ·
        <a href="https://lantern-ui.hexdocs.pm">Docs</a> ·
        <a href="/">DB viewer demo</a> ·
        <span class="cmp-soon">S3 viewer — coming soon</span>
      </footer>
    </div>
    """
  end
end
