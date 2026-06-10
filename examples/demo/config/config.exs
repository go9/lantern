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

# Cloudflare Turnstile — default to always-pass test keys for local dev.
# Override TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY in production.
config :lantern_demo,
  turnstile_site_key: System.get_env("TURNSTILE_SITE_KEY", "1x00000000000000000000AA"),
  turnstile_secret_key: System.get_env("TURNSTILE_SECRET_KEY", "1x0000000000000000000000000000000AA"),
  # Flicker branch sandbox — omit in local dev to fall back to raw Postgres.
  flicker_api_key: System.get_env("FLICKER_API_KEY"),
  flicker_database_id: System.get_env("FLICKER_DATABASE_ID")
