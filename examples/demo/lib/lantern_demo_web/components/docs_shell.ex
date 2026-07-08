defmodule LanternDemoWeb.DocsShell do
  @moduledoc """
  The shared ecosystem shell: fixed left sidebar (tools + component nav) with
  the page's content in the main column. Both the DB-viewer demo (`/`) and the
  components reference (`/components/*`) render inside it, so the whole lantern
  ecosystem reads as one product.

  `current` picks the highlighted nav item: `"db"` for the DB viewer, or a
  component slug. `theme` is `"system" | "light" | "dark"` — dark adds the
  `.dark` class that flips the `--lantern-*` tokens for the whole shell.
  """
  use Phoenix.Component

  @component_groups [
    {"Components",
     [
       {"button", "Button"},
       {"icon", "Icon"},
       {"input", "Input"},
       {"datetime-field", "Datetime field"},
       {"calendar", "Calendar"},
       {"date-picker", "Date & time pickers"}
     ]},
    {"Charts",
     [
       {"area-chart", "Area chart"},
       {"line-chart", "Line chart"},
       {"bar-chart", "Bar chart"},
       {"sparkline", "Sparkline"}
     ]}
  ]

  def component_groups, do: @component_groups

  attr(:current, :string, required: true)
  attr(:theme, :string, default: "system")
  attr(:density, :string, default: "compact")
  slot(:inner_block, required: true)

  def shell(assigns) do
    assigns = assign(assigns, :groups, @component_groups)

    ~H"""
    <div class={["docs", @theme == "dark" && "dark"]} data-lantern-density={@density}>
      <aside class="docs-side">
        <div class="docs-brand">
          <span class="docs-logo">lantern</span>
          <span class="docs-ver">
            <a href="https://hex.pm/packages/lantern_ui">hex.pm</a>
            · <a href="https://lantern-ui.hexdocs.pm">docs</a>
            · <a href="https://github.com/go9/lantern-ui">github</a>
          </span>
        </div>

        <nav class="docs-nav">
          <div class="docs-group">
            <div class="docs-group-label">Tools</div>
            <.link navigate="/" class={["docs-item", @current == "db" && "active"]}>
              DB viewer
            </.link>
            <span class="docs-item docs-soon">S3 viewer — soon</span>
          </div>
          <div :for={{group, items} <- @groups} class="docs-group">
            <div class="docs-group-label">{group}</div>
            <.link
              :for={{slug, label} <- items}
              navigate={"/components/#{slug}"}
              class={["docs-item", @current == slug && "active"]}
            >
              {label}
            </.link>
          </div>
        </nav>
      </aside>

      <main class="docs-main">
        {render_slot(@inner_block)}
      </main>

      <style>
        .docs { display: flex; min-height: 100vh; font-family: var(--lantern-font);
          background: var(--lantern-surface); color: var(--lantern-fg);
          transition: background .15s, color .15s; }
        .docs-side { width: 230px; flex-shrink: 0; position: sticky; top: 0; height: 100vh;
          overflow-y: auto; border-right: 1px solid var(--lantern-border);
          padding: 1.25rem 1rem 2rem; box-sizing: border-box;
          background: var(--lantern-surface); }
        .docs-brand { padding: 0 .5rem; margin-bottom: 1.25rem; display: flex;
          flex-direction: column; gap: .2rem; }
        .docs-logo { font-size: 1rem; font-weight: 700; letter-spacing: -.02em; }
        .docs-ver { font-size: .6875rem; color: var(--lantern-fg-subtle); }
        .docs-ver a { color: var(--lantern-fg-muted); text-decoration: none; }
        .docs-ver a:hover { color: var(--lantern-accent); }
        .docs-group { margin-bottom: 1.25rem; }
        .docs-group-label { font-size: .6875rem; font-weight: 600; text-transform: uppercase;
          letter-spacing: .05em; color: var(--lantern-fg-subtle); padding: 0 .5rem;
          margin-bottom: .25rem; }
        .docs-item { display: block; font-size: .8125rem; color: var(--lantern-fg-muted);
          text-decoration: none; padding: .3rem .5rem; border-radius: var(--lantern-radius-sm);
          line-height: 1.4; }
        .docs-item:hover { color: var(--lantern-fg); background: var(--lantern-surface-sunken); }
        .docs-item.active { color: var(--lantern-accent); font-weight: 550;
          background: var(--lantern-accent-soft); }
        .docs-soon { color: var(--lantern-fg-subtle); cursor: default; }
        .docs-soon:hover { color: var(--lantern-fg-subtle); background: none; }
        .docs-main { flex: 1; min-width: 0; padding: 1.25rem 2.5rem 5rem; box-sizing: border-box; }

        /* Embedded DB-viewer demo: strip the standalone marketing chrome so it
           reads as a tool page inside the shell (no gradient backdrop, no outer
           padding, docs-scale headline). Sandbox panels keep their own styles. */
        .docs .demo-shell { background: none; padding: 0; min-height: 0; }
        .docs .demo-shell > * { max-width: 900px; margin-left: 0; margin-right: 0; }
        .docs .demo-hero { margin-bottom: 1rem; }
        .docs .demo-title { font-size: 1.5rem; }
        .docs .demo-eyebrow { display: none; }

        @media (max-width: 760px) {
          .docs { flex-direction: column; }
          .docs-side { position: static; width: 100%; height: auto; border-right: none;
            border-bottom: 1px solid var(--lantern-border); padding-bottom: .75rem; }
          .docs-nav { display: flex; gap: 1.25rem; overflow-x: auto; }
          .docs-group { margin-bottom: 0; flex-shrink: 0; }
          .docs-main { padding: 1.25rem 1.25rem 4rem; }
        }
      </style>
    </div>
    """
  end
end
