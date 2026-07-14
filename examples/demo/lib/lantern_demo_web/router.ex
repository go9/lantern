defmodule LanternDemoWeb.Router do
  use Phoenix.Router

  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {LanternDemoWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/", LanternDemoWeb do
    pipe_through(:browser)

    live("/", DemoLive, :index)
    live("/components", ComponentsLive, :index)
    live("/components/data-table", DataTableDemo)
    live("/components/theming", ThemingLive)
    live("/components/:slug", ComponentsLive, :show)
  end
end
