defmodule LanternDemoWeb.ThemingLive do
  @moduledoc """
  Client-side runtime theming controls for the Lantern demo.
  """
  use Phoenix.LiveView

  alias LanternUI.Components.Alert
  alias LanternUI.Components.Badge
  alias LanternUI.Components.Button
  alias LanternUI.Components.Checkbox
  alias LanternUI.Components.Radio
  alias LanternUI.Components.Select
  alias LanternUI.Components.Switch
  alias LanternUI.Components.Tabs

  @light_status %{
    danger: "#dc2626",
    success: "#16a34a",
    warning: "#d97706"
  }

  @dark_status %{
    danger: "#ef4444",
    success: "#22c55e",
    warning: "#f59e0b"
  }

  @light_themes [
    %{
      id: "coral",
      name: "Coral",
      description: "Lantern's default warm accent on clean zinc surfaces.",
      tokens:
        Map.merge(@light_status, %{
          accent: "oklch(0.637 0.192 38)",
          accent_fg: "#ffffff",
          fg: "#09090b",
          fg_muted: "#71717a",
          fg_subtle: "#a1a1aa",
          surface: "#ffffff",
          surface_raised: "#ffffff",
          surface_sunken: "#f4f4f5",
          surface_hover: "#f4f4f5",
          border: "#e4e4e7",
          border_strong: "#d4d4d8"
        })
    },
    %{
      id: "ocean",
      name: "Ocean",
      description: "A blue accent with cool, slate-tinted surfaces.",
      tokens:
        Map.merge(@light_status, %{
          accent: "#2563eb",
          accent_fg: "#ffffff",
          fg: "#0f172a",
          fg_muted: "#64748b",
          fg_subtle: "#94a3b8",
          surface: "#f8fafc",
          surface_raised: "#ffffff",
          surface_sunken: "#f1f5f9",
          surface_hover: "#e2e8f0",
          border: "#cbd5e1",
          border_strong: "#94a3b8"
        })
    },
    %{
      id: "forest",
      name: "Forest",
      description: "Green emphasis over soft warm-neutral surfaces.",
      tokens:
        Map.merge(@light_status, %{
          accent: "#15803d",
          accent_fg: "#ffffff",
          fg: "#1f2933",
          fg_muted: "#6b665f",
          fg_subtle: "#9a9186",
          surface: "#fffdfa",
          surface_raised: "#ffffff",
          surface_sunken: "#f4f1ea",
          surface_hover: "#eee9df",
          border: "#ded8cb",
          border_strong: "#c9bdad"
        })
    },
    %{
      id: "plum",
      name: "Plum",
      description: "Violet controls with pale lavender surfaces.",
      tokens:
        Map.merge(@light_status, %{
          accent: "#6d28d9",
          accent_fg: "#ffffff",
          fg: "#18151f",
          fg_muted: "#6d6478",
          fg_subtle: "#9b8faa",
          surface: "#fbfaff",
          surface_raised: "#ffffff",
          surface_sunken: "#f5f3ff",
          surface_hover: "#ede9fe",
          border: "#ddd6fe",
          border_strong: "#c4b5fd"
        })
    },
    %{
      id: "paper",
      name: "Paper",
      description: "Amber accents on warm off-white paper surfaces.",
      tokens:
        Map.merge(@light_status, %{
          accent: "#92400e",
          accent_fg: "#ffffff",
          fg: "#1c1917",
          fg_muted: "#78716c",
          fg_subtle: "#a8a29e",
          surface: "#faf9f7",
          surface_raised: "#fffefd",
          surface_sunken: "#f1eee9",
          surface_hover: "#ebe6df",
          border: "#e7e5e4",
          border_strong: "#d6d3d1"
        })
    }
  ]

  @dark_themes [
    %{
      id: "coral-dark",
      name: "Coral Dark",
      description: "Lantern's default dark mode with ember focus.",
      tokens:
        Map.merge(@dark_status, %{
          accent: "oklch(0.685 0.182 39)",
          accent_fg: "#ffffff",
          fg: "#fafafa",
          fg_muted: "#a1a1aa",
          fg_subtle: "#71717a",
          surface: "#09090b",
          surface_raised: "#0c0c0e",
          surface_sunken: "#18181b",
          surface_hover: "#26262a",
          border: "#26262a",
          border_strong: "#3f3f46"
        })
    },
    %{
      id: "midnight",
      name: "Midnight",
      description: "Blue accents over blue-black application chrome.",
      tokens:
        Map.merge(@dark_status, %{
          accent: "#60a5fa",
          accent_fg: "#07111f",
          fg: "#f8fafc",
          fg_muted: "#a9b4c8",
          fg_subtle: "#64748b",
          surface: "#0b1020",
          surface_raised: "#111730",
          surface_sunken: "#080d19",
          surface_hover: "#1a2440",
          border: "#24304a",
          border_strong: "#33415f"
        })
    },
    %{
      id: "forest-dark",
      name: "Forest Dark",
      description: "A green signal theme on deep moss surfaces.",
      tokens:
        Map.merge(@dark_status, %{
          accent: "#4ade80",
          accent_fg: "#052e16",
          fg: "#f3fbf5",
          fg_muted: "#a8b8aa",
          fg_subtle: "#728074",
          surface: "#0b130d",
          surface_raised: "#101b13",
          surface_sunken: "#071009",
          surface_hover: "#1c2b20",
          border: "#26382c",
          border_strong: "#3b5243"
        })
    },
    %{
      id: "plum-dark",
      name: "Plum Dark",
      description: "A violet accent over saturated night surfaces.",
      tokens:
        Map.merge(@dark_status, %{
          accent: "#c084fc",
          accent_fg: "#2e1065",
          fg: "#fbf7ff",
          fg_muted: "#c4b5d4",
          fg_subtle: "#8b7aa3",
          surface: "#120d1f",
          surface_raised: "#191129",
          surface_sunken: "#0d0918",
          surface_hover: "#26193b",
          border: "#35224f",
          border_strong: "#4c3570"
        })
    },
    %{
      id: "slate",
      name: "Slate",
      description: "Neutral contrast with a cool slate accent.",
      tokens:
        Map.merge(@dark_status, %{
          accent: "#94a3b8",
          accent_fg: "#0f172a",
          fg: "#f8fafc",
          fg_muted: "#a1a8b3",
          fg_subtle: "#6b7280",
          surface: "#0f1117",
          surface_raised: "#151821",
          surface_sunken: "#0a0d12",
          surface_hover: "#20242e",
          border: "#2b303b",
          border_strong: "#475569"
        })
    }
  ]

  @theme_presets Map.new(
                   Enum.map(@light_themes, &{"light:#{&1.id}", &1.tokens}) ++
                     Enum.map(@dark_themes, &{"dark:#{&1.id}", &1.tokens})
                 )

  @token_rows [
    %{key: "accent", label: "Accent"},
    %{key: "accent_fg", label: "Accent foreground"},
    %{key: "fg", label: "Foreground"},
    %{key: "fg_muted", label: "Muted foreground"},
    %{key: "fg_subtle", label: "Subtle foreground"},
    %{key: "surface", label: "Surface"},
    %{key: "surface_raised", label: "Raised surface"},
    %{key: "surface_sunken", label: "Sunken surface"},
    %{key: "surface_hover", label: "Hover surface"},
    %{key: "border", label: "Border"},
    %{key: "border_strong", label: "Strong border"},
    %{key: "danger", label: "Danger"},
    %{key: "success", label: "Success"},
    %{key: "warning", label: "Warning"}
  ]

  @radius_options [
    {"None", "0rem"},
    {"Small", "0.375rem"},
    {"Default", "0.5rem"},
    {"Large", "0.75rem"},
    {"Round", "1rem"}
  ]

  @density_options [
    {"Compact", "compact"},
    {"Comfortable", "comfortable"}
  ]

  @font_options [
    {"System", ~s("Inter", ui-sans-serif, system-ui, sans-serif),
     "The demo's current body stack."},
    {"Grotesque", ~s("Space Grotesk", "Inter", system-ui, sans-serif),
     "A tighter display voice for app chrome and controls."},
    {"Serif", ~s("Iowan Old Style", Georgia, serif),
     "A warmer editorial stack for text-heavy surfaces."}
  ]

  @defaults %{
    light: List.first(@light_themes).tokens,
    dark: List.first(@dark_themes).tokens,
    radius: "0.5rem",
    density: "compact",
    font: ~s("Inter", ui-sans-serif, system-ui, sans-serif)
  }

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Theming - lantern-ui")}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        defaults_json: Jason.encode!(@defaults),
        presets_json: Jason.encode!(@theme_presets),
        light_themes: @light_themes,
        dark_themes: @dark_themes,
        token_rows: @token_rows,
        radius_options: @radius_options,
        density_options: @density_options,
        font_options: @font_options
      )

    ~H"""
    <LanternDemoWeb.DocsShell.shell current="theming" theme="system" density="compact">
      <article
        id="theming-page"
        phx-hook="DemoTheming"
        data-defaults={@defaults_json}
        data-presets={@presets_json}
        class="docs-body docs-body-wide"
      >
        <h1>Theming</h1>
        <p>Runtime token overrides, persisted locally.</p>

        <section class="docs-section">
          <h2 class="docs-section-title">Theme</h2>
          <p class="docs-section-desc">
            Choose a complete semantic color theme independently for light and dark mode.
          </p>
          <div class="docs-demo">
            <div class="docs-theme-grid">
              <.theme_column title="Light themes" mode="light" themes={@light_themes} />
              <.theme_column title="Dark themes" mode="dark" themes={@dark_themes} />
            </div>
          </div>
        </section>

        <section class="docs-section">
          <details class="docs-customize">
            <summary>Customize tokens</summary>
            <div class="docs-demo docs-customize-body">
              <Tabs.tabs id="theme-token-tabs" data-theme-mode-tabs>
                <Tabs.tabs_list active_tab="light" size="sm">
                  <:tab name="light">Light</:tab>
                  <:tab name="dark">Dark</:tab>
                </Tabs.tabs_list>
              </Tabs.tabs>

              <.token_editor mode="light" rows={@token_rows} hidden={false} />
              <.token_editor mode="dark" rows={@token_rows} hidden={true} />
            </div>
          </details>
        </section>

        <section class="docs-section">
          <h2 id="font-title" class="docs-section-title">Font</h2>
          <p class="docs-section-desc">Set the shared Lantern body font token.</p>
          <div class="docs-demo">
            <Radio.radio
              id="theme-font"
              name="theme_font"
              value={@defaults.font}
              variant="cards"
              aria-labelledby="font-title"
              data-theme-key="font"
            >
              <:radio
                :for={{label, value, description} <- @font_options}
                value={value}
                label={label}
                description={description}
              />
            </Radio.radio>
          </div>
        </section>

        <section class="docs-section">
          <h2 id="radius-title" class="docs-section-title">Radius</h2>
          <p class="docs-section-desc">Adjust the shared radius token used by Lantern controls.</p>
          <div class="docs-demo">
            <Radio.radio
              id="theme-radius"
              name="theme_radius"
              value="0.5rem"
              variant="cards"
              aria-labelledby="radius-title"
              data-theme-key="radius"
            >
              <:radio
                :for={{label, value} <- @radius_options}
                value={value}
                label={label}
                description={value}
              />
            </Radio.radio>
          </div>
        </section>

        <section class="docs-section">
          <h2 id="density-title" class="docs-section-title">Density</h2>
          <p class="docs-section-desc">Switch between the compact demo scale and roomier controls.</p>
          <div class="docs-demo">
            <Radio.radio
              id="theme-density"
              name="theme_density"
              value="compact"
              variant="cards"
              aria-labelledby="density-title"
              data-theme-key="density"
            >
              <:radio
                :for={{label, value} <- @density_options}
                value={value}
                label={label}
                description={density_description(value)}
              />
            </Radio.radio>
          </div>
        </section>

        <section class="docs-section">
          <h2 class="docs-section-title">Preview</h2>
          <p class="docs-section-desc">
            The light and dark panes are scoped theme previews, so both mode choices are visible.
          </p>
          <div class="docs-preview-grid">
            <.preview_cluster tone="light" label="Light" prefix="preview-light" />
            <.preview_cluster tone="dark" label="Dark" prefix="preview-dark" />
          </div>
        </section>

        <div class="docs-actions-row">
          <Button.button variant="outline" data-theme-reset>
            Reset to defaults
          </Button.button>
        </div>

        <style>
          .docs-body { max-width: 980px; }
          .docs-body h1 { font-size: 1.5rem; font-weight: 700; letter-spacing: 0; margin: 0 0 .4rem; }
          .docs-body > p { font-size: .875rem; color: var(--lantern-fg-muted); margin: 0 0 1.25rem; line-height: 1.6; }
          .docs-section { margin-top: 2.25rem; }
          .docs-section-title { font-size: 1.05rem; font-weight: 650; letter-spacing: 0; margin: 0 0 .25rem; color: var(--lantern-fg); }
          .docs-section-desc { font-size: .85rem; color: var(--lantern-fg-muted); margin: 0 0 .9rem; }
          .docs-demo { border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-lg); padding: 1.25rem; background: var(--lantern-surface-raised); display: flex; flex-direction: column; gap: .875rem; }
          .docs-row { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
          .docs-theme-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1rem; }
          .docs-theme-column { min-width: 0; }
          .docs-theme-heading { margin: 0 0 .65rem; color: var(--lantern-fg); font-size: .9rem; font-weight: 650; }
          .docs-theme-stack { display: grid; gap: .625rem; }
          .docs-theme-card { width: 100%; min-height: 5.5rem; display: grid; grid-template-columns: 5.5rem minmax(0, 1fr); gap: .85rem; align-items: stretch; padding: .65rem; text-align: left; color: var(--lantern-fg); background: var(--theme-surface); border: 1px solid var(--theme-border); border-radius: var(--lantern-radius-md); cursor: pointer; box-shadow: var(--lantern-shadow); transition: border-color var(--lantern-duration) var(--lantern-ease), box-shadow var(--lantern-duration) var(--lantern-ease), transform var(--lantern-duration) var(--lantern-ease); }
          .docs-theme-card:hover { transform: translateY(-1px); border-color: var(--theme-accent); }
          .docs-theme-card-selected { box-shadow: 0 0 0 2px var(--lantern-surface), 0 0 0 5px var(--lantern-ring), var(--lantern-shadow-md); }
          .docs-theme-swatches { display: grid; grid-template-columns: repeat(2, 1fr); gap: .25rem; border-radius: calc(var(--lantern-radius-md) - 2px); overflow: hidden; border: 1px solid var(--theme-border); background: var(--theme-surface); }
          .docs-theme-swatch { min-height: 1.8rem; }
          .docs-theme-copy { min-width: 0; align-self: center; }
          .docs-theme-copy strong { display: block; color: var(--theme-fg); font-size: .88rem; line-height: 1.25; }
          .docs-theme-copy span { display: block; margin-top: .25rem; color: color-mix(in oklab, var(--theme-fg) 68%, var(--theme-surface)); font-size: .75rem; line-height: 1.35; }
          .docs-customize { margin-top: 2.25rem; }
          .docs-customize summary { color: var(--lantern-fg); cursor: pointer; font-size: 1.05rem; font-weight: 650; letter-spacing: 0; }
          .docs-customize-body { margin-top: .9rem; }
          .docs-token-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: .65rem .8rem; }
          .docs-token-row { display: grid; grid-template-columns: minmax(7rem, 1fr) auto minmax(4.75rem, auto); gap: .65rem; align-items: center; padding: .55rem .65rem; border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-md); background: var(--lantern-surface); }
          .docs-token-label { color: var(--lantern-fg); font-size: .8rem; font-weight: 560; line-height: 1.25; }
          .docs-token-color { width: 2.1rem; height: 2.1rem; padding: 0; border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-sm); background: transparent; cursor: pointer; }
          .docs-token-value { color: var(--lantern-fg-muted); font-family: var(--lantern-font-mono); font-size: .7rem; justify-self: end; }
          .docs-preview-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; }
          .docs-preview-pane { border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-lg); padding: 1.25rem; background: var(--lantern-surface-raised); color: var(--lantern-fg); display: flex; flex-direction: column; gap: .875rem; }
          .docs-preview-head { display: flex; align-items: center; justify-content: space-between; gap: 1rem; }
          .docs-preview-head strong { font-size: .9rem; }
          .docs-control-stack { display: grid; gap: .75rem; }
          .docs-actions-row { margin-top: 2rem; display: flex; justify-content: flex-start; }

          @media (max-width: 760px) {
            .docs-theme-grid,
            .docs-token-grid { grid-template-columns: 1fr; }
          }
        </style>
      </article>
    </LanternDemoWeb.DocsShell.shell>
    """
  end

  attr(:title, :string, required: true)
  attr(:mode, :string, required: true)
  attr(:themes, :list, required: true)

  defp theme_column(assigns) do
    ~H"""
    <div class="docs-theme-column">
      <h3 class="docs-theme-heading">{@title}</h3>
      <div class="docs-theme-stack">
        <button
          :for={theme <- @themes}
          type="button"
          class="docs-theme-card"
          style={preset_style(theme.tokens)}
          aria-pressed="false"
          data-theme-preset={"#{@mode}:#{theme.id}"}
        >
          <span class="docs-theme-swatches" aria-hidden="true">
            <span class="docs-theme-swatch" style={"background: #{theme.tokens.accent};"}></span>
            <span class="docs-theme-swatch" style={"background: #{theme.tokens.surface};"}></span>
            <span class="docs-theme-swatch" style={"background: #{theme.tokens.surface_sunken};"}></span>
            <span class="docs-theme-swatch" style={"background: #{theme.tokens.fg};"}></span>
          </span>
          <span class="docs-theme-copy">
            <strong>{theme.name}</strong>
            <span>{theme.description}</span>
          </span>
        </button>
      </div>
    </div>
    """
  end

  attr(:mode, :string, required: true)
  attr(:rows, :list, required: true)
  attr(:hidden, :boolean, default: false)

  defp token_editor(assigns) do
    ~H"""
    <div data-theme-token-panel={@mode} hidden={@hidden}>
      <div class="docs-token-grid">
        <label :for={row <- @rows} class="docs-token-row">
          <span class="docs-token-label">{row.label}</span>
          <input
            type="color"
            value="#000000"
            class="docs-token-color"
            data-theme-mode={@mode}
            data-theme-token={row.key}
            aria-label={"#{@mode} #{row.label}"}
          />
          <span class="docs-token-value" data-theme-mode={@mode} data-theme-token-value={row.key}>
            #000000
          </span>
        </label>
      </div>
    </div>
    """
  end

  attr(:tone, :string, required: true)
  attr(:label, :string, required: true)
  attr(:prefix, :string, required: true)

  defp preview_cluster(assigns) do
    ~H"""
    <div class={["docs-preview-pane", @tone]} data-theme-preview={@tone}>
      <div class="docs-preview-head">
        <strong>{@label}</strong>
        <Badge.badge color="accent">Accent</Badge.badge>
      </div>

      <div class="docs-row">
        <Button.button variant="solid">Solid</Button.button>
        <Button.button variant="soft">Soft</Button.button>
        <Button.button variant="outline">Outline</Button.button>
      </div>

      <div class="docs-row">
        <Badge.badge color="primary" variant="solid">Primary</Badge.badge>
        <Badge.badge color="accent">Accent</Badge.badge>
        <Badge.badge color="success">Live</Badge.badge>
      </div>

      <div class="docs-control-stack">
        <Checkbox.checkbox
          id={"#{@prefix}-checkbox"}
          name={"#{@prefix}_checkbox"}
          checked
          label="Selected option"
          description="Uses the current control density."
        />
        <Switch.switch
          id={"#{@prefix}-switch"}
          name={"#{@prefix}_switch"}
          checked
          label="Enabled"
        />
        <Select.select
          id={"#{@prefix}-select"}
          name={"#{@prefix}_select"}
          value="active"
          options={[{"Active", "active"}, {"Paused", "paused"}, {"Queued", "queued"}]}
          label="Status"
        />
      </div>

      <Alert.alert color="info" title="Theme applied">
        This preview reads the same runtime Lantern tokens as the rest of the demo.
      </Alert.alert>
    </div>
    """
  end

  defp density_description("compact"), do: "Dense demo controls"
  defp density_description("comfortable"), do: "Roomier controls"

  defp preset_style(tokens) do
    [
      "--theme-accent: #{tokens.accent}",
      "--theme-border: #{tokens.border}",
      "--theme-fg: #{tokens.fg}",
      "--theme-surface: #{tokens.surface}"
    ]
    |> Enum.join("; ")
  end
end
