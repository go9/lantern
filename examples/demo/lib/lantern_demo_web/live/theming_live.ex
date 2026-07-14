defmodule LanternDemoWeb.ThemingLive do
  @moduledoc """
  Theming — modeled on flicker's `admin_themes_live` branding panel, but
  client-side (no DB): named themes per mode, active light/dark selection, and
  a slide-over editor with a live preview + grouped color tokens.

  Themes are defined in the **Fluxon semantic token vocabulary** (`primary`,
  `foreground`, `background_base`, `border_base`, …) — the same names a flicker
  theme uses — so a theme built here is portable to flicker, and applying one
  flows through lantern-ui's Fluxon-token chain to re-skin every component.
  Persistence is localStorage; a real app would back this with a DB like
  flicker does.
  """
  use Phoenix.LiveView

  alias LanternUI.Components.Button
  alias LanternUI.Components.Icon
  alias LanternUI.Components.Sheet

  # Token groups + labels — identical grouping to flicker's theme editor.
  @groups [
    {"Primary Colors", ~w(primary primary_soft foreground_primary)},
    {"Background Colors", ~w(background_base background_accent background_input surface overlay)},
    {"Text Colors",
     ~w(foreground foreground_soft foreground_softer foreground_softest border_base)},
    {"Status Colors", ~w(danger success warning info)}
  ]

  @labels %{
    "primary" => "Primary",
    "primary_soft" => "Primary Soft",
    "foreground_primary" => "Primary Text",
    "background_base" => "Background",
    "background_accent" => "Background Accent",
    "background_input" => "Input Background",
    "surface" => "Surface",
    "overlay" => "Overlay",
    "foreground" => "Text",
    "foreground_soft" => "Text Soft",
    "foreground_softer" => "Text Softer",
    "foreground_softest" => "Text Softest",
    "border_base" => "Border",
    "danger" => "Danger",
    "success" => "Success",
    "warning" => "Warning",
    "info" => "Info"
  }

  @light_themes [
    %{
      id: "flicker",
      name: "Flicker",
      desc: "Coral on warm off-white — lantern's default.",
      tokens: %{
        "primary" => "#d1521e",
        "primary_soft" => "#fbeee6",
        "foreground_primary" => "#fffdfb",
        "background_base" => "#fdfcfa",
        "background_accent" => "#f4f1ec",
        "background_input" => "#fffefc",
        "surface" => "#fffefc",
        "overlay" => "#fffefc",
        "foreground" => "#3a3630",
        "foreground_soft" => "#5c554c",
        "foreground_softer" => "#837a6e",
        "foreground_softest" => "#a89e90",
        "border_base" => "#e7e2da",
        "danger" => "#d0342c",
        "success" => "#2f9e5f",
        "warning" => "#d99a2b",
        "info" => "#3b7dd8"
      }
    },
    %{
      id: "ocean",
      name: "Ocean",
      desc: "Blue accent on cool slate-tinted surfaces.",
      tokens: %{
        "primary" => "#2563eb",
        "primary_soft" => "#e6eefc",
        "foreground_primary" => "#ffffff",
        "background_base" => "#fbfcfe",
        "background_accent" => "#eef2f8",
        "background_input" => "#ffffff",
        "surface" => "#ffffff",
        "overlay" => "#ffffff",
        "foreground" => "#1e293b",
        "foreground_soft" => "#475569",
        "foreground_softer" => "#64748b",
        "foreground_softest" => "#94a3b8",
        "border_base" => "#e2e8f0",
        "danger" => "#dc2626",
        "success" => "#16a34a",
        "warning" => "#d97706",
        "info" => "#2563eb"
      }
    },
    %{
      id: "paper",
      name: "Paper",
      desc: "Amber accent on warm paper surfaces.",
      tokens: %{
        "primary" => "#b45309",
        "primary_soft" => "#f7ecd9",
        "foreground_primary" => "#fffbf2",
        "background_base" => "#faf7f0",
        "background_accent" => "#f0e9dc",
        "background_input" => "#fffdf8",
        "surface" => "#fffdf8",
        "overlay" => "#fffdf8",
        "foreground" => "#3f3a2f",
        "foreground_soft" => "#635b49",
        "foreground_softer" => "#8a7f66",
        "foreground_softest" => "#b0a488",
        "border_base" => "#e8dfcc",
        "danger" => "#c0392b",
        "success" => "#3d8b52",
        "warning" => "#c07c1a",
        "info" => "#3f6f9c"
      }
    }
  ]

  @dark_themes [
    %{
      id: "flicker-dark",
      name: "Flicker Dark",
      desc: "Ember coral over warm near-black.",
      tokens: %{
        "primary" => "#e8623a",
        "primary_soft" => "#3a241a",
        "foreground_primary" => "#fffdfb",
        "background_base" => "#1a1613",
        "background_accent" => "#2a231e",
        "background_input" => "#201b17",
        "surface" => "#221c18",
        "overlay" => "#26201b",
        "foreground" => "#f2ede7",
        "foreground_soft" => "#cec6bc",
        "foreground_softer" => "#a49a8e",
        "foreground_softest" => "#7d7367",
        "border_base" => "#3a322b",
        "danger" => "#ef5350",
        "success" => "#4caf7f",
        "warning" => "#e0a92e",
        "info" => "#5b9bd5"
      }
    },
    %{
      id: "midnight",
      name: "Midnight",
      desc: "Blue accent over blue-black chrome.",
      tokens: %{
        "primary" => "#5b9bf5",
        "primary_soft" => "#1b2a44",
        "foreground_primary" => "#0b1020",
        "background_base" => "#0b1020",
        "background_accent" => "#161f36",
        "background_input" => "#111730",
        "surface" => "#141b30",
        "overlay" => "#182035",
        "foreground" => "#e8edf7",
        "foreground_soft" => "#c0cade",
        "foreground_softer" => "#8f9cb8",
        "foreground_softest" => "#697392",
        "border_base" => "#26304a",
        "danger" => "#f26161",
        "success" => "#43c07f",
        "warning" => "#e6b23e",
        "info" => "#5b9bf5"
      }
    },
    %{
      id: "slate",
      name: "Slate",
      desc: "Neutral cool-slate accent on dark.",
      tokens: %{
        "primary" => "#94a3b8",
        "primary_soft" => "#242a33",
        "foreground_primary" => "#0f141a",
        "background_base" => "#0f141a",
        "background_accent" => "#1c232c",
        "background_input" => "#151b22",
        "surface" => "#191f27",
        "overlay" => "#1d242d",
        "foreground" => "#e6eaef",
        "foreground_soft" => "#c2c9d2",
        "foreground_softer" => "#939fac",
        "foreground_softest" => "#6b7682",
        "border_base" => "#2a323c",
        "danger" => "#ef5350",
        "success" => "#4caf7f",
        "warning" => "#e0a92e",
        "info" => "#7d94b0"
      }
    }
  ]

  def groups, do: @groups
  def light_themes, do: @light_themes
  def dark_themes, do: @dark_themes

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Theming - lantern-ui")
     |> assign(:active_light, "flicker")
     |> assign(:active_dark, "flicker-dark")
     |> assign(:editing, nil)
     |> assign(:groups, @groups)
     |> assign(:labels, @labels)
     |> assign(:light_themes, @light_themes)
     |> assign(:dark_themes, @dark_themes)
     |> assign(:edited, %{})}
  end

  # Restore persisted active themes (pushed by the DemoTheming hook on mount).
  def handle_event("restore", %{"light" => l, "dark" => d}, socket) do
    socket = if theme(l), do: assign(socket, :active_light, l), else: socket
    socket = if theme(d), do: assign(socket, :active_dark, d), else: socket
    {:noreply, apply_active(socket)}
  end

  def handle_event("restore", _params, socket), do: {:noreply, apply_active(socket)}

  def handle_event("set_active", params, socket) do
    socket =
      case params["_target"] do
        ["light"] -> assign(socket, :active_light, params["light"])
        ["dark"] -> assign(socket, :active_dark, params["dark"])
        _ -> socket
      end

    {:noreply, apply_active(socket)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, theme(id))}
  end

  def handle_event("edit_token", %{"_target" => [key]} = params, socket)
      when is_map_key(params, key) do
    editing = put_in(socket.assigns.editing, [:tokens, key], params[key])
    {:noreply, assign(socket, :editing, editing)}
  end

  def handle_event("edit_token", _params, socket), do: {:noreply, socket}

  def handle_event("apply_edits", _params, socket) do
    %{editing: editing} = socket.assigns
    mode = if editing.id in Enum.map(@dark_themes, & &1.id), do: "dark", else: "light"

    {:noreply,
     socket
     |> put_edited(editing)
     |> set_active_edited(mode, editing.id)
     |> apply_active()
     |> push_event("lantern:dialog:close", %{id: "theme-editor"})}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     socket
     |> assign(:active_light, "flicker")
     |> assign(:active_dark, "flicker-dark")
     |> assign(:edited, %{})
     |> apply_active()}
  end

  # ── helpers ──

  defp theme(id), do: Enum.find(@light_themes ++ @dark_themes, &(&1.id == id))

  defp all_themes(socket) do
    edited = Map.get(socket.assigns, :edited, %{})
    Enum.map(@light_themes ++ @dark_themes, fn t -> Map.get(edited, t.id, t) end)
  end

  defp resolved(socket, id) do
    Enum.find(all_themes(socket), &(&1.id == id)) || theme(id)
  end

  defp put_edited(socket, theme) do
    edited = Map.put(Map.get(socket.assigns, :edited, %{}), theme.id, theme)
    assign(socket, :edited, edited)
  end

  defp set_active_edited(socket, "dark", id), do: assign(socket, :active_dark, id)
  defp set_active_edited(socket, _light, id), do: assign(socket, :active_light, id)

  # Inject the active light + dark themes as Fluxon-named CSS vars, and persist.
  defp apply_active(socket) do
    light = resolved(socket, socket.assigns.active_light)
    dark = resolved(socket, socket.assigns.active_dark)

    css =
      ":root, .light {\n#{tokens_css(light.tokens)}\n}\n" <>
        ".dark {\n#{tokens_css(dark.tokens)}\n}\n" <>
        "@media (prefers-color-scheme: dark) { :root:not(.light) {\n#{tokens_css(dark.tokens)}\n} }"

    socket
    |> push_event("demo:inject-theme", %{css: css})
    |> push_event("demo:persist-theme", %{
      light: socket.assigns.active_light,
      dark: socket.assigns.active_dark
    })
  end

  defp tokens_css(tokens) do
    tokens
    |> Enum.map(fn {k, v} -> "  --#{String.replace(k, "_", "-")}: #{v};" end)
    |> Enum.join("\n")
  end

  def render(assigns) do
    assigns = assign(assigns, :resolved_themes, resolved_all(assigns))

    ~H"""
    <LanternDemoWeb.DocsShell.shell current="theming" theme="system" density="compact">
      <div id="theming-root" phx-hook="DemoTheming">
        <article class="docs-body docs-body-wide">
          <h1>Theming</h1>
          <p>
            Named themes per mode, edited in a slide-over with a live preview — modeled on
            flicker's branding panel. Themes are defined in the Fluxon token vocabulary, so a
            theme built here drops straight into flicker (and re-skins every lantern component).
          </p>

          <section class="docs-section">
            <form class="th-active" phx-change="set_active">
              <div class="th-field">
                <label for="active-light-select" class="th-field-label">Light mode theme</label>
                <div class="lui-select-native-wrap">
                  <select id="active-light-select" class="lui-select-native" name="light">
                    <option :for={t <- @light_themes} value={t.id} selected={t.id == @active_light}>
                      {t.name}
                    </option>
                  </select>
                  <Icon.icon name="chevron-up-down" class="lui-select-caret" />
                </div>
              </div>
              <div class="th-field">
                <label for="active-dark-select" class="th-field-label">Dark mode theme</label>
                <div class="lui-select-native-wrap">
                  <select id="active-dark-select" class="lui-select-native" name="dark">
                    <option :for={t <- @dark_themes} value={t.id} selected={t.id == @active_dark}>
                      {t.name}
                    </option>
                  </select>
                  <Icon.icon name="chevron-up-down" class="lui-select-caret" />
                </div>
              </div>
              <Button.button variant="ghost" size="sm" type="button" phx-click="reset">
                <Icon.icon name="arrow-path" /> Reset
              </Button.button>
            </form>
          </section>

          <section class="docs-section">
            <h2 class="docs-section-title">Available themes</h2>
            <p class="docs-section-desc">Click a theme to edit its tokens and preview live.</p>
            <div class="th-cards">
              <button
                :for={t <- @resolved_themes}
                type="button"
                class={["th-card", (t.id in [@active_light, @active_dark]) && "th-card-active"]}
                phx-click="edit"
                phx-value-id={t.id}
              >
                <span class="th-swatches">
                  <span
                    :for={k <- ~w(primary background_base surface foreground border_base)}
                    class="th-swatch"
                    style={"background: #{t.tokens[k]}"}
                  >
                  </span>
                </span>
                <span class="th-card-meta">
                  <span class="th-card-name">{t.name}</span>
                  <span class="th-card-desc">{t.desc}</span>
                </span>
              </button>
            </div>
          </section>
        </article>

        <Sheet.sheet
          :if={@editing}
          id="theme-editor"
          placement="right"
          open
          title={"Edit · #{@editing.name}"}
        >
          <div class="th-preview" style={preview_style(@editing.tokens)}>
            <div class="th-preview-label">Preview</div>
            <div class="th-prow">
              <span class="th-btn-primary" style={btn_primary_style(@editing.tokens)}>Primary</span>
              <span class="th-btn-secondary" style={btn_secondary_style(@editing.tokens)}>
                Secondary
              </span>
            </div>
            <div class="th-prow">
              <span class="th-pill" style={pill_style(@editing.tokens, "success")}>success</span>
              <span class="th-pill" style={pill_style(@editing.tokens, "danger")}>danger</span>
              <span class="th-pill" style={pill_style(@editing.tokens, "warning")}>warning</span>
              <span class="th-pill" style={pill_style(@editing.tokens, "info")}>info</span>
            </div>
            <input
              class="th-input"
              style={input_style(@editing.tokens)}
              placeholder="Input field"
              readonly
            />
            <div style={"color: #{@editing.tokens["foreground"]}; font-weight:600;"}>Primary text</div>
            <div style={"color: #{@editing.tokens["foreground_soft"]}; font-size:.85rem;"}>
              Secondary text
            </div>
            <div style={"color: #{@editing.tokens["foreground_softer"]}; font-size:.78rem;"}>
              Softer text
            </div>
          </div>

          <form phx-change="edit_token" class="th-groups">
            <div :for={{group, keys} <- @groups} class="th-group">
            <h4 class="th-group-title">{group}</h4>
            <div class="th-tokens">
              <label :for={key <- keys} class="th-token">
                <span class="th-token-swatch" style={"background: #{@editing.tokens[key]}"}></span>
                <span class="th-token-label">{@labels[key]}</span>
                <input
                  type="color"
                  class="th-color"
                  value={@editing.tokens[key]}
                  phx-change="edit_token"
                  name={key}
                />
              </label>
            </div>
            </div>
          </form>

          <:footer>
            <Button.button variant="outline" size="sm" phx-click={LanternUI.close_dialog("theme-editor")}>
              Cancel
            </Button.button>
            <Button.button
              variant="solid"
              size="sm"
              phx-click="apply_edits"
              phx-click-away={LanternUI.close_dialog("theme-editor")}
            >
              Apply
            </Button.button>
          </:footer>
        </Sheet.sheet>
      </div>

      <style>
        .th-active { display: flex; align-items: flex-end; gap: 1rem; flex-wrap: wrap; }
        .th-field { display: flex; flex-direction: column; gap: 0.25rem; min-width: 12rem; }
        .th-field-label { font-size: var(--lantern-text-sm); font-weight: 550; color: var(--lantern-fg); }
        .th-cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(15rem, 1fr)); gap: 0.75rem; }
        .th-card { display: flex; align-items: center; gap: 0.7rem; text-align: left; padding: 0.7rem;
          background: var(--lantern-surface-raised); border: 1px solid var(--lantern-border);
          border-radius: var(--lantern-radius-lg); cursor: pointer; font-family: inherit; }
        .th-card:hover { background: var(--lantern-surface-hover); }
        .th-card-active { border-color: var(--lantern-accent); box-shadow: 0 0 0 1px var(--lantern-accent); }
        .th-swatches { display: inline-flex; border-radius: var(--lantern-radius-sm); overflow: hidden;
          border: 1px solid var(--lantern-border); flex-shrink: 0; }
        .th-swatch { width: 1rem; height: 2.2rem; display: block; }
        .th-card-meta { display: flex; flex-direction: column; gap: 0.1rem; min-width: 0; }
        .th-card-name { font-weight: 600; font-size: 0.85rem; color: var(--lantern-fg); }
        .th-card-desc { font-size: 0.72rem; color: var(--lantern-fg-muted); }
        .th-preview { border: 1px solid; border-radius: var(--lantern-radius-lg); padding: 0.9rem;
          margin-bottom: 1.25rem; display: flex; flex-direction: column; gap: 0.55rem; }
        .th-preview-label { font-size: 0.68rem; text-transform: uppercase; letter-spacing: 0.05em;
          opacity: 0.6; }
        .th-prow { display: flex; gap: 0.4rem; align-items: center; flex-wrap: wrap; }
        .th-btn-primary, .th-btn-secondary { padding: 0.3rem 0.7rem; border-radius: 0.4rem;
          font-size: 0.8rem; font-weight: 600; }
        .th-btn-secondary { border: 1px solid; }
        .th-pill { padding: 0.1rem 0.5rem; border-radius: 999px; font-size: 0.7rem; font-weight: 600; }
        .th-input { padding: 0.35rem 0.5rem; border-radius: 0.4rem; border: 1px solid; font-size: 0.8rem; }
        .th-group { margin-bottom: 1.1rem; }
        .th-group-title { font-size: 0.8rem; font-weight: 650; color: var(--lantern-fg); margin: 0 0 0.5rem; }
        .th-tokens { display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; }
        .th-token { display: flex; align-items: center; gap: 0.45rem; font-size: 0.76rem;
          color: var(--lantern-fg-muted); cursor: pointer; }
        .th-token-swatch { width: 0.9rem; height: 0.9rem; border-radius: 3px;
          border: 1px solid var(--lantern-border); flex-shrink: 0; }
        .th-token-label { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .th-color { width: 1.6rem; height: 1.4rem; padding: 0; border: 1px solid var(--lantern-border);
          border-radius: 4px; background: none; cursor: pointer; flex-shrink: 0; }
      </style>
    </LanternDemoWeb.DocsShell.shell>
    """
  end

  defp resolved_all(assigns) do
    edited = Map.get(assigns, :edited, %{})
    Enum.map(@light_themes ++ @dark_themes, fn t -> Map.get(edited, t.id, t) end)
  end

  defp preview_style(t),
    do: "background: #{t["background_base"]}; border-color: #{t["border_base"]};"

  defp btn_primary_style(t),
    do: "background: #{t["primary"]}; color: #{t["foreground_primary"]};"

  defp btn_secondary_style(t),
    do:
      "background: #{t["surface"]}; color: #{t["foreground"]}; border-color: #{t["border_base"]};"

  defp pill_style(t, key) do
    "background: color-mix(in oklab, #{t[key]} 15%, transparent); color: #{t[key]};"
  end

  defp input_style(t),
    do:
      "background: #{t["background_input"]}; color: #{t["foreground"]}; border-color: #{t["border_base"]};"
end
