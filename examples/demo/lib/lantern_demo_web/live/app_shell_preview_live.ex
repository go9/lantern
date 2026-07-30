defmodule LanternDemoWeb.AppShellPreviewLive do
  @moduledoc """
  A standalone, self-contained `app_shell` rendered for the `/components/app-shell`
  preview iframe. `app_shell` is `position: fixed` (top bar + sidebar), so it can't
  be nested inside the docs' own shell — an iframe scopes the fixed positioning to
  its own viewport, giving a faithful, fully interactive preview (the collapse
  control at the sidebar foot works here too).
  """
  use Phoenix.LiveView

  alias LanternUI.Components.Badge
  alias LanternUI.Components.Breadcrumb
  alias LanternUI.Components.Button
  alias LanternUI.Components.Icon
  alias LanternUI.Components.Layout
  alias LanternUI.Components.Table
  alias LanternUI.Components.Theme

  @rows [
    %{name: "Nimbus", region: "us-east", status: "Active", objects: "1.2M"},
    %{name: "Vault", region: "eu-west", status: "Active", objects: "840K"},
    %{name: "Archive", region: "us-west", status: "Paused", objects: "3.1M"},
    %{name: "Staging", region: "eu-west", status: "Active", objects: "92K"}
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, rows: @rows), layout: false}
  end

  def render(assigns) do
    ~H"""
    <Theme.theme />
    <style>
      .lui-appshell-preview-main { display: flex; flex-direction: column; gap: 1.25rem; padding: .25rem; }
      .lui-appshell-preview-head h1 { font-size: 1.35rem; font-weight: 650; color: var(--lantern-fg); margin: 0; }
      .lui-appshell-preview-head p { font-size: .875rem; color: var(--lantern-fg-muted); margin: .25rem 0 0; }
      .lui-appshell-preview-stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: .75rem; }
      .lui-appshell-preview-stat { display: flex; flex-direction: column; gap: .25rem;
        padding: .85rem 1rem; border: 1px solid var(--lantern-border);
        border-radius: var(--lantern-radius-md); background: var(--lantern-surface-raised); }
      .lui-appshell-preview-stat-label { font-size: .75rem; color: var(--lantern-fg-muted); }
      .lui-appshell-preview-stat-value { font-size: 1.5rem; font-weight: 650; color: var(--lantern-fg); }
      .lui-appshell-preview-strong { font-weight: 550; color: var(--lantern-fg); }
    </style>
    <Layout.app_shell id="app-shell-preview">
      <:brand>
        <Icon.icon name="cloud" /> <span class="lui-brand-name">Acme</span>
      </:brand>
      <:header>
        <Breadcrumb.breadcrumb aria_label="Location">
          <:item>Workspace</:item>
          <:item current>Buckets</:item>
        </Breadcrumb.breadcrumb>
      </:header>
      <:actions>
        <Button.button variant="outline" size="sm">
          <Icon.icon name="plus" /> New bucket
        </Button.button>
      </:actions>

      <:sidebar>
        <Layout.nav_group label="Workspace">
          <Layout.nav_item label="Dashboard" icon="chart-bar" href="#" />
          <Layout.nav_item label="Buckets" icon="cloud" href="#" active />
          <Layout.nav_item label="Data" icon="circle-stack" href="#" />
        </Layout.nav_group>
        <Layout.nav_group label="Account">
          <Layout.nav_item label="Team" icon="squares-2x2" href="#" />
          <Layout.nav_item label="Settings" icon="adjustments-horizontal" href="#" />
        </Layout.nav_group>
      </:sidebar>

      <div class="lui-appshell-preview-main">
        <header class="lui-appshell-preview-head">
          <h1>Buckets</h1>
          <p>Object storage across your regions.</p>
        </header>

        <section class="lui-appshell-preview-stats">
          <div class="lui-appshell-preview-stat">
            <span class="lui-appshell-preview-stat-label">Buckets</span>
            <span class="lui-appshell-preview-stat-value">4</span>
          </div>
          <div class="lui-appshell-preview-stat">
            <span class="lui-appshell-preview-stat-label">Objects</span>
            <span class="lui-appshell-preview-stat-value">5.2M</span>
          </div>
          <div class="lui-appshell-preview-stat">
            <span class="lui-appshell-preview-stat-label">Regions</span>
            <span class="lui-appshell-preview-stat-value">3</span>
          </div>
        </section>

        <Table.table>
          <Table.table_head>
            <:col>Name</:col>
            <:col>Region</:col>
            <:col>Status</:col>
            <:col>Objects</:col>
          </Table.table_head>
          <Table.table_body>
            <Table.table_row :for={row <- @rows}>
              <:cell><span class="lui-appshell-preview-strong">{row.name}</span></:cell>
              <:cell>{row.region}</:cell>
              <:cell>
                <Badge.badge color={if row.status == "Active", do: "success", else: "warning"}>
                  {row.status}
                </Badge.badge>
              </:cell>
              <:cell>{row.objects}</:cell>
            </Table.table_row>
          </Table.table_body>
        </Table.table>
      </div>
    </Layout.app_shell>
    """
  end
end
