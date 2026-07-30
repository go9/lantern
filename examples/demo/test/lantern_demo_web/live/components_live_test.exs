defmodule LanternDemoWeb.ComponentsLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint LanternDemoWeb.Endpoint

  @pages [
    {"accordion", ["<h1>Accordion</h1>", ~s(id="faq"), "prevent_all_closed"]},
    {"autocomplete",
     ["<h1>Autocomplete</h1>", ~s(id="ac-catalog-ac"), ~s(data-server-search="search_catalog")]},
    {"alert-dialog",
     ["<h1>Alert dialog</h1>", ~s(id="alert-dialog-demo"), ~s(role="alertdialog")]},
    {"skeleton", ["<h1>Skeleton</h1>", ~s(aria-label="Loading profile"), "lui-skeleton"]},
    {"stat", ["<h1>Stat cards</h1>", "lui-stat-grid", "pending-warehouse-confirmation-2026-07"]}
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
end
