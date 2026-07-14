# Spec: theming page v2 — full theme system (rebuild of /components/theming)

## 1. Objective

Rebuild the demo theming page from an accent picker into a real theme system,
modeled on the reference implementation in
~/Sites/flicker/lib/flicker/settings/theme.ex (READ IT and
~/Sites/flicker/lib/flicker_web/live/admin_site_settings_live/index.ex first —
that admin branding panel is the robustness bar): named per-mode themes
carrying a COMPLETE semantic token set, plus a per-token customizer, fonts,
radius, and density. Also REMOVE the meaningless "Environment" select from the
preview panes (decorative filler; it confused the user).

Everything stays client-side through the existing LanternTheme hook
(deps/lantern_ui — it maps arbitrary keys in {light: %{...}, dark: %{...}} to
--lantern-<key> vars, so a full token map Just Works).

## 2. Files to modify (under examples/demo/)

- lib/lantern_demo_web/live/theming_live.ex — rebuild content per section 3.
- priv/static/app.js — extend the DemoTheming hook per section 4.
- Nothing else. (Router/nav/theme-mount already exist from v1.)

## 3. Page design

Keep: h1/intro, Radius section, Density section, dual light/dark preview panes
(REMOVE the Environment select from them; keep buttons/badges/checkbox/switch/
select/alert examples).

Replace both accent sections with:

### "Theme" section — named presets per mode
Two columns (Light themes / Dark themes). Each lists 5 named theme cards
(swatch strip of its accent+surface+fg colors, name, small description),
selectable (ring + aria-pressed). Define the presets as module attributes —
each is a COMPLETE lantern token map for its mode with these keys (underscore
form; the hook converts to --lantern-*):

  accent, accent_fg, fg, fg_muted, fg_subtle, surface, surface_raised,
  surface_sunken, surface_hover, border, border_strong, danger, success, warning

Light presets: Coral (the current defaults from
deps/lantern_ui/priv/static/lantern_ui_theme.css — read it for exact values),
Ocean (blue accent, cool zinc surfaces), Forest (green accent, warm-neutral
surfaces), Plum (violet accent), Paper (amber accent, warm off-white surfaces
like #faf9f7). Dark presets: Coral Dark (current defaults), Midnight (blue
accent, blue-black surfaces like #0b1020/#111730), Forest Dark, Plum Dark,
Slate (neutral accent #94a3b8-ish, cool dark surfaces). Choose tasteful,
AA-contrast values; keep status colors consistent across presets (reuse the
defaults) except where the preset's mood justifies a tweak.

Selecting a preset replaces that mode's ENTIRE token map in the config
(config.light = preset tokens) — not a merge — so switching presets is clean.

### "Customize" section — per-token editor
A details/summary (collapsed by default) titled "Customize tokens". Inside:
a mode toggle (Light | Dark tabs — lantern_ui Tabs, phx-click free, the
DemoTheming hook handles switching which editor column is visible via
data attrs) and a grid of the 14 token rows: label + <input type="color">
+ current value text. Editing a token merges just that key into the current
config for that mode (on top of whatever preset/custom state exists).
NOTE oklch values can't populate <input type="color">; the hook should read
the RESOLVED computed value: getComputedStyle(document.documentElement)
.getPropertyValue('--lantern-<key>') — set the color input from a canvas-
normalized hex (draw to canvas 1x1 and read back, or use a hidden probe div
with background set to the var and getComputedStyle(...).backgroundColor →
rgb → hex). Implement a small rgbToHex helper. Color inputs then emit hex
values, which is fine as token values.

### "Font" section
Radio cards (3): System (current default stack), Grotesque
("Space Grotesk", "Inter", system-ui fallback stack), Serif ("Iowan Old Style",
Georgia, serif). Sets token font (maps to --lantern-font). Mono stays.

### Reset
Keep the reset button (clears everything via {reset: true}).

## 4. DemoTheming hook changes (priv/static/app.js)

- Presets: page embeds them as JSON in data-presets on the hook root
  (ThemingLive Jason.encode!s the module attribute); hook reads it.
- [data-theme-preset="light:coral"] click → config.light = presets["light:coral"]
  (full replace of that mode), keep other keys, dispatch lantern:set-theme.
- [data-theme-key]/[data-theme-value] handling stays for radius/density/font
  (font buttons: data-theme-key="light.font" AND "dark.font"? No — font is
  shared: set both config.light.font and config.dark.font from one control).
- Token editor inputs: data-theme-token="<key>" + the active mode from the
  tabs; change → merge config[mode][key] = value; dispatch.
- Selected-state sync on mounted and after every change (presets ring only
  when config[mode] deep-equals the preset map; token inputs repopulate from
  computed styles; radius/density/font as in v1).

## 5. Constraints (MANDATORY)

- Client-side only; no LiveView theme state or handle_events for theming.
- Read the LanternTheme hook + lantern_ui_theme.css defaults FIRST; exact
  default values for Coral presets come from that css file.
- Imitate existing page structure/classes; one alias per line; scoped <style>
  in theming_live.ex for new classes (docs-theme-card etc.).
- mix format ONLY the files you modified. Never bare `mix format`.
- Do not touch other pages, router, docs_shell, config.

## 6. Verification (from examples/demo; all must pass)

    mix deps.get
    mix compile --warnings-as-errors
    node --check priv/static/app.js
