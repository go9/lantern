defmodule LanternDemoWeb.DemoLive do
  use Phoenix.LiveView

  # ---------------------------------------------------------------------------
  # Mount
  # ---------------------------------------------------------------------------

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
        reset_nonce: System.unique_integer([:positive]),
        sandbox: :none,
        turnstile_site_key: LanternDemo.Captcha.site_key()
      )
      |> ensure_demo_database()

    {:ok, socket}
  end

  # ---------------------------------------------------------------------------
  # Terminate — release any active sandbox
  # ---------------------------------------------------------------------------

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns.sandbox do
      {:active, _url, ref, _ticks} -> LanternDemo.SandboxManager.stop(ref)
      _ -> :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("customize", params, socket) do
    {:noreply,
     assign(socket,
       theme: Map.get(params, "theme", socket.assigns.theme),
       accent: Map.get(params, "accent", socket.assigns.accent),
       height: Map.get(params, "height", socket.assigns.height),
       allow_raw_filter: Map.get(params, "allow_raw_filter") == "true"
     )}
  end

  def handle_event("request_sandbox", _params, socket) do
    {:noreply, assign(socket, sandbox: :verifying)}
  end

  def handle_event("sandbox_token", %{"token" => token}, socket) do
    case LanternDemo.Captcha.verify(token) do
      :ok ->
        {:noreply, socket |> assign(sandbox: :creating) |> create_sandbox()}

      {:error, reason} ->
        {:noreply, assign(socket, sandbox: {:error, reason})}
    end
  end

  def handle_event("release_sandbox", _params, socket) do
    case socket.assigns.sandbox do
      {:active, _url, ref, _ticks} -> LanternDemo.SandboxManager.stop(ref)
      _ -> :ok
    end

    {:noreply, assign(socket, sandbox: :none, reset_nonce: System.unique_integer([:positive]))}
  end

  # ---------------------------------------------------------------------------
  # Info — countdown tick
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info(:sandbox_tick, socket) do
    case socket.assigns.sandbox do
      {:active, url, ref, ticks} when ticks > 1 ->
        schedule_tick()
        {:noreply, assign(socket, sandbox: {:active, url, ref, ticks - 1})}

      {:active, _url, ref, _} ->
        LanternDemo.SandboxManager.stop(ref)
        {:noreply, assign(socket, sandbox: :expired, reset_nonce: System.unique_integer([:positive]))}

      _ ->
        {:noreply, socket}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ensure_demo_database(socket) do
    case LanternDemo.DemoDB.ensure() do
      :ok -> assign(socket, ready?: true, error: nil)
      {:error, reason} -> assign(socket, ready?: false, error: reason)
    end
  end

  defp create_sandbox(socket) do
    case LanternDemo.SandboxManager.start(self()) do
      {:ok, %{url: url, ref: ref, ttl: ttl}} ->
        schedule_tick()
        assign(socket, sandbox: {:active, url, ref, ttl})

      {:error, reason} ->
        assign(socket, sandbox: {:error, reason})
    end
  end

  defp schedule_tick, do: Process.send_after(self(), :sandbox_tick, 1_000)

  defp format_time(seconds) do
    m = div(seconds, 60)
    s = rem(seconds, 60)
    "#{m}:#{String.pad_leading(to_string(s), 2, "0")}"
  end

  defp sandbox_source_or_default({:active, url, _ref, _ticks}, _default), do: url
  defp sandbox_source_or_default(_sandbox, default), do: default

  defp sandbox_title({:active, _url, _ref, _ticks}), do: "Your sandbox"
  defp sandbox_title(_), do: "Demo database"

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

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <main class="demo-shell" data-demo-theme={@theme}>
      <section class="demo-hero">
        <p class="demo-eyebrow">Lantern</p>
        <h1 class="demo-title">Drop a Postgres table editor into any LiveView.</h1>
        <p class="demo-copy">
          Point Lantern at a database and render one <code>live_component</code>. You get a
          table browser, sortable and filterable grids, inline editing, row inserts, a SQL
          workspace, and schema tools. This live demo is seeded with customers, orders, audit
          events, and an ops schema — foreign keys, inserts, DDL, and primary-key edge cases
          all have something real to do.
        </p>
      </section>

      <%!-- Read-only notice / sandbox request bar --%>
      <section
        :if={@sandbox in [:none, :expired] or match?({:error, _}, @sandbox)}
        class="demo-panel demo-warning demo-sandbox-bar"
      >
        <div class="demo-sandbox-desc">
          <strong>{if @sandbox == :expired, do: "Sandbox expired.", else: "Read-only demo."}</strong>
          {if @sandbox == :expired do
            " Your 5-minute session ended and the database was deleted."
          else
            " Browse, sort, filter, and run read-only SQL on this shared database. Spin up a private 5-minute sandbox to edit, insert, and run DDL."
          end}
          <span :if={match?({:error, _}, @sandbox)} style="color: inherit">
            {elem(@sandbox, 1)}
          </span>
        </div>
        <div class="demo-sandbox-actions">
          <button phx-click="request_sandbox" class="demo-btn demo-btn-primary">
            {if @sandbox == :expired, do: "New sandbox", else: "Get sandbox"}
          </button>
        </div>
      </section>

      <%!-- Captcha widget --%>
      <section :if={@sandbox in [:verifying, :creating]} class="demo-panel demo-captcha-panel">
        <p :if={@sandbox == :verifying} class="demo-captcha-hint">
          Complete the challenge below to unlock your private 5-minute sandbox.
        </p>
        <p :if={@sandbox == :creating} class="demo-captcha-hint">
          Creating your sandbox…
        </p>
        <div
          :if={@sandbox == :verifying}
          id="turnstile-widget"
          phx-hook="TurnstileWidget"
          data-sitekey={@turnstile_site_key}
          phx-update="ignore"
        >
        </div>
      </section>

      <%!-- Active sandbox banner --%>
      <section :if={match?({:active, _, _, _}, @sandbox)} class="demo-panel demo-sandbox-active">
        <span class="demo-sandbox-live-dot"></span>
        <span class="demo-sandbox-live-label">Live sandbox</span>
        <span class="demo-sandbox-timer">{format_time(elem(@sandbox, 3))} remaining</span>
        <button phx-click="release_sandbox" class="demo-btn demo-btn-sm">End session</button>
      </section>

      <%!-- Demo DB unavailable --%>
      <section :if={!@ready?} class="demo-panel demo-error">
        <h2>Demo database is not ready.</h2>
        <p>{@error}</p>
        <p>
          Start the bundled Postgres service with <code>docker compose up -d</code>, then run
          <code>mix setup</code> from <code>examples/demo</code>.
        </p>
      </section>

      <%!-- Controls --%>
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
          Raw filters are intentionally disabled by default. This demo toggle exposes the
          operator-only feature integrators can opt into with <code>allow_raw_filter: true</code>.
        </div>
      </section>

      <%!-- Lantern component --%>
      <.live_component
        :if={@ready?}
        module={Lantern.Explorer}
        id={"lantern-demo-#{@reset_nonce}"}
        source={sandbox_source_or_default(@sandbox, @source)}
        title={sandbox_title(@sandbox)}
        class="lantern-demo-instance"
        theme={@theme}
        allow_raw_filter={@allow_raw_filter}
        allow_sql_workspace={true}
        read_only={not match?({:active, _, _, _}, @sandbox)}
        style={lantern_style(@height, @accent, @theme)}
      />
    </main>
    """
  end
end
