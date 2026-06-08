import Config

port = String.to_integer(System.get_env("PORT", "4001"))

config :lantern_demo, LanternDemoWeb.Endpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: port],
  server: true,
  adapter: Bandit.PhoenixAdapter,
  secret_key_base: String.duplicate("lantern_demo_secret", 4),
  live_view: [signing_salt: "lantern_demo_salt"],
  render_errors: [formats: [html: LanternDemoWeb.ErrorHTML], layout: false]

config :phoenix, :json_library, Jason
