defmodule LanternDemoWeb.LiveCodeDemoLiveTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest

  @endpoint LanternDemoWeb.Endpoint

  test "route shows every language" do
    html = build_conn() |> get("/livecode") |> html_response(200)

    for language <- ~w(html sql json heex) do
      assert html =~ ~s(id="language-#{language}")
    end

    assert html =~ ~s(id="mode-edit")
    assert html =~ ~s(id="mode-readonly")
    assert html =~ ~s(id="editor-html-edit")
    assert html =~ ~s(data-livecode-view-btn="split")
  end

  test "events keep unsupported language and mode combinations valid" do
    {:ok, socket} =
      LanternDemoWeb.LiveCodeDemoLive.mount(
        %{},
        %{},
        %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
      )

    {:noreply, socket} =
      LanternDemoWeb.LiveCodeDemoLive.handle_event(
        "select-language",
        %{"lang" => "sql"},
        socket
      )

    assert socket.assigns.current == "sql"
    assert socket.assigns.mode == "edit"

    {:noreply, unchanged} =
      LanternDemoWeb.LiveCodeDemoLive.handle_event(
        "select-language",
        %{"lang" => "ruby"},
        socket
      )

    assert unchanged.assigns.current == "sql"

    {:noreply, heex_socket} =
      LanternDemoWeb.LiveCodeDemoLive.handle_event(
        "select-language",
        %{"lang" => "heex"},
        socket
      )

    assert heex_socket.assigns.current == "heex"
    assert heex_socket.assigns.mode == "readonly"

    {:noreply, still_readonly} =
      LanternDemoWeb.LiveCodeDemoLive.handle_event(
        "select-mode",
        %{"mode" => "edit"},
        heex_socket
      )

    assert still_readonly.assigns.mode == "readonly"

    html = render(still_readonly.assigns)
    assert html =~ ~s(id="editor-heex-readonly")
    assert html =~ ~s(id="mode-edit")
    assert html =~ "disabled"
    refute html =~ "<textarea"
    refute html =~ "data-livecode-view-btn"
  end

  defp render(assigns) do
    assigns
    |> LanternDemoWeb.LiveCodeDemoLive.render()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end
end
