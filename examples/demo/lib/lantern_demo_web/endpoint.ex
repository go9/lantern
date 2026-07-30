defmodule LanternDemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :lantern_demo

  @session_options [
    store: :cookie,
    key: "_lantern_demo_key",
    signing_salt: "lantern_demo_session",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]
  )

  plug(Plug.Static,
    at: "/",
    from: :lantern_demo,
    gzip: false,
    only: ~w(app.js favicon.svg)
  )

  plug(Plug.Static,
    at: "/",
    from: {:lantern, "priv/static"},
    gzip: false,
    only: ~w(lantern)
  )

  plug(Plug.Static,
    at: "/",
    from: {:livecode, "priv/static"},
    gzip: false,
    only: ~w(livecode)
  )

  plug(Plug.Static,
    at: "/",
    from: {:lantern_ui, "priv/static"},
    gzip: false,
    only: ~w(lantern_ui.css lantern_ui_theme.css lantern_ui_hooks.js)
  )

  plug(Plug.Static,
    at: "/",
    from: {:lantern_s3, "priv/static"},
    gzip: false,
    only: ~w(lantern_s3.css lantern_s3_uploader.js)
  )

  plug(Plug.Static,
    at: "/js",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false,
    only: ~w(phoenix_live_view.esm.js)
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])
  plug(Plug.Parsers, parsers: [:urlencoded, :multipart], pass: ["*/*"])
  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(LanternDemoWeb.Router)
end
