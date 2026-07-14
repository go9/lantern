# Spec: preview-per-feature docs sections (fluxonui.com style)

## 1. Objective

Restructure every component reference page in the lantern demo so each FEATURE
gets its own section: an h2 heading, a one-line description, a rendered preview
card, and the exact heex snippet for that preview directly beneath it (like
https://fluxonui.com/components/alert). Replace the current one-blob-demo +
one-snippet-per-page format.

## 2. Files to modify (all under examples/demo/)

- lib/lantern_demo_web/live/components_live.ex — the only substantive file.
  1. Add a private function component at the bottom of the module:

         attr(:title, :string, required: true)
         attr(:description, :string, default: nil)
         attr(:code, :string, required: true)
         slot(:inner_block, required: true)

         defp demo_section(assigns) do
           ~H"""
           <section class="docs-section">
             <h2 class="docs-section-title">{@title}</h2>
             <p :if={@description} class="docs-section-desc">{@description}</p>
             <div class="docs-demo">{render_slot(@inner_block)}</div>
             <pre class="docs-code"><code>{@code}</code></pre>
           </section>
           """
         end

  2. Rework EVERY component article (button, icon, input, datetime-field,
     calendar, date-picker, checkbox, modal, dropdown, breadcrumb, empty-state,
     switch, radio, textarea, alert, separator, tooltip, toast, table,
     pagination, tabs, select, badge — NOT app-shell, NOT data-table, NOT the
     chart pages) into 2–5 demo_section blocks per page. Split by feature:
     variants / colors / sizes / states / slots / special behaviors. Each
     section's `code` attr is a ~S""" string showing exactly what that
     section's preview renders (bare component names, e.g. <.alert ...>).
     Move each existing example into the appropriate section; ADD sections
     where a feature exists but has no example (e.g. select: separate sections
     for basic, multiple, searchable, native, FormField/error states; badge:
     colors, variants, sizes; alert: colors, title+close, custom icon; switch:
     basic/sizes/label+description/disabled; etc. Use the component moduledocs
     in deps/lantern_ui/lib/lantern_ui/components/*.ex as the feature list).
  3. The page h1 + intro paragraph stay; the old top-level @snippets map
     entries become unused for these pages — REMOVE entries that no longer
     have a reader, keep the map for pages you don't touch (data-table,
     app-shell, charts).
  4. Add the section CSS to the existing <style> block in this file (or the
     docs style location used today):
       .docs-section { margin-top: 2.25rem; }
       .docs-section-title { font-size: 1.05rem; font-weight: 650; letter-spacing: -0.01em; margin: 0 0 0.25rem; color: var(--lantern-fg); }
       .docs-section-desc { font-size: 0.85rem; color: var(--lantern-fg-muted); margin: 0 0 0.9rem; }
     (If articles' styles live in docs_shell.ex, put it there instead — match
     wherever .docs-demo is defined.)

## 3. Interfaces

No component API changes. Pure demo restructure.

## 4. Constraints (MANDATORY)

- Keep every EXISTING example working — reorganize, don't delete functionality
  (the toast playground buttons, tooltip hover examples, select multi/search
  examples etc. all survive inside their sections).
- Do not touch: data-table page, app-shell page, chart pages, DemoLive,
  router, endpoint, layouts, application.ex, config/*.
- mix format ONLY the files you modified:
    mix format lib/lantern_demo_web/live/components_live.ex lib/lantern_demo_web/components/docs_shell.ex
  Do NOT run bare `mix format`.
- One alias per line if you add aliases. No new deps.

## 5. Verification (run from examples/demo; all must pass)

    mix deps.get
    mix compile --warnings-as-errors
