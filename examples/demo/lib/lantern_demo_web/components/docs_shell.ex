defmodule LanternDemoWeb.DocsShell do
  @moduledoc """
  The shared ecosystem shell, built on lantern_ui's own `sidebar_layout`
  (dogfood): a collapsible sidebar (logo + grouped tool/component nav) beside
  the page content, with a topbar carrying the collapse toggle, a breadcrumb,
  and the page's own actions. Both the DB-viewer demo (`/`) and the components
  reference (`/components/*`) render inside it.

  `current` picks the highlighted nav item (`"db"` or a component slug). `theme`
  adds `.dark`; `density` sets the lantern density.
  """
  use Phoenix.Component

  alias LanternUI.Components.Breadcrumb
  alias LanternUI.Components.Icon
  alias LanternUI.Components.Layout

  @component_groups [
    {"Layout", [{"app-shell", "App shell"}]},
    {"Components",
     [
       {"button", "Button"},
       {"icon", "Icon"},
       {"input", "Input"},
       {"datetime-field", "Datetime field"},
       {"calendar", "Calendar"},
       {"date-picker", "Date & time pickers"},
       {"checkbox", "Checkbox"},
       {"modal", "Modal"},
       {"dropdown", "Dropdown menu"},
       {"breadcrumb", "Breadcrumb"},
       {"empty-state", "Empty state"}
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

  @labels Map.new([{"db", "DB viewer"} | Enum.flat_map(@component_groups, fn {_g, i} -> i end)])

  attr(:current, :string, required: true)
  attr(:theme, :string, default: "system")
  attr(:density, :string, default: "compact")
  slot(:actions)
  slot(:inner_block, required: true)

  def shell(assigns) do
    assigns =
      assigns
      |> assign(:groups, @component_groups)
      |> assign(:label, Map.get(@labels, assigns.current, "Lantern"))

    ~H"""
    <Layout.app_shell
      id="lantern-demo-shell"
      class={@theme == "dark" && "dark"}
      data-lantern-density={@density}
    >
      <:brand>
        <Icon.icon name="squares-2x2" /> <span class="lui-brand-name">lantern</span>
      </:brand>
      <:header>
        <Breadcrumb.breadcrumb aria_label="Location">
          <:item>{if @current == "db", do: "Tools", else: "Components"}</:item>
          <:item current>{@label}</:item>
        </Breadcrumb.breadcrumb>
      </:header>
      <:actions>{render_slot(@actions)}</:actions>

      <:sidebar>
        <Layout.nav_group label="Tools">
          <Layout.nav_item label="DB viewer" icon="circle-stack" navigate="/" active={@current == "db"} />
          <Layout.nav_item label="S3 viewer — soon" icon="cloud" class="lui-nav-item-soon" />
        </Layout.nav_group>
        <Layout.nav_group :for={{group, items} <- @groups} label={group}>
          <Layout.nav_item
            :for={{slug, label} <- items}
            label={label}
            icon={icon_for(group, slug)}
            navigate={"/components/#{slug}"}
            active={@current == slug}
          />
        </Layout.nav_group>
      </:sidebar>

      {render_slot(@inner_block)}
    </Layout.app_shell>

    <style>
      .lui-nav-item-soon { opacity: 0.5; pointer-events: none; }

      /* Embedded DB-viewer demo: drop the standalone marketing chrome so it reads
         as a tool page inside the shell. */
      .lui-app-main .demo-shell { background: none; padding: 0; min-height: 0; }
      .lui-app-main .demo-shell > * { max-width: 940px; margin-left: 0; margin-right: 0; }
      .lui-app-main .demo-hero { margin-bottom: 1rem; }
      .lui-app-main .demo-title { font-size: 1.5rem; }
      .lui-app-main .demo-eyebrow { display: none; }
    </style>
    """
  end

  @icons %{
    "app-shell" => "view-columns",
    "button" => "cursor-arrow-rays",
    "icon" => "sparkles",
    "input" => "pencil-square",
    "datetime-field" => "clock",
    "calendar" => "calendar",
    "date-picker" => "calendar-days",
    "checkbox" => "check-circle",
    "modal" => "window",
    "dropdown" => "chevron-up-down",
    "breadcrumb" => "chevron-right",
    "empty-state" => "inbox",
    "area-chart" => "chart-bar",
    "line-chart" => "presentation-chart-line",
    "bar-chart" => "chart-bar",
    "sparkline" => "arrow-trending-up"
  }

  defp icon_for(_group, slug), do: Map.get(@icons, slug, "squares-2x2")
end
