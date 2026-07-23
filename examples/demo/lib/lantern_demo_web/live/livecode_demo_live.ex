defmodule LanternDemoWeb.LiveCodeDemoLive do
  @moduledoc """
  Canonical public demo for LiveCode inside the Lantern documentation shell.
  """
  use Phoenix.LiveView

  @languages [
    %{id: "html", label: "HTML"},
    %{id: "sql", label: "SQL"},
    %{id: "json", label: "JSON"},
    %{id: "heex", label: "HEEx"}
  ]

  @modes [
    %{id: "edit", label: "Editable"},
    %{id: "readonly", label: "Read only"}
  ]

  @samples %{
    "html" => """
    <div style="font-family:system-ui,sans-serif;max-width:420px;margin:24px auto;
                border:1px solid #e5e7eb;border-radius:14px;overflow:hidden;">
      <div style="background:#534AB7;color:#fff;padding:20px 24px;">
        <h1 style="margin:0;font-size:22px;">livecode</h1>
        <p style="margin:6px 0 0;opacity:.85;font-size:14px;">Edit the HTML and the preview updates live.</p>
      </div>
      <div style="padding:20px 24px;color:#334155;">
        <p style="margin:0 0 12px;">Try <strong>Split</strong> to see code and preview together.</p>
        <a href="#" style="display:inline-block;background:#534AB7;color:#fff;
           text-decoration:none;padding:9px 16px;border-radius:8px;font-size:14px;">A button</a>
      </div>
    </div>
    """,
    "sql" => """
    -- Scroll, add a line, or remove one. The gutter stays aligned.
    with recent_orders as (
      select
        customer_id,
        total_cents,
        created_at
      from orders
      where created_at >= current_date - interval '30 days'
        and status = 'paid'
    ),
    customer_totals as (
      select
        customer_id,
        count(*) as order_count,
        sum(total_cents) as lifetime_cents
      from recent_orders
      group by customer_id
    )
    select
      users.id,
      users.name,
      users.email,
      customer_totals.order_count,
      customer_totals.lifetime_cents
    from users
    join customer_totals on customer_totals.customer_id = users.id
    where users.active = true
    order by customer_totals.lifetime_cents desc
    limit 10;
    """,
    "json" => """
    {
      "message": "Hello, world!",
      "editor": "livecode",
      "languages": ["html", "sql", "json", "heex"],
      "awesome": true
    }
    """,
    "heex" => ~S"""
    <.form for={@form} id="profile-form" phx-submit="save">
      <.input field={@form[:name]} label="Name" />
      <.input field={@form[:email]} type="email" label="Email" />

      <div :if={@form.source.action} class="text-red-600">
        Please check the highlighted fields.
      </div>

      <.button disabled={@saving}>
        <%= if @saving do %>
          Saving…
        <% else %>
          Save profile
        <% end %>
      </.button>
    </.form>
    """
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       languages: @languages,
       modes: @modes,
       current: "html",
       mode: "edit",
       samples: @samples
     )}
  end

  @impl true
  def handle_event("select-language", %{"lang" => lang}, socket)
      when is_map_key(@samples, lang) do
    mode = if lang == "heex", do: "readonly", else: socket.assigns.mode
    {:noreply, assign(socket, current: lang, mode: mode)}
  end

  def handle_event("select-language", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("select-mode", %{"mode" => "readonly"}, socket) do
    {:noreply, assign(socket, mode: "readonly")}
  end

  def handle_event("select-mode", %{"mode" => "edit"}, %{assigns: %{current: "heex"}} = socket) do
    {:noreply, socket}
  end

  def handle_event("select-mode", %{"mode" => "edit"}, socket) do
    {:noreply, assign(socket, mode: "edit")}
  end

  def handle_event("select-mode", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <LanternDemoWeb.DocsShell.shell current="livecode" theme="system">
      <div class="demo-shell">
        <section class="demo-hero">
          <p class="demo-eyebrow">LiveCode</p>
          <h1 class="demo-title">A real code editor, in a textarea.</h1>
          <p class="demo-copy">
            <code>livecode</code>
            adds syntax highlighting, autocomplete, snippets, diagnostics, and live HTML preview to a plain
            <code>&lt;textarea&gt;</code>.
            <a href="https://github.com/go9/livecode" target="_blank" rel="noopener">
              View on GitHub →
            </a>
          </p>
        </section>

        <section class="demo-panel">
          <div class="livecode-toolbar">
            <div class="livecode-picker">
              <p id="language-selector-label">Language</p>
              <div role="group" aria-labelledby="language-selector-label">
                <button
                  :for={language <- @languages}
                  id={"language-#{language.id}"}
                  type="button"
                  phx-click="select-language"
                  phx-value-lang={language.id}
                  aria-pressed={to_string(@current == language.id)}
                  class={[
                    "demo-btn demo-btn-sm",
                    @current == language.id && "demo-btn-primary"
                  ]}
                >
                  {language.label}
                </button>
              </div>
            </div>

            <div class="livecode-picker">
              <p id="mode-selector-label">Mode</p>
              <div role="group" aria-labelledby="mode-selector-label">
                <button
                  :for={mode <- @modes}
                  id={"mode-#{mode.id}"}
                  type="button"
                  phx-click="select-mode"
                  phx-value-mode={mode.id}
                  aria-pressed={to_string(@mode == mode.id)}
                  disabled={mode.id == "edit" and @current == "heex"}
                  class={[
                    "demo-btn demo-btn-sm",
                    @mode == mode.id && "demo-btn-primary"
                  ]}
                >
                  {mode.label}
                </button>
              </div>
            </div>
          </div>

          <LiveCode.Editor.editor
            id={"editor-#{@current}-#{@mode}"}
            language={language_module(@current)}
            value={Map.fetch!(@samples, @current)}
            preview={:split}
            readonly={@mode == "readonly"}
            rows={18}
            class="docs-codeblock"
          />

          <p class="livecode-help">
            <%= if @mode == "edit" do %>
              Type to highlight. Press <kbd>Ctrl</kbd>/<kbd>⌘</kbd> + <kbd>Space</kbd> for completions.
            <% else %>
              Read-only mode renders highlighted, copyable code without editor JavaScript.
            <% end %>
            <span>
              HTML exposes Code, Preview, and Split. SQL and JSON stay code-only. HEEx demonstrates Lantern's server-rendered read-only snippets.
            </span>
          </p>
        </section>
      </div>

      <style>
        .livecode-toolbar {
          display: flex;
          flex-wrap: wrap;
          gap: .85rem 1.5rem;
          margin-bottom: .85rem;
        }
        .livecode-picker > p {
          margin: 0 0 .35rem;
          color: var(--demo-muted-local);
          font-size: .7rem;
          font-weight: 720;
          letter-spacing: .05em;
          text-transform: uppercase;
        }
        .livecode-picker > div {
          display: flex;
          flex-wrap: wrap;
          gap: .4rem;
        }
        .livecode-picker .demo-btn[disabled] {
          cursor: not-allowed;
          opacity: .45;
        }
        .livecode-help {
          margin: .75rem 0 0;
          color: var(--demo-muted-local);
          font-size: .8rem;
          line-height: 1.5;
        }
        .livecode-help span { display: block; margin-top: .2rem; }
        .livecode-help kbd {
          border: 1px solid var(--demo-border-local);
          border-radius: .25rem;
          padding: 0 .25rem;
          font-family: var(--lantern-font-mono);
        }
      </style>
    </LanternDemoWeb.DocsShell.shell>
    """
  end

  defp language_module("sql"), do: LiveCode.Languages.SQL
  defp language_module("json"), do: LiveCode.Languages.JSON
  defp language_module("heex"), do: LiveCode.Languages.HEEx
  defp language_module(_language), do: LiveCode.Languages.HTML
end
