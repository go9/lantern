defmodule LanternDemoWeb.ComponentsLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint LanternDemoWeb.Endpoint

  @pages [
    {"accordion", ["<h1>Accordion</h1>", ~s(id="faq"), "prevent_all_closed"]},
    {"autocomplete",
     ["<h1>Autocomplete</h1>", ~s(id="ac-catalog-ac"), ~s(data-server-search="search_catalog")]},
    {"alert-dialog",
     ["<h1>Alert dialog</h1>", ~s(id="alert-dialog-demo"), ~s(role="alertdialog")]},
    {"skeleton", ["<h1>Skeleton</h1>", ~s(aria-label="Loading profile"), "lui-skeleton"]},
    {"stat", ["<h1>Stat cards</h1>", "lui-stat-grid", "pending-warehouse-confirmation-2026-07"]},
    {"command",
     [
       "<h1>Command palette</h1>",
       ~s(id="cmd-demo"),
       ~s(phx-hook="LanternCommand"),
       ~s(data-on-search="command_search"),
       ~s(data-value="goto-theming"),
       ~s(data-part="separator")
     ]},
    {"dropdown",
     ["<h1>Dropdown menu</h1>", ~s(lui-dropdown-custom), "Signed in as ada@example.com"]},
    {"date-picker",
     ["<h1>Date &amp; time pickers</h1>", ~s(class="lui-date-range"), "Release window"]},
    {"chat-kit",
     [
       "<h1>Chat kit</h1>",
       ~s(id="chat-kit-demo"),
       ~s(phx-hook="LanternMessageScroller"),
       ~s(role="region"),
       ~s(aria-label="Chat kit conversation"),
       ~s(role="log"),
       ~s(data-align="start"),
       ~s(data-align="end"),
       ~s(data-tone="surface"),
       ~s(data-tone="primary"),
       ~s(data-part="avatar"),
       "AL",
       "Append reply",
       "Toggle streaming",
       "Reset"
     ]},
    {"popover", ["<h1>Popover</h1>", ~s(id="filters"), ~s(role="dialog"), "lui-popover"]},
    {"menu",
     ["<h1>Menu and menubar</h1>", ~s(role="menu"), ~s(role="menubar"), ~s(role="separator")]},
    {"slider",
     ["<h1>Slider</h1>", ~s(role="slider"), ~s(data-part="input"), ~s(aria-valuetext="72%")]},
    {"resource-list",
     ["<h1>Resource list</h1>", ~s(data-layout="list"), ~s(data-layout="grid"), "Atlas"]},
    {"color-input",
     [
       "<h1>Color input</h1>",
       ~s(type="color"),
       ~s(id="brand-color"),
       "Used in the project header"
     ]},
    {"progress-meter",
     [
       "<h1>Progress and meter</h1>",
       ~s(role="progressbar"),
       ~s(role="meter"),
       ~s(data-state="indeterminate")
     ]},
    {"scroll-area",
     [
       "<h1>Scroll area</h1>",
       ~s(data-orientation="vertical"),
       ~s(data-orientation="horizontal"),
       ~s(data-orientation="both"),
       ~s(tabindex="0")
     ]}
  ]

  test "new component pages render permanent examples and shared appearance controls" do
    for {slug, fragments} <- @pages do
      html = build_conn() |> get("/components/#{slug}") |> html_response(200)

      for fragment <- fragments,
          do: assert(html =~ fragment, "missing #{inspect(fragment)} on #{slug}")

      assert html =~ ~s(data-part="theme-toggle")
      assert html =~ ~s(data-part="density-toggle")
      assert html =~ "API reference"
    end
  end

  test "component navigation includes every new page" do
    html = build_conn() |> get("/components/accordion") |> html_response(200)

    assert html =~ ~s(href="/components/accordion")
    assert html =~ ~s(href="/components/alert-dialog")
    assert html =~ ~s(href="/components/skeleton")
    assert html =~ ~s(href="/components/stat")
    assert html =~ ~s(href="/components/command")
    assert html =~ ~s(href="/components/chat-kit")
    assert html =~ ~s(href="/components/popover")
    assert html =~ ~s(href="/components/menu")
    assert html =~ ~s(href="/components/slider")
    assert html =~ ~s(href="/components/resource-list")
    assert html =~ ~s(href="/components/color-input")
    assert html =~ ~s(href="/components/progress-meter")
    assert html =~ ~s(href="/components/scroll-area")
  end

  test "chat kit controls change the transcript and busy state" do
    {:ok, view, html} = live(build_conn(), "/components/chat-kit")

    assert html =~ ~s(aria-busy="false")
    assert anchor_count(html) == 1
    assert html =~ ~s(data-message-id="chat-7")

    html = view |> element(~s(button[phx-click="chat_append_reply"])) |> render_click()
    assert html =~ ~s(data-message-id="chat-reply-8")
    assert anchor_count(html) == 1

    html = view |> element(~s(button[phx-click="chat_toggle_streaming"])) |> render_click()
    assert html =~ ~s(aria-busy="true")
    assert html =~ ~s(id="chat-streaming")
    assert html =~ "Assistant is typing..."
    assert query_nodes(html, ~s([data-message-id="chat-reply-8"][data-scroll-anchor])) == []
    assert anchor_count(html) == 1

    html = view |> element(~s(button[phx-click="chat_toggle_streaming"])) |> render_click()
    assert html =~ ~s(aria-busy="false")
    assert query_nodes(html, ~s([data-message-id="chat-reply-8"][data-scroll-anchor])) != []
    assert anchor_count(html) == 1

    html = view |> element(~s(button[phx-click="chat_reset"])) |> render_click()
    refute html =~ ~s(data-message-id="chat-reply-8")
    assert query_nodes(html, ~s([data-message-id="chat-7"][data-scroll-anchor])) != []
    assert html =~ ~s(aria-busy="false")
    assert anchor_count(html) == 1

    html = view |> element(~s(button[phx-click="chat_append_reply"])) |> render_click()
    assert html =~ ~s(data-message-id="chat-reply-9")
    refute html =~ ~s(data-message-id="chat-reply-8")
    assert anchor_count(html) == 1
  end

  # The palette filters nothing itself, so these handlers ARE the search.
  test "command palette search filters and groups the demo command list" do
    {:ok, socket} = mount_components()

    assert Enum.map(socket.assigns.command_groups, &elem(&1, 0)) ==
             ["Navigate", "Actions", "Danger zone"]

    {:noreply, navigate} =
      LanternDemoWeb.ComponentsLive.handle_event("command_search", %{"query" => "go to"}, socket)

    assert [{"Navigate", items}] = navigate.assigns.command_groups
    assert Enum.map(items, & &1.value) == ["goto-buttons", "goto-data-table", "goto-theming"]
    assert navigate.assigns.command_query == "go to"

    {:noreply, empty} =
      LanternDemoWeb.ComponentsLive.handle_event("command_search", %{"query" => "zzz"}, socket)

    assert empty.assigns.command_groups == []
  end

  test "command palette selection is reported back with its label" do
    {:ok, socket} = mount_components()

    {:noreply, chosen} =
      LanternDemoWeb.ComponentsLive.handle_event(
        "command_select",
        %{"value" => "new-ticket"},
        socket
      )

    assert chosen.assigns.command_selection == {"new-ticket", "Open a new ticket"}
  end

  test "command palette places separators between groups" do
    html = build_conn() |> get("/components/command") |> html_response(200)

    assert html =~ ~r/lui-command-group.*lui-command-separator.*lui-command-group/s
  end

  test "server-backed autocomplete filters and groups fixed catalog data" do
    {:ok, socket} = mount_components()

    {:noreply, short} =
      LanternDemoWeb.ComponentsLive.handle_event("search_catalog", %{"query" => "z"}, socket)

    assert short.assigns.catalog_options == []

    {:noreply, results} =
      LanternDemoWeb.ComponentsLive.handle_event("search_catalog", %{"query" => "zel"}, socket)

    assert results.assigns.catalog_options == [
             {"Nintendo 64",
              [
                {"The Legend of Zelda: Ocarina of Time", "zelda-ocarina"},
                {"The Legend of Zelda: Majora's Mask", "zelda-majora"}
              ]},
             {"Nintendo Switch", [{"The Legend of Zelda: Breath of the Wild", "zelda-botw"}]}
           ]

    {:noreply, none} =
      LanternDemoWeb.ComponentsLive.handle_event(
        "search_catalog",
        %{"query" => "missing"},
        socket
      )

    assert none.assigns.catalog_options == []
  end

  test "alert dialog confirmation is harmless and exposes status feedback" do
    {:ok, socket} = mount_components()

    {:noreply, confirmed} =
      LanternDemoWeb.ComponentsLive.handle_event("confirm_demo_revoke", %{}, socket)

    assert confirmed.assigns.alert_dialog_status ==
             "Demo key revoked — no real credential was changed."
  end

  test "unknown component slugs retain the existing button fallback" do
    html = build_conn() |> get("/components/not-a-component") |> html_response(200)

    assert html =~ "<h1>Button</h1>"
  end

  test "demo chrome persists the long sidebar position across navigation" do
    source = File.read!("priv/static/app.js")

    assert source =~ ~s(const SIDEBAR_SCROLL_STORAGE_KEY = "lui-demo-sidebar-scroll")
    assert source =~ "sessionStorage.setItem("
    assert source =~ "nav.scrollTop = Number(saved.top)"
    assert source =~ "nav.scrollLeft = Number(saved.left)"
    assert source =~ "this.saveSidebarScroll()"
  end

  defp mount_components do
    LanternDemoWeb.ComponentsLive.mount(
      %{},
      %{},
      %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    )
  end

  defp anchor_count(html) do
    query_nodes(html, "[data-scroll-anchor]") |> length()
  end

  defp query_nodes(html, selector) do
    html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> LazyHTML.to_tree()
  end
end
