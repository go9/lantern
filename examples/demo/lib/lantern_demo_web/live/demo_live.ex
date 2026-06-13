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
        lv = self()

        Task.start(fn ->
          result =
            try do
              LanternDemo.SandboxManager.start(lv)
            catch
              :exit, _ -> {:error, "Sandbox creation timed out — please try again."}
            end

          send(lv, {:sandbox_result, result})
        end)

        {:noreply, assign(socket, sandbox: :creating)}

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
  # Info — sandbox creation result + countdown tick
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:sandbox_result, {:ok, %{url: url, ref: ref, ttl: ttl}}}, socket) do
    schedule_tick()
    {:noreply, assign(socket, sandbox: {:active, url, ref, ttl})}
  end

  def handle_info({:sandbox_result, {:error, reason}}, socket) do
    {:noreply, assign(socket, sandbox: {:error, reason})}
  end

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
          <span class="demo-readonly-badge">
            <svg width="10" height="10" viewBox="0 0 16 16" fill="currentColor">
              <path d="M11.5 1A3.5 3.5 0 0 0 8 4.5V7H2.5A1.5 1.5 0 0 0 1 8.5v5A1.5 1.5 0 0 0 2.5 15h11a1.5 1.5 0 0 0 1.5-1.5v-5A1.5 1.5 0 0 0 13.5 7H10V4.5a1.5 1.5 0 0 1 3 0v1h1.5v-1A3.5 3.5 0 0 0 11.5 1z"/>
            </svg>
            Read-only
          </span>
          {if @sandbox == :expired do
            " Sandbox expired — your 5-minute session ended and the database was deleted."
          else
            " You're browsing a shared database. Sorts, filters, and read-only SQL all work. Get a private sandbox to edit rows, insert data, or run DDL — no sign-up required."
          end}
          <span :if={match?({:error, _}, @sandbox)} style="color: inherit">
            {elem(@sandbox, 1)}
          </span>
        </div>
        <div class="demo-sandbox-actions">
          <button phx-click="request_sandbox" class="demo-btn demo-btn-primary">
            {if @sandbox == :expired, do: "New sandbox", else: "Try editing →"}
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
        <div class="demo-sandbox-active-top">
          <span class="demo-sandbox-live-dot"></span>
          <span class="demo-sandbox-live-label">Live sandbox — full read/write</span>
          <span class="demo-sandbox-timer">{format_time(elem(@sandbox, 3))} remaining</span>
          <button phx-click="release_sandbox" class="demo-btn demo-btn-sm">End session</button>
        </div>
        <div class="demo-sandbox-pitch">
          <p class="demo-sandbox-pitch-text">
            <strong>A real Postgres database was just forked and provisioned for you.</strong>
            It's isolated, writable, and self-destructs when you're done. This is what
            <strong>Flicker</strong> does for every branch of every app you deploy — instant
            preview databases on every pull request, no ops required.
          </p>
          <a
            href="https://flickercloud.com"
            target="_blank"
            rel="noopener"
            class="demo-flicker-link"
          >
            Build on Flicker
            <svg width="12" height="12" viewBox="0 0 16 16" fill="currentColor">
              <path d="M8.636 3.5a.5.5 0 0 0-.5-.5H1.5A1.5 1.5 0 0 0 0 4.5v10A1.5 1.5 0 0 0 1.5 16h10a1.5 1.5 0 0 0 1.5-1.5V7.864a.5.5 0 0 0-1 0V14.5a.5.5 0 0 1-.5.5h-10a.5.5 0 0 1-.5-.5v-10a.5.5 0 0 1 .5-.5h6.636a.5.5 0 0 0 .5-.5z"/>
              <path d="M16 .5a.5.5 0 0 0-.5-.5h-5a.5.5 0 0 0 0 1h3.793L6.146 9.146a.5.5 0 1 0 .708.708L15 1.707V5.5a.5.5 0 0 0 1 0v-5z"/>
            </svg>
          </a>
        </div>
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
