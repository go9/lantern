defmodule LanternDemoWeb.ComponentsLive do
  @moduledoc """
  The lantern-ui components reference — Fluxon-style docs layout: a fixed
  sidebar with grouped component nav, one component per route
  (`/components/:slug`), each rendered live with its HEEx source. Dogfoods
  lantern-ui: the page chrome itself is built from the components and themed by
  the real tokens, with light/dark + density toggles.
  """
  use Phoenix.LiveView

  alias LanternUI.Charts
  alias LanternUI.Components.Accordion
  alias LanternUI.Components.Alert
  alias LanternUI.Components.AlertDialog
  alias LanternUI.Components.Autocomplete
  alias LanternUI.Components.Badge
  alias LanternUI.Components.Avatar
  alias LanternUI.Components.Breadcrumb
  alias LanternUI.Components.Button
  alias LanternUI.Components.Calendar
  alias LanternUI.Components.Checkbox
  alias LanternUI.Components.Command
  alias LanternUI.Components.DatePicker
  alias LanternUI.Components.DatetimeField
  alias LanternUI.Components.Dropdown
  alias LanternUI.Components.EmptyState
  alias LanternUI.Components.Form
  alias LanternUI.Components.Icon
  alias LanternUI.Components.Layout
  alias LanternUI.Components.Loading
  alias LanternUI.Components.Modal
  alias LanternUI.Components.Message
  alias LanternUI.Components.MessageScroller
  alias LanternUI.Components.Menu
  alias LanternUI.Components.Popover
  alias LanternUI.Components.Progress
  alias LanternUI.Components.Meter
  alias LanternUI.Components.ResourceList
  alias LanternUI.Components.ColorInput
  alias LanternUI.Components.ScrollArea
  alias LanternUI.Components.Slider
  alias LanternUI.Components.Navlist
  alias LanternUI.Components.Pagination
  alias LanternUI.Components.Radio
  alias LanternUI.Components.Select
  alias LanternUI.Components.Separator
  alias LanternUI.Components.Sheet
  alias LanternUI.Components.Skeleton
  alias LanternUI.Components.Stat
  alias LanternUI.Components.Switch
  alias LanternUI.Components.Table
  alias LanternUI.Components.Tabs
  alias LanternUI.Components.Textarea
  alias LanternUI.Components.Timeline
  alias LanternUI.Components.Toast
  alias LanternUI.Components.Tooltip

  @groups LanternDemoWeb.DocsShell.component_groups()

  @labels Map.new(Enum.flat_map(@groups, fn {_g, items} -> items end))
  @default_slug "button"

  @catalog [
    %{
      group: "Nintendo 64",
      label: "The Legend of Zelda: Ocarina of Time",
      value: "zelda-ocarina"
    },
    %{group: "Nintendo 64", label: "The Legend of Zelda: Majora's Mask", value: "zelda-majora"},
    %{group: "Nintendo 64", label: "Super Mario 64", value: "super-mario-64"},
    %{
      group: "Nintendo Switch",
      label: "The Legend of Zelda: Breath of the Wild",
      value: "zelda-botw"
    },
    %{group: "Nintendo Switch", label: "Metroid Dread", value: "metroid-dread"},
    %{group: "Nintendo Switch", label: "Animal Crossing: New Horizons", value: "animal-crossing"}
  ]

  # Command palette source data. The component deliberately filters nothing —
  # it renders exactly the items it is handed — so this list stays here and the
  # LiveView answers `command_search` itself.
  @commands [
    %{
      group: "Navigate",
      value: "goto-buttons",
      label: "Go to Button",
      icon: "cursor-arrow-rays",
      description: "Components → Button",
      shortcut: "G B"
    },
    %{
      group: "Navigate",
      value: "goto-data-table",
      label: "Go to Data table",
      icon: "view-columns",
      description: "Components → Data table",
      shortcut: "G T"
    },
    %{
      group: "Navigate",
      value: "goto-theming",
      label: "Go to Theming",
      icon: "sparkles",
      description: "Tokens, density, and dark mode",
      shortcut: "G H"
    },
    %{
      group: "Actions",
      value: "toggle-theme",
      label: "Toggle dark mode",
      icon: "adjustments-horizontal",
      description: "Flip the demo between light and dark",
      shortcut: "⌘ D"
    },
    %{
      group: "Actions",
      value: "copy-install",
      label: "Copy install snippet",
      icon: "document",
      description:
        ~s({:lantern_ui, github: "go9/lantern-ui", ref: "0ad0627054ee6765c81eceace58ad316959565bb"}),
      shortcut: "⌘ C"
    },
    %{
      group: "Actions",
      value: "new-ticket",
      label: "Open a new ticket",
      icon: "inbox",
      description: "File an issue against lantern-ui",
      shortcut: "⌘ N"
    },
    %{
      group: "Danger zone",
      value: "reset-sandbox",
      label: "Reset the sandbox database",
      icon: "trash",
      description: "Disabled in this demo",
      shortcut: nil,
      disabled: true
    }
  ]

  # slug -> the component functions whose props/slots to document (introspected)
  @api_map %{
    "app-shell" => [
      {Layout, :app_shell},
      {Layout, :nav_group},
      {Layout, :nav_item},
      {Layout, :breadcrumb_bar},
      {Layout, :page_header}
    ],
    "navlist" => [{Navlist, :navlist}, {Navlist, :navheading}, {Navlist, :navlink}],
    "table" => [{Table, :table}, {Table, :table_head}, {Table, :table_body}, {Table, :table_row}],
    "pagination" => [{Pagination, :pagination}],
    "tabs" => [{Tabs, :tabs_list}, {Tabs, :tabs_panel}],
    "select" => [{Select, :select}],
    "badge" => [{Badge, :badge}],
    "button" => [{Button, :button}],
    "icon" => [{Icon, :icon}],
    "input" => [{Form, :input}, {Form, :label}, {Form, :error}],
    "popover" => [{Popover, :popover}],
    "menu" => [
      {Menu, :menu},
      {Menu, :menu_item},
      {Menu, :menu_separator},
      {Menu, :menubar},
      {Menu, :menubar_menu}
    ],
    "slider" => [{Slider, :slider}],
    "resource-list" => [{ResourceList, :resource_list}, {ResourceList, :resource_list_item}],
    "color-input" => [{ColorInput, :color_input}],
    "progress-meter" => [{Progress, :progress}, {Meter, :meter}],
    "scroll-area" => [{ScrollArea, :scroll_area}],
    "autocomplete" => [{Autocomplete, :autocomplete}],
    "accordion" => [{Accordion, :accordion}, {Accordion, :accordion_item}],
    "datetime-field" => [{DatetimeField, :datetime_field}],
    "calendar" => [{Calendar, :calendar}],
    "date-picker" => [
      {DatePicker, :date_picker},
      {DatePicker, :date_time_picker},
      {DatePicker, :time_picker},
      {DatePicker, :date_range_picker}
    ],
    "checkbox" => [{Checkbox, :checkbox}],
    "modal" => [{Modal, :modal}],
    "alert-dialog" => [{AlertDialog, :alert_dialog}],
    "dropdown" => [
      {Dropdown, :dropdown},
      {Dropdown, :dropdown_button},
      {Dropdown, :dropdown_link},
      {Dropdown, :dropdown_header},
      {Dropdown, :dropdown_separator},
      {Dropdown, :dropdown_custom}
    ],
    "command" => [
      {Command, :command},
      {Command, :command_group},
      {Command, :command_item},
      {Command, :command_empty},
      {Command, :command_separator},
      {Command, :command_shortcut}
    ],
    "breadcrumb" => [{Breadcrumb, :breadcrumb}],
    "empty-state" => [{EmptyState, :empty_state}],
    "timeline" => [{Timeline, :timeline}, {Timeline, :timeline_item}],
    "switch" => [{Switch, :switch}],
    "radio" => [{Radio, :radio}],
    "textarea" => [{Textarea, :textarea}],
    "alert" => [{Alert, :alert}],
    "loading" => [{Loading, :loading}],
    "skeleton" => [{Skeleton, :skeleton}],
    "stat" => [{Stat, :stat_card}, {Stat, :stat_grid}],
    "separator" => [{Separator, :separator}],
    "tooltip" => [{Tooltip, :tooltip}],
    "toast" => [{Toast, :toast_group}],
    "sheet" => [{Sheet, :sheet}],
    "chat-kit" => [
      {Avatar, :avatar},
      {Message, :message},
      {MessageScroller, :message_scroller},
      {MessageScroller, :message_scroller_item}
    ],
    "area-chart" => [{Charts, :area_chart}],
    "line-chart" => [{Charts, :line_chart}],
    "bar-chart" => [{Charts, :bar_chart}],
    "sparkline" => [{Charts, :sparkline}]
  }

  # Snippets retained for pages that still use the single-blob format
  # (app-shell, charts). Feature pages embed code per demo_section.
  @snippets %{
    "app-shell" => ~S"""
    <.app_shell id="app">
      <:brand><.icon name="bolt" /> <span class="lui-brand-name">Acme</span></:brand>
      <:header><.breadcrumb>…</.breadcrumb></:header>
      <:actions><.button variant="outline" size="sm">Account</.button></:actions>

      <:sidebar>
        <.nav_group label="Workspace">
          <.nav_item label="Dashboard" icon="chart-bar" navigate={~p"/"} active />
          <.nav_item label="Buckets" icon="cloud" navigate={~p"/buckets"} />
        </.nav_group>
      </:sidebar>

      <%!-- page content --%>
    </.app_shell>
    """,
    "area-chart" => ~S"""
    # series: a list of %{date, value} points
    daily_revenue = [
      %{date: ~D[2026-06-01], value: 40.0},
      %{date: ~D[2026-06-02], value: 47.5},
      %{date: ~D[2026-06-03], value: 52.1}
      # …one per day
    ]

    <.area_chart id="rev" series={daily_revenue} height={220} value_format={:currency} />
    """,
    "line-chart" => ~S"""
    # series: a list of lines; each line's points are {datetime, value} tuples
    web1 = [
      {~U[2026-07-07 00:00:00Z], 0.30},
      {~U[2026-07-07 01:00:00Z], 0.42}
      # …one per hour
    ]

    <.line_chart
      id="cpu"
      series={[
        %{label: "web-1", color: "var(--lantern-accent)", points: web1},
        %{label: "web-2", color: "var(--lantern-fg-subtle)", points: web2}
      ]}
    />
    """,
    "bar-chart" => ~S"""
    <.bar_chart id="q" series={[%{label: "Q1", value: 42}, %{label: "Q2", value: 31}]} />
    """,
    "sparkline" => ~S"""
    <.sparkline id="s" series={[3, 5, 4, 8, 6, 9]} height={48} />
    """
  }

  @chat_demo_messages [
    %{
      id: "chat-1",
      role: :assistant,
      initials: "F",
      header: "Assistant - 09:41",
      body:
        "Welcome. This transcript shows how a message row, avatar, metadata, and footer compose together.",
      footer: "Ready",
      align: "start",
      tone: "surface"
    },
    %{
      id: "chat-2",
      role: :user,
      initials: "AL",
      header: "Alex - 09:42",
      body: "Can you outline the three states this conversation can show?",
      footer: "Seen",
      align: "end",
      tone: "primary"
    },
    %{
      id: "chat-3",
      role: :assistant,
      initials: "LU",
      header: "Assistant - 09:42",
      body:
        "The sample uses a current transcript, a busy streaming row, and a follow control for the latest item.",
      footer: "Delivered",
      align: "start",
      tone: "surface"
    },
    %{
      id: "chat-4",
      role: :user,
      initials: "AL",
      header: "Alex - 09:43",
      body: "What makes the longer response readable in a compact viewport?",
      footer: "Seen",
      align: "end",
      tone: "primary"
    },
    %{
      id: "chat-5",
      role: :assistant,
      initials: "F",
      header: "Assistant - 09:43",
      body:
        "Readable chat content benefits from a deliberate measure and visible paragraph breaks.\n\nKeep supporting context in short paragraphs, use plain text when the component does not promise Markdown rendering, and let the surrounding message bubble provide the visual grouping.\n\nThe fixed-height viewport below is intentionally small enough to make the follow behavior observable while keeping each turn easy to scan.",
      footer: "Delivered",
      align: "start",
      tone: "surface"
    },
    %{
      id: "chat-6",
      role: :user,
      initials: "AL",
      header: "Alex - 09:44",
      body: "Add one more reply so I can see the latest item move into view.",
      footer: "Seen",
      align: "end",
      tone: "primary"
    },
    %{
      id: "chat-7",
      role: :assistant,
      initials: "LU",
      header: "Assistant - 09:44",
      body:
        "The last item is marked as the scroll anchor. Use the controls above to append, hold, or reset this transcript.",
      footer: "Delivered",
      align: "start",
      tone: "surface"
    }
  ]

  def mount(_params, _session, socket) do
    today = Date.utc_today()

    area =
      for i <- 0..29 do
        %{date: Date.add(today, i - 29), value: 40 + :math.sin(i / 4) * 12 + i * 0.8}
      end

    line = [
      %{
        label: "web-1",
        color: "var(--lantern-accent)",
        points:
          for(
            i <- 0..23,
            do: {DateTime.add(~U[2026-07-07 00:00:00Z], i * 3600), 0.3 + :math.sin(i / 3) * 0.2}
          )
      },
      %{
        label: "web-2",
        color: "var(--lantern-fg-subtle)",
        points:
          for(
            i <- 0..23,
            do: {DateTime.add(~U[2026-07-07 00:00:00Z], i * 3600), 0.5 + :math.cos(i / 4) * 0.15}
          )
      }
    ]

    {:ok,
     assign(socket,
       groups: @groups,
       snippets: @snippets,
       demo_tab: "one",
       toast_placement: "top-right",
       catalog_options: [],
       command_query: "",
       command_groups: command_matches(""),
       command_selection: nil,
       alert_dialog_status: nil,
       area: area,
       line: line,
       bars: [
         %{label: "Q1", value: 42},
         %{label: "Q2", value: 31},
         %{label: "Q3", value: 55},
         %{label: "Q4", value: 47}
       ],
       spark: [3, 5, 4, 8, 6, 9, 7, 11, 9, 12],
       chat_demo_messages: @chat_demo_messages,
       chat_demo_busy: false,
       chat_demo_next_reply: 8,
       range_form:
         Phoenix.Component.to_form(%{"from" => "2026-08-01", "to" => "2026-08-07"}, as: :range)
     )}
  end

  def handle_params(params, _uri, socket) do
    slug =
      case Map.fetch(params, "slug") do
        {:ok, s} when is_map_key(@labels, s) -> s
        _ -> @default_slug
      end

    {:noreply,
     assign(socket,
       current: slug,
       label: Map.fetch!(@labels, slug),
       page_title: "#{Map.fetch!(@labels, slug)} — lantern-ui"
     )}
  end

  def handle_event("set_toast_placement", %{"placement" => placement}, socket) do
    {:noreply, assign(socket, :toast_placement, placement)}
  end

  def handle_event("demo_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :demo_tab, tab)}
  end

  def handle_event("demo_toast", %{"kind" => kind}, socket) do
    {:noreply,
     LanternUI.send_toast(socket, kind, "This is a #{kind} toast", title: String.capitalize(kind))}
  end

  def handle_event("search_catalog", %{"query" => query}, socket) do
    {:noreply, assign(socket, :catalog_options, catalog_options(query))}
  end

  # The palette does no filtering of its own — it renders what it is handed and
  # reports the query upward. Answering this event is what makes typing filter.
  def handle_event("command_search", %{"query" => query}, socket) do
    {:noreply, assign(socket, command_query: query, command_groups: command_matches(query))}
  end

  def handle_event("command_select", %{"value" => value}, socket) do
    label =
      Enum.find_value(@commands, value, fn cmd -> cmd.value == value && cmd.label end)

    {:noreply, assign(socket, :command_selection, {value, label})}
  end

  def handle_event("confirm_demo_revoke", _params, socket) do
    socket =
      socket
      |> assign(:alert_dialog_status, "Demo key revoked — no real credential was changed.")
      |> LanternUI.close_dialog("alert-dialog-demo")

    {:noreply, socket}
  end

  def handle_event("chat_append_reply", _params, socket) do
    next_reply = socket.assigns.chat_demo_next_reply

    reply = %{
      id: "chat-reply-#{next_reply}",
      role: :assistant,
      initials: "F",
      header: "Assistant - now",
      body: "Here is the stable appended reply. The new final item becomes the scroll anchor.",
      footer: "Delivered",
      align: "start",
      tone: "surface"
    }

    {:noreply,
     assign(socket,
       chat_demo_messages: socket.assigns.chat_demo_messages ++ [reply],
       chat_demo_next_reply: next_reply + 1
     )}
  end

  def handle_event("chat_toggle_streaming", _params, socket) do
    {:noreply, update(socket, :chat_demo_busy, &(!&1))}
  end

  def handle_event("chat_reset", _params, socket) do
    {:noreply, assign(socket, chat_demo_messages: @chat_demo_messages, chat_demo_busy: false)}
  end

  def render(assigns) do
    ~H"""
    <LanternDemoWeb.DocsShell.shell current={@current}>
      <article :if={@current == "app-shell"} class="docs-body">
        <h1>App shell</h1>
        <p>
          The chrome around this page — the top bar (brand · breadcrumb · actions), the
          fixed collapsible sidebar, and the main column — <strong>is</strong>
          <code>&lt;.app_shell&gt;</code>, built from lantern-ui components. Slots:
          <code>:brand</code> (corner logo), <code>:header</code> (inline
          breadcrumbs/switchers), <code>:actions</code> (top-right), and
          <code>:sidebar</code> (<code>nav_group</code> / <code>nav_item</code>). The
          collapse control at the sidebar foot persists per <code>id</code>.
        </p>
        <div class="docs-demo">
          <div class="docs-appshell-frame">
            <div class="docs-appshell-frame-bar" aria-hidden="true">
              <span></span><span></span><span></span>
            </div>
            <iframe
              src="/preview/app-shell"
              title="Live app_shell preview"
              loading="lazy"
              class="docs-appshell-iframe"
            >
            </iframe>
          </div>
          <p class="docs-caption">
            A real, interactive <code>&lt;.app_shell&gt;</code> — brand · breadcrumb ·
            actions over a collapsible sidebar and a main column. Rendered in an iframe
            because <code>app_shell</code> is <code>position: fixed</code>; the collapse
            control at the sidebar foot works here too.
          </p>
        </div>
        <.code_block id="code-app-shell" code={@snippets["app-shell"]} />
        <.demo_section
          title="Action bar"
          description="breadcrumb_bar with a trail plus :actions: trail left, actions right, one bar instead of a stacked breadcrumb and title row."
          code={~S'''
          <.breadcrumb_bar>
            <.breadcrumb>
              <:item href="#">Workspace</:item>
              <:item href="#">Projects</:item>
              <:item current>enventory</:item>
            </.breadcrumb>
            <:actions label="Share">
              <.button size="sm" variant="outline">Share</.button>
            </:actions>
            <:actions label="New deploy">
              <.button size="sm">New deploy</.button>
            </:actions>
          </.breadcrumb_bar>
          '''}
        >
          <Layout.breadcrumb_bar id="demo-bc-action-bar">
            <Breadcrumb.breadcrumb>
              <:item href="#">Workspace</:item>
              <:item href="#">Projects</:item>
              <:item current>enventory</:item>
            </Breadcrumb.breadcrumb>
            <:actions label="Share">
              <Button.button size="sm" variant="outline">Share</Button.button>
            </:actions>
            <:actions label="New deploy">
              <Button.button size="sm">New deploy</Button.button>
            </:actions>
          </Layout.breadcrumb_bar>
        </.demo_section>
        <.demo_section
          title="Page header"
          description="A title, supporting description, and right-side actions compose the page header below the breadcrumb."
          code={~S'''
          <.page_header title="Projects" description="Manage deployed resources">
            <:actions><.button>New project</.button></:actions>
          </.page_header>
          '''}
        >
          <Layout.page_header title="Projects" description="Manage deployed resources">
            <:actions><Button.button>New project</Button.button></:actions>
          </Layout.page_header>
        </.demo_section>
        <.demo_section
          title="Overflow"
          description="Only the first :max_inline entries (default 2) are quick buttons; the rest fold into the More menu. The same fold applies to the quick buttons themselves as the bar narrows, so nothing becomes unreachable on small screens."
          code={~S'''
          <.breadcrumb_bar>
            <.breadcrumb>
              <:item href="#">Workspace</:item>
              <:item current>foodfeed</:item>
            </.breadcrumb>
            <:actions label="Deploy">
              <.button size="sm">Deploy</.button>
            </:actions>
            <:actions label="Logs" phx-click="logs">
              <.button size="sm" variant="outline" phx-click="logs">Logs</.button>
            </:actions>
            <:actions label="Scale" phx-click="scale">
              <.button size="sm" variant="outline" phx-click="scale">Scale</.button>
            </:actions>
            <:actions label="Rollback" phx-click="rollback">
              <.button size="sm" variant="outline" phx-click="rollback">Rollback</.button>
            </:actions>
            <:actions label="Settings" phx-click="settings">
              <.button size="sm" variant="outline" phx-click="settings">Settings</.button>
            </:actions>
          </.breadcrumb_bar>
          '''}
        >
          <Layout.breadcrumb_bar id="demo-bc-overflow">
            <Breadcrumb.breadcrumb>
              <:item href="#">Workspace</:item>
              <:item current>foodfeed</:item>
            </Breadcrumb.breadcrumb>
            <:actions label="Deploy">
              <Button.button size="sm">Deploy</Button.button>
            </:actions>
            <:actions label="Logs" phx-click="logs">
              <Button.button size="sm" variant="outline" phx-click="logs">Logs</Button.button>
            </:actions>
            <:actions label="Scale" phx-click="scale">
              <Button.button size="sm" variant="outline" phx-click="scale">Scale</Button.button>
            </:actions>
            <:actions label="Rollback" phx-click="rollback">
              <Button.button size="sm" variant="outline" phx-click="rollback">Rollback</Button.button>
            </:actions>
            <:actions label="Settings" phx-click="settings">
              <Button.button size="sm" variant="outline" phx-click="settings">Settings</Button.button>
            </:actions>
          </Layout.breadcrumb_bar>
        </.demo_section>
        <.demo_section
          title="Destructive entry"
          description="Put data-confirm on the :actions slot. A folded item renders from slot attrs and never its body, so a confirm placed only on an inner button is lost once the entry folds."
          code={~S'''
          <.breadcrumb_bar>
            <.breadcrumb>
              <:item href="#">Workspace</:item>
              <:item current>skusync</:item>
            </.breadcrumb>
            <:actions label="Edit">
              <.button size="sm" variant="outline">Edit</.button>
            </:actions>
            <:actions label="Clone">
              <.button size="sm" variant="outline">Clone</.button>
            </:actions>
            <:actions
              label="Delete"
              phx-click="delete"
              data-confirm="Delete this project? This cannot be undone."
            >
              <.button
                size="sm"
                variant="outline"
                color="danger"
                phx-click="delete"
                data-confirm="Delete this project? This cannot be undone."
              >
                Delete
              </.button>
            </:actions>
          </.breadcrumb_bar>
          '''}
        >
          <Layout.breadcrumb_bar id="demo-bc-destructive">
            <Breadcrumb.breadcrumb>
              <:item href="#">Workspace</:item>
              <:item current>skusync</:item>
            </Breadcrumb.breadcrumb>
            <:actions label="Edit">
              <Button.button size="sm" variant="outline">Edit</Button.button>
            </:actions>
            <:actions label="Clone">
              <Button.button size="sm" variant="outline">Clone</Button.button>
            </:actions>
            <:actions
              label="Delete"
              phx-click="delete"
              data-confirm="Delete this project? This cannot be undone."
            >
              <Button.button
                size="sm"
                variant="outline"
                color="danger"
                phx-click="delete"
                data-confirm="Delete this project? This cannot be undone."
              >
                Delete
              </Button.button>
            </:actions>
          </Layout.breadcrumb_bar>
        </.demo_section>
      </article>

      <article :if={@current == "navlist"} class="docs-body">
        <h1>Nav list</h1>
        <p>
          Vertical navigation — an optional heading plus links. Items render as
          <code>navigate</code>/<code>patch</code>/<code>href</code> links, or as a
          button when given <code>phx-click</code>. Mirrors Fluxon's navlist surface.
        </p>
        <.demo_section
          title="Headed list"
          description="heading + navlink items; active marks the current page, icon adds a leading glyph."
          code={~S'''
          <.navlist heading="Workspace">
            <.navlink href="#" active>Dashboard</.navlink>
            <.navlink href="#" icon="folder">Projects</.navlink>
            <.navlink href="#" icon="adjustments-horizontal">Settings</.navlink>
            <.navheading>Account</.navheading>
            <.navlink href="#" icon="document">Profile</.navlink>
          </.navlist>
          '''}
        >
          <Navlist.navlist heading="Workspace">
            <Navlist.navlink href="#" active>Dashboard</Navlist.navlink>
            <Navlist.navlink href="#" icon="folder">Projects</Navlist.navlink>
            <Navlist.navlink href="#" icon="adjustments-horizontal">Settings</Navlist.navlink>
            <Navlist.navheading>Account</Navlist.navheading>
            <Navlist.navlink href="#" icon="document">Profile</Navlist.navlink>
          </Navlist.navlist>
        </.demo_section>
      </article>

      <article :if={@current == "button"} class="docs-body">
        <h1>Button</h1>
        <p>
          Variants × colors, sizes, and icon buttons.
          Defaults: <code>variant="outline" color="primary" size="md"</code>.
        </p>
        <.demo_section
          title="Variants"
          description="Six surface styles. Color is primary by default."
          code={~S'''
          <.button :for={v <- ~w(solid soft surface outline dashed ghost)} variant={v}>
            {v}
          </.button>
          '''}
        >
          <div class="docs-row">
            <Button.button :for={v <- ~w(solid soft surface outline dashed ghost)} variant={v}>
              {v}
            </Button.button>
          </div>
        </.demo_section>
        <.demo_section
          title="Colors"
          description="primary, danger, warning, success, info — shown on solid."
          code={~S'''
          <.button :for={c <- ~w(primary danger warning success info)} variant="solid" color={c}>
            {c}
          </.button>
          '''}
        >
          <div class="docs-row">
            <Button.button
              :for={c <- ~w(primary danger warning success info)}
              variant="solid"
              color={c}
            >
              {c}
            </Button.button>
          </div>
        </.demo_section>
        <.demo_section
          title="Sizes"
          description="Text sizes xs–xl, icon size, and the disabled state."
          code={~S'''
          <.button :for={s <- ~w(xs sm md lg xl)} size={s}>{s}</.button>
          <.button size="icon" aria-label="Add"><.icon name="plus" /></.button>
          <.button variant="solid" disabled>disabled</.button>
          '''}
        >
          <div class="docs-row">
            <Button.button :for={s <- ~w(xs sm md lg xl)} size={s}>{s}</Button.button>
            <Button.button size="icon" aria-label="Add"><Icon.icon name="plus" /></Button.button>
            <Button.button variant="solid" disabled>disabled</Button.button>
          </div>
        </.demo_section>
        <.demo_section
          title="Button group"
          description="Joined segmented control — shared borders and radius."
          code={~S'''
          <.button_group>
            <.button>Years</.button>
            <.button>Months</.button>
            <.button>Days</.button>
          </.button_group>
          '''}
        >
          <div class="docs-row">
            <Button.button_group>
              <Button.button>Years</Button.button>
              <Button.button>Months</Button.button>
              <Button.button>Days</Button.button>
            </Button.button_group>
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "icon"} class="docs-body">
        <h1>Icon</h1>
        <p>Inline heroicons (outline), sized by font-size.</p>
        <.demo_section
          title="Gallery"
          description="Pass a heroicon name; the glyph scales with surrounding font-size."
          code={~S'''
          <.icon name="calendar-days" />
          <.icon name="magnifying-glass" />
          <.icon name="check" />
          '''}
        >
          <div class="docs-row docs-icons">
            <span
              :for={
                n <-
                  ~w(plus minus check x-mark chevron-down chevron-up chevron-left chevron-right arrow-right calendar-days clock magnifying-glass ellipsis-horizontal exclamation-circle)
              }
              class="docs-icon-cell"
            >
              <Icon.icon name={n} />
              <code>{n}</code>
            </span>
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "input"} class="docs-body">
        <h1>Input</h1>
        <p>
          Text field with label, sublabel, help text, and error states.
          Accepts a <code>Phoenix.HTML.FormField</code>.
        </p>
        <.demo_section
          title="Basic"
          description="Label, name, and placeholder."
          code={~S'''
          <.input id="in-1" name="name" label="Name" placeholder="Ada Lovelace" />
          '''}
        >
          <Form.input id="in-1" name="name" label="Name" placeholder="Ada Lovelace" value={nil} />
        </.demo_section>
        <.demo_section
          title="Help text & sublabel"
          description="Sublabel sits beside the label; help_text sits under the control."
          code={~S'''
          <.input
            name="email"
            label="Email"
            sublabel="Required"
            help_text="We never share it."
            placeholder="you@example.com"
          />
          '''}
        >
          <Form.input
            id="in-2"
            name="email"
            label="Email"
            sublabel="Required"
            help_text="We never share it."
            placeholder="you@example.com"
            value={nil}
          />
        </.demo_section>
        <.demo_section
          title="Error state"
          description="Pass errors as a list of strings (or use FormField)."
          code={~S'''
          <.input name="handle" label="Handle" value="not valid!" errors={["must not contain spaces"]} />
          '''}
        >
          <Form.input
            id="in-3"
            name="handle"
            label="Handle"
            value="not valid!"
            errors={["must not contain spaces"]}
          />
        </.demo_section>
        <.demo_section
          title="Disabled"
          description="Disabled fields keep their value but cannot be edited."
          code={~S'''
          <.input name="ro" label="Disabled" value="read only" disabled />
          '''}
        >
          <Form.input id="in-4" name="ro" label="Disabled" value="read only" disabled />
        </.demo_section>
      </article>

      <article :if={@current == "autocomplete"} class="docs-body">
        <h1>Autocomplete</h1>
        <p>
          Accessible static or LiveView-backed search. Lantern owns the combobox,
          keyboard selection, and presentation; your LiveView owns remote querying,
          authorization, and result order. The public API mirrors Fluxon 2.3.1.
        </p>
        <.demo_section
          title="Static filtering"
          description="Static options filter in the browser; selection fills the hidden form input."
          code={~S'''
          <.autocomplete
            id="ac-fruit"
            name="fruit"
            label="Fruit"
            placeholder="Search fruit…"
            options={["Apple", "Apricot", "Banana", "Blackberry", "Cherry", "Grape"]}
          />
          '''}
        >
          <Autocomplete.autocomplete
            id="ac-fruit"
            name="fruit"
            label="Fruit"
            placeholder="Search fruit…"
            options={["Apple", "Apricot", "Banana", "Blackberry", "Cherry", "Grape"]}
          />
        </.demo_section>

        <.demo_section
          title="Server-backed search"
          description="Type at least two characters (try “zel”). The LiveView filters server-owned data and patches grouped, rich results back into the same focused combobox."
          code={~S'''
          # LiveView
          def handle_event("search_catalog", %{"query" => query}, socket) do
            {:noreply, assign(socket, :catalog_options, search_catalog(query))}
          end

          <.autocomplete
            id="ac-catalog"
            name="game_id"
            label="Game catalog"
            options={@catalog_options}
            on_search="search_catalog"
            search_threshold={2}
            debounce={250}
            clearable
            no_results_text="No games match %{query}"
          >
            <:option :let={{label, value}}>
              <span>{label}</span><code>{value}</code>
            </:option>
          </.autocomplete>
          '''}
        >
          <Autocomplete.autocomplete
            id="ac-catalog"
            name="game_id"
            label="Game catalog"
            description="Server-backed, grouped results with rich option rows."
            placeholder="Search the catalog…"
            options={@catalog_options}
            on_search="search_catalog"
            search_threshold={2}
            debounce={250}
            clearable
            no_results_text="No games match %{query}"
          >
            <:header>Results from the demo LiveView</:header>
            <:option :let={{label, value}}>
              <span class="docs-option-rich">
                <span>{label}</span>
                <code>{value}</code>
              </span>
            </:option>
            <:footer>Fixed demo data; production search remains caller-owned.</:footer>
          </Autocomplete.autocomplete>
        </.demo_section>
      </article>

      <article :if={@current == "accordion"} class="docs-body">
        <h1>Accordion</h1>
        <p>
          WAI-ARIA disclosure groups with Fluxon 2.3.1's
          <code>accordion/1</code> + <code>accordion_item/1</code> composition API.
          Arrow keys move between headers; Enter and Space toggle the focused item.
        </p>
        <.demo_section
          title="Required open item"
          description="Single-open mode with prevent_all_closed keeps one answer available at all times."
          code={~S'''
          <.accordion id="faq" prevent_all_closed>
            <.accordion_item id="faq-search" expanded>
              <:header>Who owns async search?</:header>
              <:panel>The LiveView owns querying and authorization.</:panel>
            </.accordion_item>
            <.accordion_item id="faq-state">
              <:header>Does state survive patches?</:header>
              <:panel>Yes. Hook-owned state is restored after LiveView patches.</:panel>
            </.accordion_item>
          </.accordion>
          '''}
        >
          <Accordion.accordion id="faq" prevent_all_closed>
            <Accordion.accordion_item id="faq-search" expanded>
              <:header>Who owns async search?</:header>
              <:panel>
                The LiveView owns querying, authorization, and ordering; the component owns interaction.
              </:panel>
            </Accordion.accordion_item>
            <Accordion.accordion_item id="faq-state">
              <:header>Does state survive LiveView patches?</:header>
              <:panel>Yes. Open state and focused-header position are restored after patches.</:panel>
            </Accordion.accordion_item>
            <Accordion.accordion_item id="faq-keyboard">
              <:header>Which keys are supported?</:header>
              <:panel>Enter, Space, Arrow Up/Down, Home, and End follow the APG pattern.</:panel>
            </Accordion.accordion_item>
          </Accordion.accordion>
        </.demo_section>

        <.demo_section
          title="Multiple open"
          description="multiple allows independent disclosure panels; icon={false} supports a custom visual treatment."
          code={~S'''
          <.accordion id="details" multiple>
            <.accordion_item id="details-api" expanded>
              <:header>Public API</:header>
              <:panel>Fluxon-compatible container and item functions.</:panel>
            </.accordion_item>
            <.accordion_item id="details-license" expanded icon={false}>
              <:header>Implementation</:header>
              <:panel>Independent, clean-room Lantern behavior.</:panel>
            </.accordion_item>
          </.accordion>
          '''}
        >
          <Accordion.accordion id="details" multiple>
            <Accordion.accordion_item id="details-api" expanded>
              <:header>Public API</:header>
              <:panel>Fluxon-compatible container and item functions.</:panel>
            </Accordion.accordion_item>
            <Accordion.accordion_item id="details-license" expanded icon={false}>
              <:header>Implementation</:header>
              <:panel>Independent, clean-room Lantern behavior.</:panel>
            </Accordion.accordion_item>
          </Accordion.accordion>
        </.demo_section>
      </article>

      <article :if={@current == "datetime-field"} class="docs-body">
        <h1>Datetime field</h1>
        <p>
          Segmented, keyboard-first entry: type straight into a segment,
          <kbd>↑</kbd><kbd>↓</kbd> to step, <kbd>←</kbd><kbd>→</kbd> to move.
          Backs a hidden input with the canonical value.
        </p>
        <.demo_section
          title="Date mode"
          description="Canonical value is YYYY-MM-DD."
          code={~S'''
          <.datetime_field id="dtf-date" name="dtf1" mode={:date} value="2026-07-08" />
          '''}
        >
          <DatetimeField.datetime_field id="dtf-date" name="dtf1" mode={:date} value="2026-07-08" />
        </.demo_section>
        <.demo_section
          title="Time mode"
          description="precision controls which segments appear (:minute, :second, :millisecond)."
          code={~S'''
          <.datetime_field
            id="dtf-time"
            name="dtf2"
            mode={:time}
            precision={:millisecond}
            value="14:30:00.000"
          />
          '''}
        >
          <DatetimeField.datetime_field
            id="dtf-time"
            name="dtf2"
            mode={:time}
            precision={:millisecond}
            value="14:30:00.000"
          />
        </.demo_section>
        <.demo_section
          title="Datetime mode"
          description="Combined date + time; canonical value is ISO-8601 local."
          code={~S'''
          <.datetime_field
            id="dtf-dt"
            name="at"
            mode={:datetime}
            precision={:millisecond}
            value="2026-07-08T14:30:00.000"
          />
          '''}
        >
          <DatetimeField.datetime_field
            id="dtf-dt"
            name="at"
            mode={:datetime}
            precision={:millisecond}
            value="2026-07-08T14:30:00.000"
          />
        </.demo_section>
      </article>

      <article :if={@current == "calendar"} class="docs-body">
        <h1>Calendar</h1>
        <p>
          APG-grid month calendar: arrow keys move by day/week,
          <kbd>PgUp</kbd>/<kbd>PgDn</kbd> by month, <kbd>t</kbd> jumps to today.
        </p>
        <.demo_section
          title="Basic"
          description="Selected day uses monochrome-primary fill; today gets a coral ring."
          code={~S'''
          <.calendar id="cal-demo" selected={Date.utc_today()} />
          '''}
        >
          <div class="docs-cal-box">
            <Calendar.calendar id="cal-demo" selected={Date.utc_today()} />
          </div>
        </.demo_section>
        <.demo_section
          title="Week start & min date"
          description="week_start is 0=Sunday … 6=Saturday; min disables earlier days."
          code={~S'''
          <.calendar id="cal-min" selected={~D[2026-07-08]} week_start={1} min="2026-01-01" />
          '''}
        >
          <div class="docs-cal-box">
            <Calendar.calendar
              id="cal-min"
              selected={~D[2026-07-08]}
              week_start={1}
              min="2026-01-01"
            />
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "date-picker"} class="docs-body">
        <h1>Date &amp; time pickers</h1>
        <p>
          Fluxon-compatible API. Segmented trigger + calendar popover with a time pane
          (<code>date_time_picker</code>). <code>time_picker</code>
          is segments-only — a lantern-ui extension.
        </p>
        <.demo_section
          title="Date picker"
          description="Segmented date trigger with a calendar popover."
          code={~S'''
          <.date_picker id="pk-date" name="due" label="Due date" value="2026-07-08" />
          '''}
        >
          <DatePicker.date_picker id="pk-date" name="due" label="Due date" value="2026-07-08" />
        </.demo_section>
        <.demo_section
          title="Date-time picker"
          description="Calendar plus a time pane; precision controls the time segments."
          code={~S'''
          <.date_time_picker
            id="pk-dt"
            name="starts_at"
            label="Starts at"
            precision={:millisecond}
            value="2026-07-08T09:15:00.000"
          />
          '''}
        >
          <DatePicker.date_time_picker
            id="pk-dt"
            name="starts_at"
            label="Starts at"
            precision={:millisecond}
            value="2026-07-08T09:15:00.000"
          />
        </.demo_section>
        <.demo_section
          title="Time picker"
          description="Segments-only time entry — a lantern-ui extension."
          code={~S'''
          <.time_picker id="pk-time" name="alarm" label="Alarm" value="08:45:00.000" />
          '''}
        >
          <DatePicker.time_picker id="pk-time" name="alarm" label="Alarm" value="08:45:00.000" />
        </.demo_section>
        <.demo_section
          title="Error state"
          description="Same error chrome as other form controls."
          code={~S'''
          <.date_picker id="pk-err" name="bad" label="With error" errors={["can't be blank"]} />
          '''}
        >
          <DatePicker.date_picker
            id="pk-err"
            name="bad"
            label="With error"
            value={nil}
            errors={["can't be blank"]}
          />
        </.demo_section>
        <.demo_section
          title="Date range"
          description="Two ordinary form fields compose a start and end date range."
          code={~S'''
          <.date_range_picker start_field={f[:from]} end_field={f[:to]} label="Release window" />
          '''}
        >
          <DatePicker.date_range_picker
            id="pk-range"
            start_field={@range_form[:from]}
            end_field={@range_form[:to]}
            label="Release window"
          />
        </.demo_section>
      </article>

      <article :if={@current == "checkbox"} class="docs-body">
        <h1>Checkbox</h1>
        <p>
          Fluxon-compatible, <code>FormField</code>-aware. A hidden input submits the
          unchecked value so forms always receive the param.
        </p>
        <.demo_section
          title="Basic"
          description="Unchecked by default; label is optional."
          code={~S'''
          <.checkbox id="ck-1" name="accept" label="Accept the terms" />
          '''}
        >
          <Checkbox.checkbox id="ck-1" name="accept" label="Accept the terms" />
        </.demo_section>
        <.demo_section
          title="Checked with description"
          description="description renders under the label for longer helper copy."
          code={~S'''
          <.checkbox
            name="notify"
            checked
            label="Email me about activity"
            description="At most one email per day."
          />
          '''}
        >
          <Checkbox.checkbox
            id="ck-2"
            name="notify"
            checked
            label="Email me about activity"
            description="At most one email per day."
          />
        </.demo_section>
        <.demo_section
          title="Disabled"
          description="Non-interactive; value still posts if the control is checked."
          code={~S'''
          <.checkbox name="dis" label="Disabled" disabled />
          '''}
        >
          <Checkbox.checkbox id="ck-3" name="dis" label="Disabled" disabled />
        </.demo_section>
        <.demo_section
          title="Error state"
          description="Invalid chrome and error message under the control."
          code={~S'''
          <.checkbox name="err" label="Required" errors={["must be accepted"]} />
          '''}
        >
          <Checkbox.checkbox id="ck-4" name="err" label="Required" errors={["must be accepted"]} />
        </.demo_section>
      </article>

      <article :if={@current == "modal"} class="docs-body">
        <h1>Modal</h1>
        <p>
          General-purpose dialog content on the shared overlay runtime: focus trap,
          <kbd>Esc</kbd>/outside dismissal, optional close button, and token-driven fade.
          Use it for forms, details, and reversible workflows.
        </p>
        <.demo_section
          title="Edit workspace details"
          description="A normal modal can contain arbitrary form content and dismisses on Esc, close button, or outside click."
          code={~S'''
          <.button phx-click={LanternUI.open_dialog("workspace-modal")}>Edit workspace</.button>

          <.modal id="workspace-modal">
            <h2>Edit workspace</h2>
            <.input name="workspace_name" label="Workspace name" value="Acme Operations" />
            <.button phx-click={LanternUI.close_dialog("workspace-modal")}>Cancel</.button>
            <.button variant="solid" phx-click={LanternUI.close_dialog("workspace-modal")}>Save</.button>
          </.modal>
          '''}
        >
          <div class="docs-row">
            <Button.button phx-click={LanternUI.open_dialog("demo-modal")}>
              Edit workspace…
            </Button.button>
          </div>
          <Modal.modal id="demo-modal">
            <h2 style="margin: 0 0 1rem; font-size: 1.05rem;">Edit workspace details</h2>
            <Form.input
              id="modal-workspace-name"
              name="workspace_name"
              label="Workspace name"
              value="Acme Operations"
            />
            <div style="display: flex; gap: .5rem; justify-content: flex-end; margin-top: 1rem;">
              <Button.button phx-click={LanternUI.close_dialog("demo-modal")}>Cancel</Button.button>
              <Button.button variant="solid" phx-click={LanternUI.close_dialog("demo-modal")}>
                Save changes
              </Button.button>
            </div>
          </Modal.modal>
        </.demo_section>
      </article>

      <article :if={@current == "alert-dialog"} class="docs-body">
        <h1>Alert dialog</h1>
        <p>
          A deliberately constrained confirmation surface for irreversible or high-impact
          choices. Unlike a general modal, it requires consequence copy plus cancel/action
          controls, focuses Cancel first, hides the generic close button, and ignores outside clicks.
        </p>
        <.demo_section
          title="Revoke a production credential"
          description="The consequence is concrete and the destructive action is visually singular. This demo never changes a real credential."
          code={~S'''
          <.button phx-click={LanternUI.open_dialog("revoke-key")}>Revoke key…</.button>

          <.alert_dialog id="revoke-key">
            <:title>Revoke the production API key?</:title>
            <:description>Requests using pk_live_7K… will fail immediately.</:description>
            <:cancel>
              <.button phx-click={LanternUI.close_dialog("revoke-key")}>Keep key</.button>
            </:cancel>
            <:action>
              <.button color="danger" variant="solid" phx-click="revoke_key">Revoke key</.button>
            </:action>
          </.alert_dialog>
          '''}
        >
          <div class="docs-row">
            <Button.button phx-click={LanternUI.open_dialog("alert-dialog-demo")}>
              Revoke production key…
            </Button.button>
            <p
              :if={@alert_dialog_status}
              id="alert-dialog-status"
              class="docs-confirm-status"
              role="status"
            >
              {@alert_dialog_status}
            </p>
          </div>
          <AlertDialog.alert_dialog id="alert-dialog-demo">
            <:title>Revoke the production API key?</:title>
            <:description>
              Requests using <code>pk_live_7K…</code> will fail immediately. This demo changes no real credential.
            </:description>
            <:cancel>
              <Button.button phx-click={LanternUI.close_dialog("alert-dialog-demo")}>
                Keep key
              </Button.button>
            </:cancel>
            <:action>
              <Button.button color="danger" variant="solid" phx-click="confirm_demo_revoke">
                Revoke key
              </Button.button>
            </:action>
          </AlertDialog.alert_dialog>
        </.demo_section>
      </article>

      <article :if={@current == "dropdown"} class="docs-body">
        <h1>Dropdown menu</h1>
        <p>
          Fluxon-compatible family with WAI-ARIA menu semantics — <kbd>↑</kbd><kbd>↓</kbd>
          move through items, <kbd>Esc</kbd> closes, focus returns to the trigger.
        </p>
        <.demo_section
          title="Label trigger"
          description="Default toggle button from label=; header, buttons, separator, and danger item."
          code={~S'''
          <.dropdown id="dd-demo" label="Actions">
            <.dropdown_header>object.png</.dropdown_header>
            <.dropdown_button><.icon name="arrow-down-tray" /> Download</.dropdown_button>
            <.dropdown_button><.icon name="arrow-path" /> Rename</.dropdown_button>
            <.dropdown_separator />
            <.dropdown_button data-danger><.icon name="trash" /> Delete</.dropdown_button>
          </.dropdown>
          '''}
        >
          <div class="docs-row">
            <Dropdown.dropdown id="dd-demo" label="Actions">
              <Dropdown.dropdown_header>object.png</Dropdown.dropdown_header>
              <Dropdown.dropdown_button>
                <Icon.icon name="arrow-down-tray" /> Download
              </Dropdown.dropdown_button>
              <Dropdown.dropdown_button>
                <Icon.icon name="arrow-path" /> Rename
              </Dropdown.dropdown_button>
              <Dropdown.dropdown_separator />
              <Dropdown.dropdown_button data-danger>
                <Icon.icon name="trash" /> Delete
              </Dropdown.dropdown_button>
            </Dropdown.dropdown>
          </div>
        </.demo_section>
        <.demo_section
          title="Custom toggle & placement"
          description=":toggle slot for any trigger; placement anchors the panel."
          code={~S'''
          <.dropdown id="dd-icon" placement="bottom-end">
            <:toggle>
              <.button size="icon" aria-label="More"><.icon name="ellipsis-horizontal" /></.button>
            </:toggle>
            <.dropdown_button>Duplicate</.dropdown_button>
            <.dropdown_button>Move…</.dropdown_button>
          </.dropdown>
          '''}
        >
          <div class="docs-row">
            <Dropdown.dropdown id="dd-icon" placement="bottom-end">
              <:toggle>
                <Button.button size="icon" aria-label="More">
                  <Icon.icon name="ellipsis-horizontal" />
                </Button.button>
              </:toggle>
              <Dropdown.dropdown_button>Duplicate</Dropdown.dropdown_button>
              <Dropdown.dropdown_button>Move…</Dropdown.dropdown_button>
              </Dropdown.dropdown>
            </div>
          </.demo_section>
        <.demo_section
          title="Custom content"
          description="Use dropdown_custom for non-item content that should stay inside the menu panel."
          code={~S'''
          <.dropdown id="dd-custom" label="Account">
            <.dropdown_custom><p>Signed in as ada@example.com</p></.dropdown_custom>
          </.dropdown>
          '''}
        >
          <Dropdown.dropdown id="dd-custom" label="Account">
            <Dropdown.dropdown_custom class="docs-dropdown-custom">
              <p data-part="custom-content">Signed in as ada@example.com</p>
            </Dropdown.dropdown_custom>
          </Dropdown.dropdown>
        </.demo_section>
      </article>

      <article :if={@current == "command"} class="docs-body">
        <h1>Command palette</h1>
        <p>
          A ⌘K dialog: a modal combobox over a listbox of actions, on the shared overlay
          runtime. The component owns opening, the focus trap, keyboard traversal, and
          <code>aria-activedescendant</code>; <strong>it never filters its own children</strong>
          — it renders exactly the items you hand it and reports the query upward, so search
          can come from a database, an index, or memory.
        </p>
        <.demo_section
          title="Searchable actions"
          description="Press ⌘K (Ctrl+K on Windows/Linux) or use the button. Type to filter, ↑/↓ to move, Enter to choose, Esc to close. Filtering happens in the LiveView — the palette itself renders whatever it is given."
          code={command_demo_code()}
        >
          <div class="docs-row">
            <Button.button phx-click={LanternUI.open_dialog("cmd-demo")}>
              Search commands…
              <Command.command_shortcut>⌘K</Command.command_shortcut>
            </Button.button>
            <p id="command-selection" class="docs-confirm-status" role="status">
              <%= case @command_selection do %>
                <% nil -> %>
                  Nothing chosen yet — open the palette and press Enter on a row.
                <% {value, label} -> %>
                  Selected <strong>{label}</strong> (<code>{value}</code>)
              <% end %>
            </p>
          </div>

          <Command.command
            id="cmd-demo"
            label="Demo command palette"
            placeholder="Type a command or search…"
            on_search="command_search"
            on_select="command_select"
            debounce={120}
          >
            <%= for {{group, items}, index} <- Enum.with_index(@command_groups) do %>
              <Command.command_separator :if={index > 0} />
              <Command.command_group label={group}>
                <Command.command_item
                  :for={cmd <- items}
                  value={cmd.value}
                  disabled={Map.get(cmd, :disabled, false)}
                >
                  <:icon><Icon.icon name={cmd.icon} /></:icon>
                  {cmd.label}
                  <:description>{cmd.description}</:description>
                  <:shortcut :if={cmd.shortcut}>{cmd.shortcut}</:shortcut>
                </Command.command_item>
              </Command.command_group>
            <% end %>
            <Command.command_empty :if={@command_groups == []}>
              No commands match “{@command_query}”.
            </Command.command_empty>

            <:footer>
              <span>↑↓ to navigate · ↵ to select · esc to close</span>
            </:footer>
          </Command.command>
        </.demo_section>
      </article>

      <article :if={@current == "breadcrumb"} class="docs-body">
        <h1>Breadcrumb</h1>
        <p>
          Path navigation for file/tree UIs — a lantern-ui extension. Items render as links,
          event buttons, or the <code>aria-current</code> page.
        </p>
        <.demo_section
          title="Path"
          description="href / navigate / phx-click on intermediate items; current marks the page."
          code={~S'''
          <.breadcrumb>
            <:item href="#">my-bucket</:item>
            <:item href="#">photos</:item>
            <:item href="#">2026</:item>
            <:item current>07-vacation</:item>
          </.breadcrumb>
          '''}
        >
          <Breadcrumb.breadcrumb>
            <:item href="#">my-bucket</:item>
            <:item href="#">photos</:item>
            <:item href="#">2026</:item>
            <:item current>07-vacation</:item>
          </Breadcrumb.breadcrumb>
        </.demo_section>
      </article>

      <article :if={@current == "empty-state"} class="docs-body">
        <h1>Empty state</h1>
        <p>Quiet zero states for tables, lists, and panels — a lantern-ui extension.</p>
        <.demo_section
          title="With actions"
          description="icon, title, body copy, and one or more :action slots."
          code={~S'''
          <.empty_state icon="folder-open" title="No objects">
            Drop files here to upload them, or create a folder to get organized.
            <:action><.button size="sm">Upload</.button></:action>
            <:action><.button size="sm" variant="ghost">New folder</.button></:action>
          </.empty_state>
          '''}
        >
          <EmptyState.empty_state icon="folder-open" title="No objects">
            Drop files here to upload them, or create a folder to get organized.
            <:action><Button.button size="sm">Upload</Button.button></:action>
            <:action><Button.button size="sm" variant="ghost">New folder</Button.button></:action>
          </EmptyState.empty_state>
        </.demo_section>
      </article>

      <article :if={@current == "timeline"} class="docs-body">
        <h1>Timeline</h1>
        <p>
          Vertical event sequence with a marker rail:
          <code>timeline/1</code> plus <code>timeline_item/1</code>. Ordered list markup;
          pure server render, no JS hook.
        </p>
        <.demo_section
          title="Basic"
          description="Three items with status :done / :active / :pending plus label, at, and title. The state word always renders, so items stay legible in grayscale."
          code={~S'''
          <.timeline>
            <.timeline_item status={:done} label="Deployed" at="2h ago" title="enventory" />
            <.timeline_item status={:active} label="Deploying" at="40s" title="foodfeed" />
            <.timeline_item status={:pending} label="Queued" at="just now" title="skusync" />
          </.timeline>
          '''}
        >
          <Timeline.timeline>
            <Timeline.timeline_item status={:done} label="Deployed" at="2h ago" title="enventory" />
            <Timeline.timeline_item status={:active} label="Deploying" at="40s" title="foodfeed" />
            <Timeline.timeline_item status={:pending} label="Queued" at="just now" title="skusync" />
          </Timeline.timeline>
        </.demo_section>
        <.demo_section
          title="Statuses"
          description="One item per status, including :danger and :neutral."
          code={~S'''
          <.timeline>
            <.timeline_item status={:done} label="Deployed" title="done" />
            <.timeline_item status={:active} label="Deploying" title="active" />
            <.timeline_item status={:pending} label="Queued" title="pending" />
            <.timeline_item status={:danger} label="Failed" title="danger" />
            <.timeline_item status={:neutral} label="Note" title="neutral" />
          </.timeline>
          '''}
        >
          <Timeline.timeline>
            <Timeline.timeline_item status={:done} label="Deployed" title="done" />
            <Timeline.timeline_item status={:active} label="Deploying" title="active" />
            <Timeline.timeline_item status={:pending} label="Queued" title="pending" />
            <Timeline.timeline_item status={:danger} label="Failed" title="danger" />
            <Timeline.timeline_item status={:neutral} label="Note" title="neutral" />
          </Timeline.timeline>
        </.demo_section>
        <.demo_section
          title="Collapsible detail"
          description="Deployment-log shape: title is the summary, :detail is the output. open starts expanded."
          code={~S'''
          <.timeline>
            <.timeline_item status={:done} label="Deployed" at="2h ago" title="enventory">
              <:detail>
                <pre>==> Building release
          Compiling 8 files (.ex)
          Generated enventory app
          ==> Deployed to production</pre>
              </:detail>
            </.timeline_item>
            <.timeline_item status={:active} label="Deploying" at="40s" title="foodfeed" open>
              <:detail>
                <pre>==> Building release
          Compiling 12 files (.ex)
          Generated foodfeed app</pre>
              </:detail>
            </.timeline_item>
          </.timeline>
          '''}
        >
          <Timeline.timeline>
            <Timeline.timeline_item status={:done} label="Deployed" at="2h ago" title="enventory">
              <:detail>
                <pre>==> Building release
          Compiling 8 files (.ex)
          Generated enventory app
          ==> Deployed to production</pre>
              </:detail>
            </Timeline.timeline_item>
            <Timeline.timeline_item status={:active} label="Deploying" at="40s" title="foodfeed" open>
              <:detail>
                <pre>==> Building release
          Compiling 12 files (.ex)
          Generated foodfeed app</pre>
              </:detail>
            </Timeline.timeline_item>
          </Timeline.timeline>
        </.demo_section>
        <.demo_section
          title="Leading labels"
          description="label_position={:leading} on the container places timestamps in their own column; items inherit it."
          code={~S'''
          <.timeline label_position={:leading}>
            <.timeline_item status={:done} label="Deployed" at="2h ago" title="enventory" />
            <.timeline_item status={:active} label="Deploying" at="40s" title="foodfeed" />
            <.timeline_item status={:pending} label="Queued" at="just now" title="skusync" />
          </.timeline>
          '''}
        >
          <Timeline.timeline label_position={:leading}>
            <Timeline.timeline_item status={:done} label="Deployed" at="2h ago" title="enventory" />
            <Timeline.timeline_item status={:active} label="Deploying" at="40s" title="foodfeed" />
            <Timeline.timeline_item status={:pending} label="Queued" at="just now" title="skusync" />
          </Timeline.timeline>
        </.demo_section>
        <.demo_section
          title="Marker slot"
          description=":marker replaces the status dot or icon. Avatars and other custom glyphs are supported."
          code={~S'''
          <.timeline>
            <.timeline_item status={:done} label="Merged" at="3h ago" title="PR #412">
              <:marker>
                <span class="docs-timeline-avatar">GO</span>
              </:marker>
            </.timeline_item>
            <.timeline_item status={:active} label="Reviewing" at="12m" title="PR #418">
              <:marker>
                <span class="docs-timeline-avatar">AL</span>
              </:marker>
            </.timeline_item>
            <.timeline_item status={:pending} label="Queued" at="just now" title="PR #421" />
          </.timeline>
          '''}
        >
          <Timeline.timeline>
            <Timeline.timeline_item status={:done} label="Merged" at="3h ago" title="PR #412">
              <:marker>
                <span class="docs-timeline-avatar">GO</span>
              </:marker>
            </Timeline.timeline_item>
            <Timeline.timeline_item status={:active} label="Reviewing" at="12m" title="PR #418">
              <:marker>
                <span class="docs-timeline-avatar">AL</span>
              </:marker>
            </Timeline.timeline_item>
            <Timeline.timeline_item status={:pending} label="Queued" at="just now" title="PR #421" />
          </Timeline.timeline>
        </.demo_section>
      </article>

      <article :if={@current == "chat-kit"} class="docs-body">
        <h1>Chat kit</h1>
        <p>
          A composed conversation demo using avatars, message rows, and an accessible
          follow-aware message scroller. The controls make the scroll and busy states
          visible without background work.
        </p>
        <.demo_section
          title="Conversation"
          description="A fixed-height transcript keeps MessageScroller as the inner scroll region; append, stream, and reset are ordinary LiveView events."
          code={~S'''
          <.message_scroller id="chat-kit-demo" label="Chat kit conversation" follow={true} busy={@chat_demo_busy}>
            <.message_scroller_item
              :for={{message, index} <- Enum.with_index(@chat_demo_messages)}
              message_id={message.id}
              scroll_anchor={index == length(@chat_demo_messages) - 1 and not @chat_demo_busy}
            >
              <.message align={message.align} tone={message.tone}>
                <:avatar><.avatar initials={message.initials} /></:avatar>
                <:header>{message.header}</:header>
                {message.body}
                <:footer>{message.footer}</:footer>
              </.message>
            </.message_scroller_item>
            <.message_scroller_item :if={@chat_demo_busy} message_id="chat-streaming" scroll_anchor>
              <.message align="start" tone="surface">
                <:avatar><.avatar initials="LU" /></:avatar>
                <:header>Assistant - now</:header>
                Assistant is typing...
              </.message>
            </.message_scroller_item>
          </.message_scroller>
          '''}
        >
          <div class="docs-row docs-chat-controls">
            <Button.button size="sm" phx-click="chat_append_reply">Append reply</Button.button>
            <Button.button size="sm" variant="outline" phx-click="chat_toggle_streaming">
              Toggle streaming
            </Button.button>
            <Button.button size="sm" variant="ghost" phx-click="chat_reset">Reset</Button.button>
          </div>
          <div class="docs-chat-frame">
            <MessageScroller.message_scroller
              id="chat-kit-demo"
              label="Chat kit conversation"
              follow={true}
              busy={@chat_demo_busy}
            >
              <MessageScroller.message_scroller_item
                :for={{message, index} <- Enum.with_index(@chat_demo_messages)}
                id={message.id}
                message_id={message.id}
                scroll_anchor={index == length(@chat_demo_messages) - 1 and not @chat_demo_busy}
              >
                <Message.message align={message.align} tone={message.tone}>
                  <:avatar><Avatar.avatar initials={message.initials} /></:avatar>
                  <:header>{message.header}</:header>
                  <p :for={paragraph <- String.split(message.body, "\n\n")}>{paragraph}</p>
                  <:footer>{message.footer}</:footer>
                </Message.message>
              </MessageScroller.message_scroller_item>
              <MessageScroller.message_scroller_item
                :if={@chat_demo_busy}
                id="chat-streaming"
                message_id="chat-streaming"
                scroll_anchor
              >
                <Message.message align="start" tone="surface">
                  <:avatar><Avatar.avatar initials="LU" /></:avatar>
                  <:header>Assistant - now</:header>
                  <span class="docs-chat-typing">Assistant is typing...</span>
                </Message.message>
              </MessageScroller.message_scroller_item>
            </MessageScroller.message_scroller>
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "area-chart"} class="docs-body">
        <h1>Area chart</h1>
        <p>
          Server-rendered SVG — geometry computed in Elixir, one hover hook, no chart
          library. Catmull-Rom smoothing under a density threshold.
        </p>
        <div class="docs-demo">
          <Charts.area_chart id="ch-area" series={@area} height={220} value_format={:currency} />
        </div>
        <.code_block id="code-area-chart" code={@snippets["area-chart"]} />
      </article>

      <article :if={@current == "line-chart"} class="docs-body">
        <h1>Line chart</h1>
        <p>Multi-series line chart with a shared crosshair + tooltip and a legend.</p>
        <div class="docs-demo">
          <Charts.line_chart id="ch-line" series={@line} height={220} />
        </div>
        <.code_block id="code-line-chart" code={@snippets["line-chart"]} />
      </article>

      <article :if={@current == "bar-chart"} class="docs-body">
        <h1>Bar chart</h1>
        <p>Categorical bars with value labels.</p>
        <div class="docs-demo">
          <Charts.bar_chart id="ch-bar" series={@bars} height={200} />
        </div>
        <.code_block id="code-bar-chart" code={@snippets["bar-chart"]} />
      </article>

      <article :if={@current == "badge"} class="docs-body">
        <h1>Badge</h1>
        <p>Status pills — colors × variants × sizes.</p>
        <.demo_section
          title="Colors"
          description="neutral, primary, accent, info, success, warning, danger."
          code={~S'''
          <.badge :for={c <- ~w(neutral primary accent success warning danger)} color={c}>
            {c}
          </.badge>
          '''}
        >
          <div class="docs-row">
            <Badge.badge :for={c <- ~w(neutral primary accent success warning danger)} color={c}>
              {c}
            </Badge.badge>
          </div>
        </.demo_section>
        <.demo_section
          title="Variants"
          description="soft (default), solid, and outline."
          code={~S'''
          <.badge :for={v <- ~w(soft solid outline)} variant={v} color="accent">{v}</.badge>
          '''}
        >
          <div class="docs-row">
            <Badge.badge :for={v <- ~w(soft solid outline)} variant={v} color="accent">
              {v}
            </Badge.badge>
          </div>
        </.demo_section>
        <.demo_section
          title="Sizes"
          description="sm, md (default), lg."
          code={~S'''
          <.badge size="sm" color="success">sm</.badge>
          <.badge size="md" color="success">md</.badge>
          <.badge size="lg" color="danger">lg</.badge>
          '''}
        >
          <div class="docs-row">
            <Badge.badge size="sm" color="success">sm</Badge.badge>
            <Badge.badge size="md" color="success">md</Badge.badge>
            <Badge.badge size="lg" color="danger">lg</Badge.badge>
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "stat"} class="docs-body">
        <h1>Stat cards</h1>
        <p>
          Compact summary metrics extracted from the data-table overview. Use
          <code>stat_card/1</code> alone or compose a responsive group with
          <code>stat_grid/1</code>. Callers own calculations, formatting, trends, and
          navigation state.
        </p>
        <.demo_section
          title="Standalone metric"
          description="Without href the card is a non-interactive div; subtitle adds quiet context."
          code={~S'''
          <.stat_card
            label="Queued jobs"
            value={18}
            subtitle="4 require attention"
            icon="hero-inbox"
          />
          '''}
        >
          <div style="max-width: 18rem;">
            <Stat.stat_card
              label="Queued jobs"
              value={18}
              subtitle="4 require attention"
              icon="hero-inbox"
            />
          </div>
        </.demo_section>

        <.demo_section
          title="Responsive grid"
          description="Cards share a minimum basis, wrap without caller breakpoints, and only become links when href is present."
          code={~S'''
          <.stat_grid aria-label="Order summary">
            <:stat label="Open orders" value={42} />
            <:stat label="Shipped" value={128} href={~p"/orders?status=shipped"} />
            <:stat label="Long value" value="pending-warehouse-confirmation-2026-07" />
            <:stat label="Revenue" value="$12,482.19" subtitle="Last 30 days" />
          </.stat_grid>
          '''}
        >
          <Stat.stat_grid aria-label="Order summary">
            <:stat label="Open orders" value={42} />
            <:stat label="Shipped" value={128} href="/components/data-table" />
            <:stat label="Long value" value="pending-warehouse-confirmation-2026-07" />
            <:stat label="Revenue" value="$12,482.19" subtitle="Last 30 days" />
          </Stat.stat_grid>
        </.demo_section>
      </article>

      <article :if={@current == "table"} class="docs-body">
        <h1>Table</h1>
        <p>
          The presentational family <code>data_table</code> composes — use it directly
          for simple, non-Flop tables.
        </p>
        <.demo_section
          title="Basic"
          description="table_head / table_body / table_row with :col and :cell slots; selected highlights a row."
          code={~S'''
          <.table>
            <.table_head>
              <:col>Name</:col>
              <:col>Role</:col>
              <:col class="lui-th-num">Commits</:col>
            </.table_head>
            <.table_body>
              <.table_row>
                <:cell>Ada Lovelace</:cell>
                <:cell>Analyst</:cell>
                <:cell class="lui-td-num">1,842</:cell>
              </.table_row>
              <.table_row selected>
                <:cell>Grace Hopper</:cell>
                <:cell>Rear Admiral</:cell>
                <:cell class="lui-td-num">2,214</:cell>
              </.table_row>
            </.table_body>
          </.table>
          '''}
        >
          <Table.table>
            <Table.table_head>
              <:col>Name</:col>
              <:col>Role</:col>
              <:col class="lui-th-num">Commits</:col>
            </Table.table_head>
            <Table.table_body>
              <Table.table_row>
                <:cell>Ada Lovelace</:cell>
                <:cell>Analyst</:cell>
                <:cell class="lui-td-num">1,842</:cell>
              </Table.table_row>
              <Table.table_row selected>
                <:cell>Grace Hopper</:cell>
                <:cell>Rear Admiral</:cell>
                <:cell class="lui-td-num">2,214</:cell>
              </Table.table_row>
            </Table.table_body>
          </Table.table>
        </.demo_section>
      </article>

      <article :if={@current == "tabs"} class="docs-body">
        <h1>Tabs</h1>
        <p>
          Segmented or underline tab lists with server-driven active state; tabs given
          <code>patch</code> render as links so tab state can live in the URL.
        </p>
        <.demo_section
          title="Segmented with panels"
          description="Default segmented list; panels show based on the active assign."
          code={~S'''
          <.tabs id="demo-tabs">
            <.tabs_list active_tab={@demo_tab}>
              <:tab name="one" phx-click="demo_tab">First <.badge size="sm">12</.badge></:tab>
              <:tab name="two" phx-click="demo_tab">Second</:tab>
              <:tab name="three" phx-click="demo_tab">Third</:tab>
            </.tabs_list>
            <.tabs_panel name="one" active={@demo_tab == "one"}>First panel content.</.tabs_panel>
            <.tabs_panel name="two" active={@demo_tab == "two"}>Second panel content.</.tabs_panel>
            <.tabs_panel name="three" active={@demo_tab == "three"}>Third panel content.</.tabs_panel>
          </.tabs>
          '''}
        >
          <Tabs.tabs id="demo-tabs">
            <Tabs.tabs_list active_tab={@demo_tab}>
              <:tab name="one" phx-click="demo_tab">
                First <Badge.badge size="sm">12</Badge.badge>
              </:tab>
              <:tab name="two" phx-click="demo_tab">Second</:tab>
              <:tab name="three" phx-click="demo_tab">Third</:tab>
            </Tabs.tabs_list>
            <Tabs.tabs_panel name="one" active={@demo_tab == "one"}>
              First panel content.
            </Tabs.tabs_panel>
            <Tabs.tabs_panel name="two" active={@demo_tab == "two"}>
              Second panel content.
            </Tabs.tabs_panel>
            <Tabs.tabs_panel name="three" active={@demo_tab == "three"}>
              Third panel content.
            </Tabs.tabs_panel>
          </Tabs.tabs>
        </.demo_section>
        <.demo_section
          title="Underline variant"
          description="variant=&quot;underline&quot; with size sm — good for page-level tabs."
          code={~S'''
          <.tabs_list active_tab="b" variant="underline" size="sm">
            <:tab name="a">Underline</:tab>
            <:tab name="b">Variant</:tab>
          </.tabs_list>
          '''}
        >
          <Tabs.tabs_list active_tab="b" variant="underline" size="sm">
            <:tab name="a">Underline</:tab>
            <:tab name="b">Variant</:tab>
          </Tabs.tabs_list>
        </.demo_section>
      </article>

      <article :if={@current == "select"} class="docs-body">
        <h1>Select</h1>
        <p>
          FormField-aware select (Fluxon API): rich listbox with keyboard nav +
          type-ahead over a hidden input, or a <code>native</code> fallback.
        </p>
        <.demo_section
          title="Basic"
          description="Rich listbox with label, options, and placeholder."
          code={~S'''
          <.select
            name="channel"
            label="Channel"
            options={[{"eBay", "ebay"}, {"Shopify", "shopify"}, {"Direct", "direct"}]}
            placeholder="Pick a channel"
          />
          '''}
        >
          <Select.select
            id="sel-1"
            name="channel"
            label="Channel"
            options={[{"eBay", "ebay"}, {"Shopify", "shopify"}, {"Direct", "direct"}]}
            placeholder="Pick a channel"
          />
        </.demo_section>
        <.demo_section
          title="With value"
          description="Controlled value selects the matching option."
          code={~S'''
          <.select
            name="status"
            label="Status"
            value="active"
            options={[{"Active", "active"}, {"Archived", "archived"}]}
          />
          '''}
        >
          <Select.select
            id="sel-2"
            name="status"
            label="Status"
            value="active"
            options={[{"Active", "active"}, {"Archived", "archived"}]}
          />
        </.demo_section>
        <.demo_section
          title="Multiple"
          description="multiple keeps the panel open and submits name[] for each selection."
          code={~S'''
          <.select
            name="tags"
            label="Multiple"
            multiple
            value={["elixir", "phoenix"]}
            options={[
              {"Elixir", "elixir"},
              {"Phoenix", "phoenix"},
              {"LiveView", "liveview"},
              {"Ecto", "ecto"}
            ]}
          />
          '''}
        >
          <Select.select
            id="sel-5"
            name="tags"
            label="Multiple"
            multiple
            value={["elixir", "phoenix"]}
            options={[
              {"Elixir", "elixir"},
              {"Phoenix", "phoenix"},
              {"LiveView", "liveview"},
              {"Ecto", "ecto"}
            ]}
          />
        </.demo_section>
        <.demo_section
          title="Searchable"
          description="searchable adds a filter box in the listbox (or set search_threshold)."
          code={~S'''
          <.select
            name="country"
            label="Searchable"
            searchable
            placeholder="Pick a country"
            options={["Argentina", "Australia", "Brazil", "Canada", "Denmark"]}
          />
          '''}
        >
          <Select.select
            id="sel-6"
            name="country"
            label="Searchable"
            searchable
            placeholder="Pick a country"
            options={[
              "Argentina",
              "Australia",
              "Brazil",
              "Canada",
              "Denmark",
              "Estonia",
              "France",
              "Germany",
              "Iceland",
              "Japan",
              "Mexico",
              "Netherlands",
              "Norway",
              "Portugal",
              "Sweden",
              "United States"
            ]}
          />
        </.demo_section>
        <.demo_section
          title="Multi + search"
          description="Combine multiple and searchable for large option sets."
          code={~S'''
          <.select
            name="team"
            label="Multi + search"
            multiple
            searchable
            options={["Ada", "Alan", "Barbara", "Donald", "Edsger", "Grace", "Ken", "Radia"]}
          />
          '''}
        >
          <Select.select
            id="sel-7"
            name="team"
            label="Multi + search"
            multiple
            searchable
            options={["Ada", "Alan", "Barbara", "Donald", "Edsger", "Grace", "Ken", "Radia"]}
          />
        </.demo_section>
        <.demo_section
          title="Native"
          description="native renders a plain &lt;select&gt; — useful for dense tool UIs."
          code={~S'''
          <.select name="size" label="Native" native value={25} options={[10, 25, 50]} />
          '''}
        >
          <Select.select
            id="sel-3"
            name="size"
            label="Native"
            native
            value={25}
            options={[10, 25, 50]}
          />
        </.demo_section>
        <.demo_section
          title="Error state"
          description="Same FormField / errors list pattern as input."
          code={~S'''
          <.select name="bad" label="With error" options={["a"]} errors={["can't be blank"]} />
          '''}
        >
          <Select.select
            id="sel-4"
            name="bad"
            label="With error"
            options={["a"]}
            errors={["can't be blank"]}
          />
        </.demo_section>
      </article>

      <article :if={@current == "pagination"} class="docs-body">
        <h1>Pagination</h1>
        <p>
          Pager + page-size control, duck-typed to <code>Flop.Meta</code> (no flop
          dependency) — all patch navigation. Fluxon has no equivalent; this replaces
          flop_phoenix's pager.
        </p>
        <.demo_section
          title="Basic"
          description="Pass a meta map (current_page, total_pages, page_size, total_count) and a patch_fn."
          code={~S'''
          <.pagination
            meta={%{current_page: 5, total_pages: 20, page_size: 25, total_count: 487}}
            patch_fn={fn p -> ~p"/orders?#{p}" end}
          />
          '''}
        >
          <Pagination.pagination
            id="pg-demo"
            meta={%{current_page: 5, total_pages: 20, page_size: 25, total_count: 487}}
            patch_fn={fn params -> "/components/pagination?" <> Plug.Conn.Query.encode(params) end}
          />
        </.demo_section>
        <.demo_section
          title="Edges & small sets"
          description="Prev is disabled on the first page, next on the last; few pages drop the gaps."
          code={~S'''
          <.pagination meta={%{current_page: 1, total_pages: 8, page_size: 25, total_count: 190}} patch_fn={pf} />
          <.pagination meta={%{current_page: 3, total_pages: 3, page_size: 25, total_count: 62}} patch_fn={pf} />
          '''}
        >
          <div class="docs-row" style="flex-direction: column; align-items: stretch; gap: 1rem;">
            <Pagination.pagination
              id="pg-first"
              meta={%{current_page: 1, total_pages: 8, page_size: 25, total_count: 190}}
              patch_fn={fn params -> "/components/pagination?" <> Plug.Conn.Query.encode(params) end}
            />
            <Pagination.pagination
              id="pg-small"
              meta={%{current_page: 3, total_pages: 3, page_size: 25, total_count: 62}}
              patch_fn={fn params -> "/components/pagination?" <> Plug.Conn.Query.encode(params) end}
            />
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "switch"} class="docs-body">
        <h1>Switch</h1>
        <p>
          Toggle switch for binary settings. Sizes <code>sm</code>/<code>md</code>/<code>lg</code>,
          with optional label and description.
        </p>
        <.demo_section
          title="Basic"
          description="Unchecked and checked. A hidden input always submits the off value."
          code={~S'''
          <.switch name="sw_off" label="Unchecked" />
          <.switch name="sw_on" checked label="Checked" />
          '''}
        >
          <div class="docs-row" style="flex-direction: column; align-items: flex-start; gap: .75rem;">
            <Switch.switch id="sw-1" name="sw_off" label="Unchecked" />
            <Switch.switch id="sw-2" name="sw_on" checked label="Checked" />
          </div>
        </.demo_section>
        <.demo_section
          title="Sizes"
          description="sm, md (default), and lg."
          code={~S'''
          <.switch name="sw_sm" size="sm" label="sm" checked />
          <.switch name="sw_md" size="md" label="md" checked />
          <.switch name="sw_lg" size="lg" label="lg" checked />
          '''}
        >
          <div class="docs-row">
            <Switch.switch id="sw-sm" name="sw_sm" size="sm" label="sm" checked />
            <Switch.switch id="sw-md" name="sw_md" size="md" label="md" checked />
            <Switch.switch id="sw-lg" name="sw_lg" size="lg" label="lg" checked />
          </div>
        </.demo_section>
        <.demo_section
          title="Label & description"
          description="description sits under the label for longer helper copy."
          code={~S'''
          <.switch
            name="sw_desc"
            checked
            label="Email notifications"
            description="At most one email per day."
          />
          '''}
        >
          <Switch.switch
            id="sw-4"
            name="sw_desc"
            checked
            label="Email notifications"
            description="At most one email per day."
          />
        </.demo_section>
        <.demo_section
          title="Disabled"
          description="Non-interactive switch."
          code={~S'''
          <.switch name="sw_dis" label="Disabled" disabled />
          '''}
        >
          <Switch.switch id="sw-3" name="sw_dis" label="Disabled" disabled />
        </.demo_section>
      </article>

      <article :if={@current == "radio"} class="docs-body">
        <h1>Radio</h1>
        <p>
          Exclusive single selection — <code>list</code> (default) or <code>cards</code> variant.
        </p>
        <.demo_section
          title="List"
          description="Default list layout; sublabel annotates an option."
          code={~S'''
          <.radio name="plan" value="pro" label="Plan" variant="list">
            <:radio value="basic" label="Basic" />
            <:radio value="pro" label="Pro" sublabel="Popular" />
            <:radio value="enterprise" label="Enterprise" />
          </.radio>
          '''}
        >
          <Radio.radio id="rd-list" name="plan" value="pro" label="Plan" variant="list">
            <:radio value="basic" label="Basic" />
            <:radio value="pro" label="Pro" sublabel="Popular" />
            <:radio value="enterprise" label="Enterprise" />
          </Radio.radio>
        </.demo_section>
        <.demo_section
          title="Cards"
          description="Card layout with optional per-option description."
          code={~S'''
          <.radio name="tier" value="team" label="Tier" variant="cards">
            <:radio value="free" label="Free" description="Hobby projects" />
            <:radio value="team" label="Team" description="Collaboration" />
            <:radio value="scale" label="Scale" description="Growing teams" />
          </.radio>
          '''}
        >
          <Radio.radio id="rd-cards" name="tier" value="team" label="Tier" variant="cards">
            <:radio value="free" label="Free" description="Hobby projects" />
            <:radio value="team" label="Team" description="Collaboration" />
            <:radio value="scale" label="Scale" description="Growing teams" />
          </Radio.radio>
        </.demo_section>
      </article>

      <article :if={@current == "textarea"} class="docs-body">
        <h1>Textarea</h1>
        <p>
          Multi-line text input with the same label, help text, and error chrome as
          <code>input</code>.
        </p>
        <.demo_section
          title="Basic"
          description="Label and placeholder."
          code={~S'''
          <.textarea name="notes" label="Notes" placeholder="Write something…" />
          '''}
        >
          <Textarea.textarea
            id="ta-1"
            name="notes"
            label="Notes"
            placeholder="Write something…"
            value={nil}
          />
        </.demo_section>
        <.demo_section
          title="Help text"
          description="help_text under the control, same as input."
          code={~S'''
          <.textarea name="bio" label="Bio" help_text="A short intro for your profile." />
          '''}
        >
          <Textarea.textarea
            id="ta-2"
            name="bio"
            label="Bio"
            help_text="A short intro for your profile."
            value={nil}
          />
        </.demo_section>
        <.demo_section
          title="Error state"
          description="Invalid border and error list."
          code={~S'''
          <.textarea
            name="bad"
            label="With error"
            value="too short"
            errors={["is too short (minimum is 20 characters)"]}
          />
          '''}
        >
          <Textarea.textarea
            id="ta-3"
            name="bad"
            label="With error"
            value="too short"
            errors={["is too short (minimum is 20 characters)"]}
          />
        </.demo_section>
        <.demo_section
          title="Disabled"
          description="Read-only presentation via disabled."
          code={~S'''
          <.textarea name="ro" label="Disabled" value="Read only content" disabled />
          '''}
        >
          <Textarea.textarea
            id="ta-4"
            name="ro"
            label="Disabled"
            value="Read only content"
            disabled
          />
        </.demo_section>
      </article>

      <article :if={@current == "alert"} class="docs-body">
        <h1>Alert</h1>
        <p>
          Inline status alerts — colors, optional close button, and hideable icon.
        </p>
        <.demo_section
          title="Colors"
          description="neutral, info, success, warning, danger — each with a default icon."
          code={~S'''
          <.alert color="neutral" title="Note">A neutral status message.</.alert>
          <.alert color="info" title="Info">Something you should know.</.alert>
          <.alert color="success" title="Saved">Your changes were stored.</.alert>
          <.alert color="warning" title="Careful">Review before continuing.</.alert>
          <.alert color="danger" title="Failed">The request could not be completed.</.alert>
          '''}
        >
          <Alert.alert color="neutral" title="Note">A neutral status message.</Alert.alert>
          <Alert.alert color="info" title="Info">Something you should know.</Alert.alert>
          <Alert.alert color="success" title="Saved">Your changes were stored.</Alert.alert>
          <Alert.alert color="warning" title="Careful">Review before continuing.</Alert.alert>
          <Alert.alert color="danger" title="Failed">The request could not be completed.</Alert.alert>
        </.demo_section>
        <.demo_section
          title="Title & close"
          description="hide_close={false} shows a dismiss button (JS.hide on the alert id)."
          code={~S'''
          <.alert id="alert-close" color="warning" title="Unsaved" hide_close={false}>
            Discard or save before leaving.
          </.alert>
          '''}
        >
          <Alert.alert id="alert-close" color="warning" title="Unsaved" hide_close={false}>
            Discard or save before leaving.
          </Alert.alert>
        </.demo_section>
        <.demo_section
          title="Hide icon"
          description="hide_icon removes the leading icon entirely."
          code={~S'''
          <.alert color="info" title="No icon" hide_icon>
            Icon hidden via hide_icon.
          </.alert>
          '''}
        >
          <Alert.alert color="info" title="No icon" hide_icon>
            Icon hidden via <code>hide_icon</code>.
          </Alert.alert>
        </.demo_section>
        <.demo_section
          title="Custom icon"
          description="Pass an :icon slot to replace the default glyph."
          code={~S'''
          <.alert color="info" title="Custom icon">
            <:icon><.icon name="sparkles" /></:icon>
            Using the icon slot.
          </.alert>
          '''}
        >
          <Alert.alert color="info" title="Custom icon">
            <:icon><Icon.icon name="sparkles" /></:icon>
            Using the <code>:icon</code> slot.
          </Alert.alert>
        </.demo_section>
      </article>

      <article :if={@current == "loading"} class="docs-body">
        <h1>Loading</h1>
        <p>
          Inline loading indicator — a rotating ring or three staggered dots
          (bounce/fade/scale), in five sizes. CSS-only, no JS. Mirrors Fluxon's
          <code>loading/1</code>.
        </p>
        <.demo_section
          title="Variants"
          description="ring plus the three dot styles."
          code={~S'''
          <.loading variant="ring" />
          <.loading variant="dots-bounce" />
          <.loading variant="dots-fade" />
          <.loading variant="dots-scale" />
          '''}
        >
          <div style="display:flex; align-items:center; gap:2rem;">
            <Loading.loading variant="ring" />
            <Loading.loading variant="dots-bounce" />
            <Loading.loading variant="dots-fade" />
            <Loading.loading variant="dots-scale" />
          </div>
        </.demo_section>
        <.demo_section
          title="Sizes"
          description="xs through xl scale ring diameter and dot size."
          code={~S'''
          <.loading size="xs" />
          <.loading size="sm" />
          <.loading size="md" />
          <.loading size="lg" />
          <.loading size="xl" />
          '''}
        >
          <div style="display:flex; align-items:center; gap:2rem;">
            <Loading.loading size="xs" />
            <Loading.loading size="sm" />
            <Loading.loading size="md" />
            <Loading.loading size="lg" />
            <Loading.loading size="xl" />
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "skeleton"} class="docs-body">
        <h1>Skeleton</h1>
        <p>
          A decorative, dependency-free loading placeholder. Match the geometry of the
          content it replaces, hide the placeholder from assistive technology, and put
          <code>aria-busy="true"</code> plus an accessible label on the surrounding region.
          Animation is disabled automatically when reduced motion is requested.
        </p>
        <.demo_section
          title="Profile loading state"
          description="Compose the same primitive into avatar, title, metadata, and body shapes."
          code={~S'''
          <section aria-busy="true" aria-label="Loading profile">
            <.skeleton style="width: 3rem; height: 3rem; border-radius: 999px;" />
            <.skeleton style="width: 12rem; height: 1rem;" />
            <.skeleton style="width: 8rem; height: .75rem;" />
            <.skeleton style="height: 5rem;" />
          </section>
          '''}
        >
          <section class="docs-skeleton-card" aria-busy="true" aria-label="Loading profile">
            <Skeleton.skeleton class="docs-skeleton-avatar" />
            <div class="docs-skeleton-copy">
              <Skeleton.skeleton style="width: 12rem; height: 1rem;" />
              <Skeleton.skeleton style="width: 8rem; height: .75rem;" />
            </div>
            <Skeleton.skeleton class="docs-skeleton-block" />
          </section>
        </.demo_section>

        <.demo_section
          title="Inline geometry"
          description="class and style are intentionally the only geometry controls; content and timing remain caller-owned."
          code={~S'''
          <.skeleton />
          <.skeleton style="width: 65%;" />
          <.skeleton style="width: 35%; height: .75rem;" />
          '''}
        >
          <div class="docs-skeleton-lines" aria-busy="true" aria-label="Loading article summary">
            <Skeleton.skeleton />
            <Skeleton.skeleton style="width: 65%;" />
            <Skeleton.skeleton style="width: 35%; height: .75rem;" />
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "separator"} class="docs-body">
        <h1>Separator</h1>
        <p>Visual divider — horizontal, labeled, or vertical.</p>
        <.demo_section
          title="Horizontal"
          description="Default full-width rule."
          code={~S'''
          <.separator />
          '''}
        >
          <p style="margin: 0; font-size: .875rem; color: var(--lantern-fg-muted);">Above the line</p>
          <Separator.separator />
          <p style="margin: 0; font-size: .875rem; color: var(--lantern-fg-muted);">Below the line</p>
        </.demo_section>
        <.demo_section
          title="With text"
          description="Centered label on the rule — useful for “or” splits."
          code={~S'''
          <.separator text="or" />
          '''}
        >
          <Separator.separator text="or" />
        </.demo_section>
        <.demo_section
          title="Vertical"
          description="vertical splits adjacent columns."
          code={~S'''
          <.separator vertical />
          '''}
        >
          <div class="docs-row" style="align-items: stretch; gap: 1rem;">
            <p style="margin: 0; font-size: .875rem; color: var(--lantern-fg-muted); max-width: 12rem;">
              Left column with a short note about primary content.
            </p>
            <Separator.separator vertical />
            <p style="margin: 0; font-size: .875rem; color: var(--lantern-fg-muted); max-width: 12rem;">
              Right column for secondary detail or actions.
            </p>
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "tooltip"} class="docs-body">
        <h1>Tooltip</h1>
        <p>
          Hover/focus tips with placement and optional arrow. Content can be a string or a
          <code>:content</code> slot.
        </p>
        <.demo_section
          title="Placement"
          description="placement positions the tip relative to the trigger."
          code={~S'''
          <.tooltip id="tip-top" value="Placed on top" placement="top">
            <.button size="sm">Top</.button>
          </.tooltip>
          <.tooltip id="tip-bottom" value="Placed on bottom" placement="bottom">
            <.button size="sm">Bottom</.button>
          </.tooltip>
          '''}
        >
          <div class="docs-row">
            <Tooltip.tooltip id="tip-top" value="Placed on top" placement="top">
              <Button.button size="sm">Top</Button.button>
            </Tooltip.tooltip>
            <Tooltip.tooltip id="tip-bottom" value="Placed on bottom" placement="bottom">
              <Button.button size="sm">Bottom</Button.button>
            </Tooltip.tooltip>
          </div>
        </.demo_section>
        <.demo_section
          title="Rich content"
          description="Use the :content slot for markup inside the tip."
          code={~S'''
          <.tooltip id="tip-content" placement="top">
            <.button size="sm">Rich content</.button>
            <:content>
              <strong>Bold</strong> tip with <em>markup</em>
            </:content>
          </.tooltip>
          '''}
        >
          <div class="docs-row">
            <Tooltip.tooltip id="tip-content" placement="top">
              <Button.button size="sm">Rich content</Button.button>
              <:content>
                <strong>Bold</strong> tip with <em>markup</em>
              </:content>
            </Tooltip.tooltip>
          </div>
        </.demo_section>
        <.demo_section
          title="No arrow"
          description="arrow={false} removes the caret."
          code={~S'''
          <.tooltip id="tip-no-arrow" value="No arrow" placement="bottom" arrow={false}>
            <.button size="sm">No arrow</.button>
          </.tooltip>
          '''}
        >
          <div class="docs-row">
            <Tooltip.tooltip id="tip-no-arrow" value="No arrow" placement="bottom" arrow={false}>
              <Button.button size="sm">No arrow</Button.button>
            </Tooltip.tooltip>
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "toast"} class="docs-body">
        <h1>Toast</h1>
        <p>
          Stacked notifications via <code>toast_group</code> and
          <code>LanternUI.send_toast/4</code>. Fire one of each kind below.
        </p>
        <.demo_section
          title="Playground"
          description="Mount toast_group once, then send_toast from the LiveView."
          code={~S'''
          <Toast.toast_group id="demo-toasts" />

          <.button phx-click="demo_toast" phx-value-kind="info">Info</.button>
          <.button phx-click="demo_toast" phx-value-kind="success">Success</.button>
          <.button phx-click="demo_toast" phx-value-kind="warning">Warning</.button>
          <.button phx-click="demo_toast" phx-value-kind="danger">Danger</.button>
          '''}
        >
          <Toast.toast_group id="demo-toasts" placement={@toast_placement} />
          <div class="docs-row">
            <Button.button phx-click="demo_toast" phx-value-kind="info">Info</Button.button>
            <Button.button phx-click="demo_toast" phx-value-kind="success" color="success">
              Success
            </Button.button>
            <Button.button phx-click="demo_toast" phx-value-kind="warning" color="warning">
              Warning
            </Button.button>
            <Button.button phx-click="demo_toast" phx-value-kind="danger" color="danger">
              Danger
            </Button.button>
          </div>
        </.demo_section>

        <.demo_section
          title="Placement"
          description="Any corner or edge-center. Pick one, then fire a toast — it enters from the nearest edge."
          code={~S'''
          <Toast.toast_group placement="bottom-center" />
          '''}
        >
          <div class="docs-row">
            <Button.button
              :for={p <- ~w(top-left top-center top-right bottom-left bottom-center bottom-right)}
              size="sm"
              variant={if @toast_placement == p, do: "solid", else: "outline"}
              phx-click="set_toast_placement"
              phx-value-placement={p}
            >
              {p}
            </Button.button>
          </div>
        </.demo_section>
      </article>

      <article :if={@current == "sheet"} class="docs-body">
        <h1>Sheet</h1>
        <p>
          Slide-over panel (drawer) that enters from a screen edge. Shares the modal's
          <code>open_dialog</code>/<code>close_dialog</code> runtime with focus trap and Escape/backdrop dismissal.
        </p>
        <.demo_section
          title="Trigger & content"
          description="A button opens the sheet; it shares the modal's open_dialog/close_dialog runtime."
          code={~S'''
          <.button phx-click={open_dialog("settings")}>Open sheet</.button>

          <.sheet id="settings" title="Edit settings">
            <p>Sheet body content goes here.</p>
            <:footer>
              <.button variant="outline" size="sm" phx-click={close_dialog("settings")}>Cancel</.button>
              <.button variant="solid" size="sm" phx-click={close_dialog("settings")}>Save</.button>
            </:footer>
          </.sheet>
          '''}
        >
          <Button.button phx-click={LanternUI.open_dialog("sheet-basic")}>Open sheet</Button.button>
          <Sheet.sheet id="sheet-basic" title="Edit settings">
            <p>
              Sheet body content goes here. Focus is trapped; Escape or the backdrop closes it.
            </p>
            <:footer>
              <Button.button
                variant="outline"
                size="sm"
                phx-click={LanternUI.close_dialog("sheet-basic")}
              >
                Cancel
              </Button.button>
              <Button.button
                variant="solid"
                size="sm"
                phx-click={LanternUI.close_dialog("sheet-basic")}
              >
                Save
              </Button.button>
            </:footer>
          </Sheet.sheet>
        </.demo_section>

        <.demo_section
          title="Placement"
          description="Slides in from any edge — left, right (default), top, or bottom."
          code={~S'''
          <.sheet id="nav" placement="left">…</.sheet>
          <.sheet id="panel" placement="right">…</.sheet>
          <.sheet id="banner" placement="top">…</.sheet>
          <.sheet id="tray" placement="bottom">…</.sheet>
          '''}
        >
          <div class="docs-row">
            <Button.button phx-click={LanternUI.open_dialog("sheet-left")}>left</Button.button>
            <Button.button phx-click={LanternUI.open_dialog("sheet-right")}>right</Button.button>
            <Button.button phx-click={LanternUI.open_dialog("sheet-top")}>top</Button.button>
            <Button.button phx-click={LanternUI.open_dialog("sheet-bottom")}>bottom</Button.button>
          </div>
          <Sheet.sheet id="sheet-left" placement="left" title="left">
            <p>Slides in from the left.</p>
          </Sheet.sheet>
          <Sheet.sheet id="sheet-right" placement="right" title="right">
            <p>Slides in from the right.</p>
          </Sheet.sheet>
          <Sheet.sheet id="sheet-top" placement="top" title="top">
            <p>Slides in from the top.</p>
          </Sheet.sheet>
          <Sheet.sheet id="sheet-bottom" placement="bottom" title="bottom">
            <p>Slides in from the bottom.</p>
          </Sheet.sheet>
        </.demo_section>

        <.demo_section
          title="Prevent closing"
          description="prevent_closing removes the close button and disables Escape/backdrop dismissal — the sheet must be closed by an explicit action."
          code={~S'''
          <.sheet id="confirm" title="Confirm" prevent_closing>
            <p>You must choose an action.</p>
            <:footer>
              <.button variant="solid" size="sm" phx-click={close_dialog("confirm")}>Done</.button>
            </:footer>
          </.sheet>
          '''}
        >
          <Button.button phx-click={LanternUI.open_dialog("sheet-locked")}>
            Open locked sheet
          </Button.button>
          <Sheet.sheet id="sheet-locked" title="Confirm" prevent_closing>
            <p>You must choose an action.</p>
            <:footer>
              <Button.button
                variant="solid"
                size="sm"
                phx-click={LanternUI.close_dialog("sheet-locked")}
              >
                Done
              </Button.button>
            </:footer>
          </Sheet.sheet>
        </.demo_section>
      </article>

      <article :if={@current == "sparkline"} class="docs-body">
        <h1>Sparkline</h1>
        <p>Tiny inline trend line — no axes, no hooks.</p>
        <div class="docs-demo">
          <div class="docs-spark-box">
            <Charts.sparkline id="ch-spark" series={[3, 5, 4, 8, 6, 9]} height={48} />
          </div>
        </div>
        <.code_block id="code-sparkline" code={@snippets["sparkline"]} />
      </article>

      <article :if={@current == "popover"} class="docs-body">
        <h1>Popover</h1>
        <p>Popover content is a surface for form-like content. It keeps focus return, Escape, and outside-click dismissal while allowing interaction inside the panel. Unlike a dropdown menu, it does not close when a field is used.</p>
        <.demo_section title="Filter form" description="The default slot is the trigger and :content is the panel." code={~s"<.popover id=\"filters\" placement=\"bottom-start\"><.button variant=\"outline\">Filters</.button><:content><.input name=\"query\" label=\"Project name\" /><.button size=\"sm\">Apply</.button></:content></.popover>"}>
          <Popover.popover id="filters" placement="bottom-start"><Button.button variant="outline">Filters</Button.button><:content><Form.input name="query" label="Project name" description="Search active projects." /><Button.button size="sm">Apply</Button.button></:content></Popover.popover>
        </.demo_section>
      </article>

      <article :if={@current == "menu"} class="docs-body">
        <h1>Menu and menubar</h1>
        <p>These controls implement the APG menu-button and menubar keyboard models with roles, roving tabindex, arrow keys, Home, and End.</p>
        <.demo_section title="Actions" description="Items can be disabled, separated, linked, or custom-triggered." code={~s"<.menu label=\"File\"><.menu_item>New</.menu_item><.menu_separator /><.menu_item disabled>Unavailable</.menu_item><.menu_item>Export</.menu_item></.menu>"}>
          <Menu.menu id="file-menu" label="File"><Menu.menu_item>New</Menu.menu_item><Menu.menu_separator /><Menu.menu_item disabled>Unavailable</Menu.menu_item><Menu.menu_item>Export <kbd>⌘E</kbd></Menu.menu_item></Menu.menu>
        </.demo_section>
        <.demo_section title="Menubar" description="Top-level entries use horizontal arrow navigation." code={~s"<.menubar label=\"Editor\"><.menubar_menu label=\"File\"><.menu_item>New</.menu_item></.menubar_menu><.menubar_menu label=\"Edit\"><.menu_item>Undo</.menu_item></.menubar_menu></.menubar>"}>
          <Menu.menubar id="editor-menubar" label="Editor"><Menu.menubar_menu label="File"><Menu.menu_item>New</Menu.menu_item></Menu.menubar_menu><Menu.menubar_menu label="Edit"><Menu.menu_item>Undo</Menu.menu_item></Menu.menubar_menu></Menu.menubar>
        </.demo_section>
      </article>

      <article :if={@current == "slider"} class="docs-body">
        <h1>Slider</h1>
        <p>A pointer and keyboard slider writes its hidden input on committed changes. <code>value_text</code> supplies human-readable aria-valuetext; disabled and invalid states remain visible.</p>
        <.demo_section title="Volume" description="Use Arrow keys, Home, End, PageUp, PageDown, or drag the thumb." code={~s"<.slider id=\"volume\" name=\"volume\" value={72} min={0} max={100} step={4} label=\"Volume\" value_text=\"{value}%\" />"}>
          <Slider.slider id="volume" name="volume" value={72} min={0} max={100} step={4} label="Volume" value_text="{value}%" />
          <Slider.slider id="disabled-volume" name="disabled_volume" value={20} label="Disabled" disabled />
          <Slider.slider id="invalid-volume" name="invalid_volume" value={120} label="Invalid" errors={["Choose a value below 100"]} />
        </.demo_section>
      </article>

      <article :if={@current == "resource-list"} class="docs-body">
        <h1>Resource list</h1>
        <p>Use list rows for compact indexes or grid cards for resource overviews. Linked rows make the whole row the hit target.</p>
        <.demo_section title="List" description="Subtitle, leading content, and trailing metadata compose a linked resource row." code={~s"<.resource_list layout={:list}><.resource_list_item navigate=\"/projects/atlas\" title=\"Atlas\" subtitle=\"atlas\"><.badge>Healthy</.badge></.resource_list_item></.resource_list>"}>
          <ResourceList.resource_list layout={:list}><ResourceList.resource_list_item navigate="/projects/atlas" title="Atlas" subtitle="atlas" subtitle_mono><Badge.badge>Healthy</Badge.badge><span>3 apps</span></ResourceList.resource_list_item><ResourceList.resource_list_item title="Beacon" subtitle="beacon"><Badge.badge color="warning">Review</Badge.badge></ResourceList.resource_list_item></ResourceList.resource_list>
        </.demo_section>
        <.demo_section title="Grid" description="The same item contract becomes cards with layout={:grid}." code={~s"<.resource_list layout={:grid}><.resource_list_item title=\"Atlas\" subtitle=\"atlas\">3 apps</.resource_list_item></.resource_list>"}>
          <ResourceList.resource_list layout={:grid}><ResourceList.resource_list_item title="Atlas" subtitle="atlas" subtitle_mono>3 apps</ResourceList.resource_list_item><ResourceList.resource_list_item title="Beacon" subtitle="beacon">1 app</ResourceList.resource_list_item></ResourceList.resource_list>
        </.demo_section>
      </article>

      <article :if={@current == "color-input"} class="docs-body">
        <h1>Color input</h1>
        <p>A native color control with form-compatible name/value, label, help text, errors, disabled state, and density tokens.</p>
        <.demo_section title="Theme color" description="The submitted element is the real input type=color." code={~s"<.color_input id=\"brand-color\" name=\"brand\" value=\"#4f46e5\" label=\"Brand color\" help_text=\"Used in the project header.\" />"}>
          <ColorInput.color_input id="brand-color" name="brand" value="#4f46e5" label="Brand color" help_text="Used in the project header." />
          <ColorInput.color_input id="disabled-color" name="disabled" value="#64748b" label="Disabled" size="sm" disabled />
        </.demo_section>
      </article>

      <article :if={@current == "progress-meter"} class="docs-body">
        <h1>Progress and meter</h1>
        <p>Progress communicates task completion. Meter communicates a scalar measurement in a known range, with optional low, high, and optimum regions.</p>
        <.demo_section title="Task progress" description="Determinate and indeterminate progress use role=progressbar." code={~s"<.progress value={64} label=\"Upload\" /><.progress indeterminate label=\"Preparing\" />"}>
          <Progress.progress value={64} label="Upload" color="success" /><Progress.progress indeterminate label="Preparing" />
        </.demo_section>
        <.demo_section title="Measurements" description="Meter exposes min, max, value, and semantic range regions." code={~s"<.meter value={72} min={0} max={100} low={30} high={80} optimum={50} label=\"CPU load\" />"}>
          <Meter.meter value={72} min={0} max={100} low={30} high={80} optimum={50} label="CPU load" value_text="72 percent" />
        </.demo_section>
      </article>

      <article :if={@current == "scroll-area"} class="docs-body">
        <h1>Scroll area</h1>
        <p>Constrain the wrapper to create overflow. A label gives the region keyboard-scrollable semantics with a focusable role=region.</p>
        <.demo_section title="Axes" description="Vertical, horizontal, and both-axis scrolling all use native browser behavior." code={~s"<.scroll_area label=\"Recent activity\" orientation=\"vertical\" style=\"max-height: 8rem\"><p>...</p></.scroll_area>"}>
          <ScrollArea.scroll_area label="Recent activity" orientation="vertical" class="docs-scroll-demo"><p :for={n <- 1..8}>Activity event {n}</p></ScrollArea.scroll_area>
          <ScrollArea.scroll_area label="Timeline" orientation="horizontal" class="docs-scroll-wide"><span :for={n <- 1..8}>Event {n} - </span></ScrollArea.scroll_area>
          <ScrollArea.scroll_area label="Canvas" orientation="both" class="docs-scroll-both"><span :for={n <- 1..5}>Wide content {n} </span></ScrollArea.scroll_area>
        </.demo_section>
      </article>

      <.api_section current={@current} />

      <style>
        .docs-topbar { display: flex; justify-content: space-between; align-items: center;
          gap: 1rem; padding-bottom: 1rem; border-bottom: 1px solid var(--lantern-border);
          margin-bottom: 2rem; }
        .docs-crumb { font-size: .8125rem; color: var(--lantern-fg-muted); }
        .docs-crumb span { margin: 0 .4rem; opacity: .5; }
        .docs-toggles { display: flex; gap: .5rem; }
        .docs-body { max-width: 760px; }
        .docs-body h1 { font-size: 1.5rem; font-weight: 700; letter-spacing: -.02em; margin: 0 0 .4rem; }
        .docs-body > p { font-size: .875rem; color: var(--lantern-fg-muted); margin: 0 0 1.25rem;
          line-height: 1.6; }
        .docs-body p code, .docs-body kbd { font-family: var(--lantern-font-mono); font-size: .8em;
          background: var(--lantern-surface-sunken); border: 1px solid var(--lantern-border);
          border-radius: 4px; padding: 0 .3em; }
        .docs-section { margin-top: 2.25rem; }
        .docs-section-title { font-size: 1.05rem; font-weight: 650; letter-spacing: -0.01em;
          margin: 0 0 0.25rem; color: var(--lantern-fg); }
        .docs-section-desc { font-size: 0.85rem; color: var(--lantern-fg-muted); margin: 0 0 0.9rem; }
        .docs-chat-controls { margin-bottom: .75rem; }
        .docs-chat-frame { height: 30rem; min-height: 0; }
        .docs-chat-frame .lui-message-scroller { height: 100%; }
        .docs-chat-frame .lui-message-scroller-content { padding: 1rem; }
        .docs-chat-frame .lui-message p { margin: 0 0 .65rem; }
        .docs-chat-frame .lui-message p:last-child { margin-bottom: 0; }
        .docs-chat-typing { color: var(--lantern-fg-muted); font-style: italic; }

        /* Framed example: one card, Preview/Code tabs, code hidden by default. */
        .docs-example { border: 1px solid var(--lantern-border);
          border-radius: var(--lantern-radius-lg); overflow: hidden;
          background: var(--lantern-surface-raised); }
        .docs-example-tabs { display: flex; gap: .15rem; padding: .35rem .45rem;
          border-bottom: 1px solid var(--lantern-border); }
        .docs-example-tab { appearance: none; border: 0; background: none; font: inherit;
          font-size: .8125rem; font-weight: 550; color: var(--lantern-fg-muted);
          padding: .28rem .7rem; border-radius: var(--lantern-radius-sm); cursor: pointer;
          transition: color .12s cubic-bezier(0.16,1,0.3,1),
            background .12s cubic-bezier(0.16,1,0.3,1); }
        .docs-example-tab:hover { color: var(--lantern-fg); }
        .docs-example-tab[aria-selected="true"] { color: var(--lantern-fg);
          background: var(--lantern-surface-sunken); }
        .docs-example-panel[data-panel="preview"] { padding: 2.25rem 1.75rem; min-height: 7rem;
          display: flex; flex-direction: column; justify-content: center; }
        /* The author display above beats the UA [hidden]{display:none}; guard it. */
        .docs-example [data-panel][hidden] { display: none; }
        /* No nested card: the frame owns the border/background. */
        .docs-example-panel .docs-demo { border: 0; background: none; padding: 0;
          display: flex; flex-direction: column; gap: .875rem; }
        .docs-example-panel[data-panel="code"] .lc-editor { border: 0; border-radius: 0; }
        .docs-example-panel[data-panel="code"] .docs-codeblock { margin: 0; }

        /* Standalone preview (chart / app-shell articles that aren't tabbed). */
        .docs-demo { border: 1px solid var(--lantern-border); border-radius: var(--lantern-radius-lg);
          padding: 1.5rem; background: var(--lantern-surface-raised); display: flex;
          flex-direction: column; gap: .875rem; }
        .docs-navdemo { max-width: 15rem; border: 1px solid var(--lantern-border);
          border-radius: var(--lantern-radius-md); padding: .6rem; background: var(--lantern-surface); }
        .docs-appshell-frame { border: 1px solid var(--lantern-border);
          border-radius: var(--lantern-radius-md); overflow: hidden;
          background: var(--lantern-surface); box-shadow: var(--lantern-shadow); }
        .docs-appshell-frame-bar { display: flex; align-items: center; gap: .4rem;
          padding: .55rem .75rem; border-bottom: 1px solid var(--lantern-border);
          background: var(--lantern-surface-sunken); }
        .docs-appshell-frame-bar span { width: .625rem; height: .625rem; border-radius: 999px;
          background: var(--lantern-border-strong); }
        .docs-appshell-iframe { display: block; width: 100%; height: 30rem; border: 0;
          background: var(--lantern-surface); }
        .docs-caption { font-size: .8125rem; color: var(--lantern-fg-muted); margin: 0; }
        .docs-row { display: flex; flex-wrap: wrap; gap: .5rem; align-items: center; }
        .docs-grid2 { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 1rem; }
        .docs-option-rich { display: flex; align-items: baseline; justify-content: space-between;
          gap: 1rem; width: 100%; min-width: 0; }
        .docs-option-rich code { color: var(--lantern-fg-subtle); font-size: .6875rem; }
        .docs-confirm-status { margin: 0; color: var(--lantern-success); font-size: .8125rem; }
        .docs-skeleton-card { display: grid; grid-template-columns: auto minmax(0, 1fr);
          gap: .75rem; align-items: center; width: 100%; }
        .docs-skeleton-avatar { width: 3rem; height: 3rem; border-radius: 999px; grid-row: 1; }
        .docs-skeleton-copy, .docs-skeleton-lines { display: grid; gap: .55rem; min-width: 0; }
        .docs-skeleton-block { height: 5rem; grid-column: 1 / -1; }
        .docs-icons { gap: .875rem; }
        .docs-icon-cell { display: inline-flex; flex-direction: column; align-items: center;
          gap: .3rem; font-size: 1.1rem; color: var(--lantern-fg); }
        .docs-icon-cell code { font-size: .625rem; color: var(--lantern-fg-subtle); }
        .docs-cal-box { max-width: 320px; }
        .docs-spark-box { max-width: 220px; }
         .docs-scroll-demo { max-height: 8rem; }
        .docs-scroll-wide { width: 14rem; white-space: nowrap; overflow-x: auto; }
         .docs-scroll-both { width: 14rem; height: 6rem; white-space: nowrap; overflow: auto; }
        .docs-timeline-avatar {
          display: inline-flex; align-items: center; justify-content: center;
          border-radius: 9999px; background: var(--lantern-accent);
          color: var(--lantern-accent-fg);
          font-size: 0.5rem; font-weight: 650; letter-spacing: 0.02em;
          line-height: 1;
        }
        .docs-code { margin: .75rem 0 0; padding: .875rem 1rem; border-radius: var(--lantern-radius-md);
          background: var(--lantern-surface-sunken); border: 1px solid var(--lantern-border);
          overflow-x: auto; }
        .docs-code code { font-family: var(--lantern-font-mono); font-size: .75rem; line-height: 1.6;
          color: var(--lantern-fg); }

        /* API reference — one dense card per component function. */
        .docs-api { margin-top: 2.5rem; max-width: 760px; }
        .docs-api-fn { border: 1px solid var(--lantern-border);
          border-radius: var(--lantern-radius-md); overflow: hidden; margin-top: 1rem; }
        .docs-api-fn-head { font-family: var(--lantern-font-mono); font-size: .75rem;
          color: var(--lantern-fg-muted); padding: .35rem .7rem;
          background: var(--lantern-surface-sunken);
          border-bottom: 1px solid var(--lantern-border); }
        .docs-api-table { width: 100%; border-collapse: collapse; font-size: .8125rem;
          table-layout: fixed; }
        .docs-api-c1 { width: 26%; } .docs-api-c2 { width: 20%; } .docs-api-c3 { width: 16%; }
        .docs-api-table th { text-align: left; font-weight: 500; font-size: .625rem;
          text-transform: uppercase; letter-spacing: .05em; color: var(--lantern-fg-subtle);
          padding: .3rem .7rem; border-bottom: 1px solid var(--lantern-border); }
        .docs-api-table td { padding: .32rem .7rem; line-height: 1.4; vertical-align: baseline;
          color: var(--lantern-fg-muted); border-bottom: 1px solid var(--lantern-border);
          overflow-wrap: anywhere; }
        .docs-api-table tr:last-child td { border-bottom: 0; }
        .docs-api-table code { font-family: var(--lantern-font-mono); font-size: .75rem;
          color: var(--lantern-fg); }
        .docs-api-type { color: var(--lantern-accent) !important; }
        .docs-api-default { color: var(--lantern-fg-subtle) !important; }
        .docs-api-muted { color: var(--lantern-fg-muted); }
        .docs-api-req { color: var(--lantern-danger); margin-left: 1px; font-weight: 700; }
        .docs-api-div td { background: var(--lantern-surface-sunken); font-size: .6rem;
          text-transform: uppercase; letter-spacing: .06em; font-weight: 600;
          color: var(--lantern-fg-subtle); padding: .22rem .7rem; }
      </style>
    </LanternDemoWeb.DocsShell.shell>
    """
  end

  attr(:title, :string, required: true)
  attr(:description, :string, default: nil)
  attr(:code, :string, required: true)
  slot(:inner_block, required: true)

  defp demo_section(assigns) do
    slug = slugify(assigns.title)
    assigns = assigns |> assign(:code_id, "code-" <> slug) |> assign(:ex_id, "ex-" <> slug)

    ~H"""
    <section class="docs-section">
      <h2 class="docs-section-title">{@title}</h2>
      <p :if={@description} class="docs-section-desc">{@description}</p>
      <div id={@ex_id} class="docs-example" phx-hook="DocsExample">
        <div class="docs-example-tabs" role="tablist" aria-label="Example view">
          <button type="button" class="docs-example-tab" role="tab" data-tab="preview" aria-selected="true">
            Preview
          </button>
          <button type="button" class="docs-example-tab" role="tab" data-tab="code" aria-selected="false">
            Code
          </button>
        </div>
        <div class="docs-example-panel" data-panel="preview">
          <div class="docs-demo">{render_slot(@inner_block)}</div>
        </div>
        <div class="docs-example-panel" data-panel="code" hidden>
          <.code_block id={@code_id} code={@code} />
        </div>
      </div>
    </section>
    """
  end

  attr(:id, :string, required: true)
  attr(:code, :string, required: true)

  defp code_block(assigns) do
    ~H"""
    <LiveCode.Editor.editor
      id={@id}
      language={LiveCode.Languages.HEEx}
      readonly
      value={String.trim(@code)}
      class="docs-codeblock"
    />
    """
  end

  defp catalog_options(query) do
    normalized = query |> String.trim() |> String.downcase()

    if String.length(normalized) < 2 do
      []
    else
      @catalog
      |> Enum.filter(fn item ->
        String.contains?(String.downcase(item.label), normalized) or
          String.contains?(item.value, normalized)
      end)
      |> Enum.group_by(& &1.group)
      |> Enum.sort_by(fn {group, _items} -> group end)
      |> Enum.map(fn {group, items} ->
        {group, Enum.map(items, &{&1.label, &1.value})}
      end)
    end
  end

  defp command_matches(query) do
    normalized = query |> String.trim() |> String.downcase()

    @commands
    |> Enum.filter(fn cmd ->
      normalized == "" or
        String.contains?(String.downcase(cmd.label), normalized) or
        String.contains?(String.downcase(cmd.description || ""), normalized) or
        String.contains?(String.downcase(cmd.group), normalized)
    end)
    |> Enum.chunk_by(& &1.group)
    |> Enum.map(fn [%{group: group} | _] = items -> {group, items} end)
  end

  defp command_demo_code do
    ~S"""
    # LiveView - the palette does no filtering, so you do
    def handle_event("command_search", %{"query" => query}, socket) do
      {:noreply, assign(socket, query: query, groups: command_matches(query))}
    end

    def handle_event("command_select", %{"value" => value}, socket) do
      {:noreply, assign(socket, :selection, value)}
    end

    <.button phx-click={LanternUI.open_dialog("cmd-demo")}>
      Search... <.command_shortcut>Cmd+K</.command_shortcut>
    </.button>

    <.command id="cmd-demo" on_search="command_search" on_select="command_select">
      <%= for {{group, items}, index} <- Enum.with_index(@groups) do %>
        <.command_separator :if={index > 0} />
        <.command_group label={group}>
          <.command_item :for={cmd <- items} value={cmd.value} disabled={cmd.disabled}>
            <:icon><.icon name={cmd.icon} /></:icon>
            {cmd.label}
            <:description>{cmd.description}</:description>
            <:shortcut>{cmd.shortcut}</:shortcut>
          </.command_item>
        </.command_group>
      <% end %>

      <.command_empty :if={@groups == []}>No commands match "{@query}".</.command_empty>

      <:footer>Up/Down to navigate - Enter to select - Esc to close</:footer>
    </.command>
    """
  end

  defp slugify(title) do
    title |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  end

  attr(:current, :string, required: true)

  defp api_section(assigns) do
    assigns = assign(assigns, :entries, Map.get(@api_map, assigns.current, []))

    ~H"""
    <section :if={@entries != []} class="docs-api">
      <h2 class="docs-section-title">API reference</h2>
      <p class="docs-section-desc">Props and slots, introspected from the component.</p>
      <.api_table :for={{mod, fun} <- @entries} module={mod} fun={fun} multi={length(@entries) > 1} />
    </section>
    """
  end

  attr(:module, :atom, required: true)
  attr(:fun, :atom, required: true)
  attr(:multi, :boolean, default: false)

  defp api_table(assigns) do
    info = assigns.module.__components__()[assigns.fun]

    assigns =
      assign(assigns,
        attrs: (info && Enum.reject(info.attrs, &(&1.type == :global))) || [],
        slots: (info && info.slots) || []
      )

    ~H"""
    <div class="docs-api-fn">
      <div :if={@multi} class="docs-api-fn-head"><code>{@fun}/1</code></div>
      <table class="docs-api-table">
        <thead>
          <tr>
            <th class="docs-api-c1">Prop</th>
            <th class="docs-api-c2">Type</th>
            <th class="docs-api-c3">Default</th>
            <th>Description</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={a <- @attrs}>
            <td><code>{a.name}</code><span :if={a.required} class="docs-api-req" title="required">*</span></td>
            <td><code class="docs-api-type">{attr_type(a)}</code></td>
            <td><code class="docs-api-default">{attr_default(a)}</code></td>
            <td>{a.doc}</td>
          </tr>
          <tr :if={@slots != []} class="docs-api-div"><td colspan="4">Slots</td></tr>
          <tr :for={sl <- @slots}>
            <td><code>:{sl.name}</code><span :if={sl.required} class="docs-api-req">*</span></td>
            <td class="docs-api-muted" colspan="3">{sl.doc}</td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  defp attr_type(%{type: type, opts: opts}) do
    cond do
      Keyword.has_key?(opts, :values) -> Enum.map_join(opts[:values], " | ", &to_string/1)
      is_atom(type) -> type |> Atom.to_string() |> String.trim_leading("Elixir.")
      true -> inspect(type)
    end
  end

  defp attr_default(%{required: true}), do: "—"

  defp attr_default(%{opts: opts}) do
    if Keyword.has_key?(opts, :default), do: inspect(opts[:default]), else: "—"
  end
end
