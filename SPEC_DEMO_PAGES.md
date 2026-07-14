# Spec: demo reference pages for switch, radio, textarea, alert, separator, tooltip, toast

## 1. Objective

Add seven reference pages to the lantern demo's components section (a Phoenix
LiveView app in examples/demo), one per new lantern_ui component, following the
existing page pattern exactly. Also mount the toast system so the toast page
can fire real toasts.

## 2. Files to modify (all under examples/demo/)

- lib/lantern_demo_web/components/docs_shell.ex:
  - In @component_groups, extend the "Components" group list with:
    {"switch", "Switch"}, {"radio", "Radio"}, {"textarea", "Textarea"},
    {"alert", "Alert"}, {"separator", "Separator"}, {"tooltip", "Tooltip"},
    {"toast", "Toast"} (after {"empty-state", "Empty state"}).
  - In the @icons map add: "switch" => "check-circle", "radio" => "check-circle",
    "textarea" => "pencil-square", "alert" => "exclamation-circle",
    "separator" => "minus", "tooltip" => "information-circle",
    "toast" => "inbox".
- lib/lantern_demo_web/live/components_live.ex:
  - Add aliases (one per line, alphabetical among the existing ones):
    LanternUI.Components.Alert, LanternUI.Components.Radio,
    LanternUI.Components.Separator, LanternUI.Components.Switch,
    LanternUI.Components.Textarea, LanternUI.Components.Toast,
    LanternUI.Components.Tooltip
  - Add seven <article :if={@current == "<slug>"} class="docs-body"> blocks
    (insert before the sparkline article), mirroring the existing structure:
    h1, one-sentence p, div.docs-demo with live examples, pre.docs-code with a
    snippet from @snippets.
  - Add matching @snippets entries ("switch", "radio", "textarea", "alert",
    "separator", "tooltip", "toast") — short idiomatic HEEx examples using the
    bare component names (<.switch ...>) as consumers would after use LanternUI.
  - Toast page: render <Toast.toast_group id="demo-toasts" /> once inside the
    toast article, plus four buttons (info/success/warning/danger) with
    phx-click="demo_toast" phx-value-kind={kind}; add handle_event("demo_toast",
    %{"kind" => kind}, socket) that calls
    LanternUI.send_toast(socket, kind, "This is a #{kind} toast", title: String.capitalize(kind))
    and returns {:noreply, socket}.
  - Tooltip page: a few Tooltip.tooltip examples (top/bottom placements, one
    with :content slot containing markup, one arrow={false}).
  - Switch page: unchecked, checked, disabled, sizes sm/md/lg, one with label +
    description.
  - Radio page: a radio group (list variant) with 3 options + one cards variant.
  - Textarea page: default, with label/help_text, with errors, disabled.
  - Alert page: one per color (neutral/info/success/warning/danger), one with
    hide_close={false}, one with hide_icon.
  - Separator page: horizontal, with text, vertical (inside a flex row with
    two short paragraphs).

## 3. Interfaces

Use the components' documented attrs (read the moduledocs in
deps/lantern_ui/lib/lantern_ui/components/*.ex for switch.ex, radio.ex,
textarea.ex, alert.ex, separator.ex, tooltip.ex, toast.ex). Call them
module-qualified in this file (Switch.switch, Radio.radio, etc.) matching how
existing articles call Button.button.

## 4. Constraints

- Imitate the existing article blocks in components_live.ex precisely (class
  names docs-body / docs-demo / docs-row / docs-grid2 / docs-code).
- One alias per line; no grouped aliases. mix format at the end.
- Do not touch any other pages or the data-table demo.

## 5. Verification (must run, must pass)

    cd examples/demo && mix deps.get && mix compile --warnings-as-errors && mix format --check-formatted

Then confirm each route renders 200 by booting is NOT required — compile is the gate.
