# Spec: theming page — light/dark theme selection + customization, persisted

## 1. Objective

A branding-panel-style theming page at /components/theming in the lantern demo
(Phoenix LiveView app at examples/demo). The user picks an accent color for
LIGHT mode and (separately) for DARK mode from preset swatches or a custom
color input, plus radius and density controls. Changes apply INSTANTLY across
the whole demo and PERSIST across reloads — all client-side via the existing
`LanternTheme` hook from the lantern_ui dep (already available; read
deps/lantern_ui/lib/lantern_ui/components/theme.ex and the LanternTheme hook
in deps/lantern_ui/priv/static/lantern_ui_hooks.js FIRST — the page mostly
just dispatches the `lantern:set-theme` CustomEvent).

## 2. Files to create/modify (under examples/demo/ unless noted)

Create:
- lib/lantern_demo_web/live/theming_live.ex (LanternDemoWeb.ThemingLive)

Modify:
- lib/lantern_demo_web/router.ex — add BEFORE the "/components/:slug" route:
    live("/components/theming", ThemingLive)
- lib/lantern_demo_web/components/docs_shell.ex —
  - Mount the hook once for the whole demo: inside the app_shell, right after
    the opening (next to where render_slot(@inner_block) area starts — put it
    as the FIRST child of the main content), render:
      <LanternUI.Components.Theme.theme />
    (add the alias; one alias per line).
  - Nav: add a new group {"Theming", [{"theming", "Theming"}]} after "Layout";
    icon map: "theming" => "sparkles".
- lib/lantern_demo_web/live/components_live.ex — no changes (theming has its
  own LiveView; the :slug route never sees "theming" because the explicit
  route matches first).

## 3. Page design (ThemingLive)

Renders inside LanternDemoWeb.DocsShell.shell (current="theming",
follow data_table_demo.ex's structure). Content:

- h1 "Theming"; intro paragraph: runtime token overrides, persisted locally.
- Section "Light mode accent": a row of 6 preset swatch buttons (coral
  oklch(0.637 0.192 38) — the default, blue oklch(0.546 0.245 262.881), violet
  oklch(0.606 0.25 292.717), green oklch(0.627 0.17 149.214), rose
  oklch(0.645 0.246 16.439), amber oklch(0.666 0.179 58.318)) + an
  <input type="color"> for custom. Each swatch is a button with the color as
  background (style attr), a ring when selected.
- Section "Dark mode accent": same six presets (use the slightly lighter
  variants: coral oklch(0.685 0.182 39), blue oklch(0.623 0.214 259.815),
  violet oklch(0.673 0.218 293.336), green oklch(0.696 0.17 162.48), rose
  oklch(0.712 0.194 13.428), amber oklch(0.769 0.188 70.08)) + custom color
  input.
- Section "Radius": lantern_ui radio (cards variant) with options None 0rem /
  Small 0.375rem / Default 0.5rem / Large 0.75rem / Round 1rem.
- Section "Density": radio cards compact / comfortable.
- Section "Preview": a live cluster showing themed components — a few
  Button.button variants, Badge.badge colors, a Checkbox + Switch, one
  Select.select, an Alert.alert — so changes are visible immediately on-page.
- A "Reset to defaults" Button.

## 4. State & behavior — ALL CLIENT-SIDE (this is the key constraint)

The LiveView holds NO theme state and has NO handle_event for theme changes.
Every control drives the hook directly with a small page-local hook:

- Add hook `DemoTheming` to examples/demo/priv/static/app.js (that file
  defines TurnstileWidget already — follow its style; register in the hooks
  object). The ThemingLive content root has phx-hook="DemoTheming"
  id="theming-page" data-defaults={...}.
- All swatches/radios/inputs carry data attributes:
  data-theme-key="light.accent" | "dark.accent" | "radius" | "density",
  data-theme-value={value} (color inputs use their input value).
- DemoTheming hook: on click of [data-theme-key] buttons / change of inputs,
  read current saved config from localStorage("lui-theme") (JSON or null),
  deep-merge the new key path, then
  window.dispatchEvent(new CustomEvent("lantern:set-theme", {detail: config}))
  — the LanternTheme hook does persistence + application. For reset button
  (data-theme-reset): dispatch with {detail: {reset: true}}.
- Selected-state ring on swatches: the hook re-reads config after each change
  and sets aria-pressed / a "selected" class on the matching swatches; on
  mounted() it does the same so the UI reflects persisted state after reload.

## 5. Constraints (MANDATORY)

- Read the LanternTheme hook implementation first; match its config shape
  exactly ({light: {accent: v}, dark: {accent: v}, radius: v, density: v}).
- Imitate existing files precisely (docs_shell nav pattern, article/docs-body
  classes, demo_section if useful). One alias per line. No new deps.
- Swatch styles: small scoped <style> block in theming_live.ex like other
  pages do (classes: docs-swatch, docs-swatch-selected, docs-swatch-row).
- mix format ONLY files you created/modified — never bare `mix format`.
- Do not touch: components_live.ex, data-table page, config/*, endpoint.

## 6. Verification (from examples/demo; all must pass)

    mix deps.get
    mix compile --warnings-as-errors
    node --check priv/static/app.js
