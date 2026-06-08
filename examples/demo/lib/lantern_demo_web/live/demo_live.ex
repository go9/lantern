defmodule LanternDemoWeb.DemoLive do
  use Phoenix.LiveView

  @impl true
  def mount(_params, _session, socket) do
    source = LanternDemo.DemoDB.url()

    socket =
      socket
      |> assign(
        source: source,
        theme: "system",
        accent: "#e45832",
        height: "680px",
        allow_raw_filter: false,
        reset_nonce: System.unique_integer([:positive])
      )
      |> ensure_demo_database()

    {:ok, socket}
  end

  @impl true
  def handle_event("customize", params, socket) do
    {:noreply,
     assign(socket,
       theme: Map.get(params, "theme", socket.assigns.theme),
       accent: Map.get(params, "accent", socket.assigns.accent),
       height: Map.get(params, "height", socket.assigns.height),
       allow_raw_filter: Map.get(params, "allow_raw_filter") == "true",
       notice: nil
     )}
  end

  defp ensure_demo_database(socket) do
    case LanternDemo.DemoDB.ensure() do
      :ok -> assign(socket, ready?: true, error: nil)
      {:error, reason} -> assign(socket, ready?: false, error: reason)
    end
  end

  defp lantern_style(height, accent, "dark") do
    lantern_style(height, accent, nil) <>
      " --lt-bg: oklch(0.18 0.018 39); --lt-bg-subtle: oklch(0.22 0.022 39);" <>
      " --lt-bg-hover: oklch(0.27 0.028 39); --lt-fg: oklch(0.94 0.01 55);" <>
      " --lt-fg-muted: oklch(0.72 0.018 55); --lt-border: oklch(0.32 0.028 39);"
  end

  defp lantern_style(height, accent, _theme) do
    "--lt-height: #{height}; --lt-accent: #{accent}; --lt-radius: 0.85rem;" <>
      " --lt-font: Space Grotesk, Inter, system-ui, sans-serif;" <>
      " --lt-mono: JetBrains Mono, ui-monospace, SFMono-Regular, monospace;"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="demo-shell" data-demo-theme={@theme}>
      <section class="demo-hero">
        <p class="demo-eyebrow">Lantern</p>
        <h1 class="demo-title">Drop a Postgres table editor into any LiveView.</h1>
        <p class="demo-copy">
          Point Lantern at a database and render one <code>live_component</code>. You get a table
          browser, sortable and filterable grids, inline editing, row inserts, a SQL workspace,
          and schema tools. This live demo is seeded with customers, orders, audit events, and an
          ops schema, so foreign keys, inserts, DDL, and primary-key edge cases all have something
          real to do.
        </p>
      </section>

      <section class="demo-panel demo-warning">
        <strong>Read-only demo.</strong>
        A public, isolated database you can browse, sort, filter, and query with read-only SQL.
        Never production data. To edit, insert, and run DDL, spin up your own private sandbox
        (coming soon).
      </section>

      <section :if={!@ready?} class="demo-panel demo-error">
        <h2>Demo database is not ready.</h2>
        <p>{@error}</p>
        <p>
          Start the bundled Postgres service with <code>docker compose up -d</code>, then run
          <code>mix setup</code> from <code>examples/demo</code>.
        </p>
      </section>

      <section :if={@ready?} class="demo-panel">
        <form phx-change="customize" class="demo-controls">
          <label>
            Theme
            <select name="theme">
              <option value="system" selected={@theme == "system"}>System</option>
              <option value="light" selected={@theme == "light"}>Light</option>
              <option value="dark" selected={@theme == "dark"}>Dark</option>
            </select>
          </label>

          <label>
            Accent
            <input type="color" name="accent" value={@accent} />
          </label>

          <label>
            Height
            <select name="height">
              <option value="520px" selected={@height == "520px"}>Compact</option>
              <option value="680px" selected={@height == "680px"}>Comfortable</option>
              <option value="820px" selected={@height == "820px"}>Tall</option>
            </select>
          </label>

          <label class="demo-checkbox">
            <input type="hidden" name="allow_raw_filter" value="false" />
            <input
              type="checkbox"
              name="allow_raw_filter"
              value="true"
              checked={@allow_raw_filter}
            />
            Enable raw SQL filter
          </label>
        </form>

        <div :if={@allow_raw_filter} class="demo-panel demo-warning demo-inline-warning">
          Raw filters are intentionally disabled by default. This demo toggle exposes the exact
          operator-only feature integrators can opt into with <code>allow_raw_filter: true</code>.
        </div>
      </section>

      <.live_component
        :if={@ready?}
        module={Lantern.Explorer}
        id={"lantern-demo-#{@reset_nonce}"}
        source={@source}
        title="Demo database"
        class="lantern-demo-instance"
        theme={@theme}
        allow_raw_filter={@allow_raw_filter}
        allow_sql_workspace={true}
        read_only={true}
        style={lantern_style(@height, @accent, @theme)}
      />
    </main>
    """
  end
end
