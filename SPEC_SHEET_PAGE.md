# Spec: add a "Sheet" component reference page to the lantern demo

## 1. Objective

The `sheet` component (LanternUI.Components.Sheet, a slide-over/drawer) exists
in lantern_ui but has NO demo page, so it's missing from the sidebar. Add a
reference page for it, matching the existing component pages exactly (nav
entry + icon + an article of `demo_section` blocks with live previews +
snippets). Work in the demo app at examples/demo (repo root is the cwd; the app
is under examples/demo/).

## 2. Files to modify (under examples/demo/)

### a) lib/lantern_demo_web/components/docs_shell.ex
- In `@component_groups`, the "Components" group list, add `{"sheet", "Sheet"}`
  IMMEDIATELY AFTER `{"modal", "Modal"}` (sheet is modal-family).
- In the `@icons` map, add: `"sheet" => "arrow-right",` (use exactly that icon
  name — it exists; do NOT invent an icon).

### b) lib/lantern_demo_web/live/components_live.ex
- Add `alias LanternUI.Components.Sheet` with the other aliases (one per line,
  keep alphabetical among the existing `alias LanternUI.Components.*` lines).
- Add a `<article :if={@current == "sheet"} class="docs-body">` block. Put it
  IMMEDIATELY BEFORE the existing `<article :if={@current == "sparkline"} ...>`
  block (same location the other recently-added articles use). Structure it
  exactly like the other articles: an `<h1>Sheet</h1>`, a one-sentence `<p>`
  intro, then `<.demo_section>` blocks (see §3).

## 3. Page content — the demo_section blocks

`demo_section` is a private component already defined in this file:
`attr :title`, `attr :description` (optional), `attr :code` (required string),
`slot :inner_block`. It renders: title, description, a `.docs-demo` preview
(the inner_block), and a `<pre class="docs-code">` showing `code`.

The sheet opens/closes via the shared dialog runtime:
`LanternUI.open_dialog("<id>")` / `LanternUI.close_dialog("<id>")` (JS commands,
usable in `phx-click`). The `<Sheet.sheet id="..." ...>` element renders hidden
until opened. Each demo needs a trigger button + its own sheet element with a
UNIQUE id.

Add these sections:

1. title="Trigger & content", description="A button opens the sheet; it shares
   the modal's open_dialog/close_dialog runtime.":
   - inner_block: a `<Button.button phx-click={LanternUI.open_dialog("sheet-basic")}>Open sheet</Button.button>`
     followed by:
     ```
     <Sheet.sheet id="sheet-basic" title="Edit settings">
       <p>Sheet body content goes here. Focus is trapped; Escape or the
       backdrop closes it.</p>
       <:footer>
         <Button.button variant="outline" size="sm" phx-click={LanternUI.close_dialog("sheet-basic")}>Cancel</Button.button>
         <Button.button variant="solid" size="sm" phx-click={LanternUI.close_dialog("sheet-basic")}>Save</Button.button>
       </:footer>
     </Sheet.sheet>
     ```
   - code: a ~S""" string showing the bare-component version (`<.sheet id="settings" title="Edit settings">…<:footer>…</:footer></.sheet>` plus the `<.button phx-click={open_dialog("settings")}>` trigger).

2. title="Placement", description="Slides in from any edge — left, right (default), top, or bottom.":
   - inner_block: a `<div class="docs-row">` with four buttons, one per placement,
     each opening a distinct sheet id (sheet-left, sheet-right, sheet-top,
     sheet-bottom); label each button with the placement name. After the row,
     render four `<Sheet.sheet>` elements with matching ids and
     `placement={"left"|"right"|"top"|"bottom"}` and `title` = the placement,
     each with a short `<p>` body.
   - code: a ~S""" showing `<.sheet id="nav" placement="left">…</.sheet>` etc.
     (abbreviated is fine).

3. title="Prevent closing", description="prevent_closing removes the close
   button and disables Escape/backdrop dismissal — the sheet must be closed by
   an explicit action.":
   - inner_block: a button opening `sheet-locked`, plus:
     ```
     <Sheet.sheet id="sheet-locked" title="Confirm" prevent_closing>
       <p>You must choose an action.</p>
       <:footer>
         <Button.button variant="solid" size="sm" phx-click={LanternUI.close_dialog("sheet-locked")}>Done</Button.button>
       </:footer>
     </Sheet.sheet>
     ```
   - code: the ~S""" equivalent.

## 4. Constraints (MANDATORY)

- Match the existing articles' structure/classes precisely (docs-body,
  docs-row, demo_section). Look at the `@current == "modal"` and
  `@current == "toast"` articles in this same file as the closest models.
- `Button` and `Sheet` are the components used — `Button` is already aliased;
  add the `Sheet` alias. Use module-qualified calls (`Sheet.sheet`,
  `Button.button`) like the other articles do.
- One alias per line; no grouped aliases; no new deps.
- Do NOT touch any other page, the data-table page, the theming page, router,
  endpoint, or config.
- `mix format` ONLY the two files you modified:
    mix format lib/lantern_demo_web/components/docs_shell.ex lib/lantern_demo_web/live/components_live.ex
  Do NOT run a bare `mix format`.

## 5. Verification (run from examples/demo; all must pass)

    mix compile --warnings-as-errors
