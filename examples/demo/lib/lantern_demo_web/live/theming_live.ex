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

  @light_presets [
    {"Coral", "oklch(0.637 0.192 38)"},
    {"Blue", "oklch(0.546 0.245 262.881)"},
    {"Violet", "oklch(0.606 0.25 292.717)"},
    {"Green", "oklch(0.627 0.17 149.214)"},
    {"Rose", "oklch(0.645 0.246 16.439)"},
    {"Amber", "oklch(0.666 0.179 58.318)"}
  ]

  @dark_presets [
    {"Coral", "oklch(0.685 0.182 39)"},
    {"Blue", "oklch(0.623 0.214 259.815)"},
    {"Violet", "oklch(0.673 0.218 293.336)"},
    {"Green", "oklch(0.696 0.17 162.48)"},
    {"Rose", "oklch(0.712 0.194 13.428)"},
    {"Amber", "oklch(0.769 0.188 70.08)"}
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

  @defaults %{
    light: %{accent: "oklch(0.637 0.192 38)"},
    dark: %{accent: "oklch(0.685 0.182 39)"},
    radius: "0.5rem",
    density: "compact"
  }

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Theming - lantern-ui")}
  end

  def render(assigns) do
    assigns =
      assign(assigns,
        defaults_json: Jason.encode!(@defaults),
        light_presets: @light_presets,
        dark_presets: @dark_presets,
        radius_options: @radius_options,
        density_options: @density_options
      )

    ~H"""
    <LanternDemoWeb.DocsShell.shell current="theming" theme="system" density="compact">
      <article
        id="theming-page"
        phx-hook="DemoTheming"
        data-defaults={@defaults_json}
        class="docs-body docs-body-wide"
      >
        <h1>Theming</h1>
        <p>Runtime token overrides, persisted locally.</p>

        <section class="docs-section">
          <h2 class="docs-section-title">Light mode accent</h2>
          <p class="docs-section-desc">
            Choose the accent token used when Lantern is rendering in light mode.
          </p>
          <div class="docs-demo">
            <div class="docs-swatch-row" aria-label="Light mode accent presets">
              <button
                :for={{name, value} <- @light_presets}
                type="button"
                class="docs-swatch"
                style={"background: #{value};"}
                title={name}
                aria-label={"#{name} light accent"}
                aria-pressed="false"
                data-theme-key="light.accent"
                data-theme-value={value}
              >
                <span>{name}</span>
              </button>

              <label class="docs-color-input">
                <span>Custom</span>
                <input type="color" value="#d85f3f" data-theme-key="light.accent" />
              </label>
            </div>
          </div>
        </section>

        <section class="docs-section">
          <h2 class="docs-section-title">Dark mode accent</h2>
          <p class="docs-section-desc">
            Choose the matching accent token for dark mode and system-dark previews.
          </p>
          <div class="docs-demo">
            <div class="docs-swatch-row" aria-label="Dark mode accent presets">
              <button
                :for={{name, value} <- @dark_presets}
                type="button"
                class="docs-swatch"
                style={"background: #{value};"}
                title={name}
                aria-label={"#{name} dark accent"}
                aria-pressed="false"
                data-theme-key="dark.accent"
                data-theme-value={value}
              >
                <span>{name}</span>
              </button>

              <label class="docs-color-input">
                <span>Custom</span>
                <input type="color" value="#ef7854" data-theme-key="dark.accent" />
              </label>
            </div>
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
            The light and dark panes are scoped theme previews, so both accent choices are visible.
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
          .docs-body { max-width: 920px; }
          .docs-body h1 { font-size: 1.5rem; font-weight: 700; letter-spacing: 0; margin: 0 0 .4rem; }
          .docs-body > p { font-size: .875rem; color: var(--lantern-fg-muted); margin: 0 0 1.25rem; line-height: 1.6; }
          .docs-section { margin-top: 2.25rem; }
          .docs-section-title { font-size: 1.05rem; font-weight: 650; letter-spacing: 0; margin: 0 0 .25rem; color: var(--lantern-fg); }
          .docs-section-desc { font-size: .85rem; color: var(--lantern-fg-muted); margin: 0 0 .9rem; }
          .docs-demo { border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-lg); padding: 1.25rem; background: var(--lantern-surface-raised); display: flex; flex-direction: column; gap: .875rem; }
          .docs-row { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
          .docs-swatch-row { display: flex; flex-wrap: wrap; align-items: center; gap: .7rem; }
          .docs-swatch { width: 2.25rem; height: 2.25rem; border: 1px solid color-mix(in oklab, var(--lantern-border) 80%, black); border-radius: 999px; box-shadow: inset 0 0 0 1px rgb(255 255 255 / .28), var(--lantern-shadow); cursor: pointer; transition: box-shadow var(--lantern-duration) var(--lantern-ease), transform var(--lantern-duration) var(--lantern-ease); }
          .docs-swatch:hover { transform: translateY(-1px); }
          .docs-swatch span { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; }
          .docs-swatch-selected { box-shadow: 0 0 0 2px var(--lantern-surface), 0 0 0 5px var(--lantern-ring), var(--lantern-shadow-md); }
          .docs-color-input { display: inline-flex; align-items: center; gap: .5rem; min-height: var(--lantern-control-h); color: var(--lantern-fg-muted); font-size: var(--lantern-text); }
          .docs-color-input input { width: 2.35rem; height: 2.35rem; padding: 0; border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-md); background: transparent; cursor: pointer; }
          .docs-preview-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; }
          .docs-preview-pane { border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-lg); padding: 1.25rem; background: var(--lantern-surface-raised); color: var(--lantern-fg); display: flex; flex-direction: column; gap: .875rem; }
          .docs-preview-head { display: flex; align-items: center; justify-content: space-between; gap: 1rem; }
          .docs-preview-head strong { font-size: .9rem; }
          .docs-control-stack { display: grid; gap: .75rem; }
          .docs-actions-row { margin-top: 2rem; display: flex; justify-content: flex-start; }
        </style>
      </article>
    </LanternDemoWeb.DocsShell.shell>
    """
  end

  attr(:tone, :string, required: true)
  attr(:label, :string, required: true)
  attr(:prefix, :string, required: true)

  defp preview_cluster(assigns) do
    ~H"""
    <div class={["docs-preview-pane", @tone]}>
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
          value="production"
          options={[{"Production", "production"}, {"Staging", "staging"}, {"Preview", "preview"}]}
          label="Environment"
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
end
