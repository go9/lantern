import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "SECRET_KEY_BASE environment variable is required"

  host = System.get_env("PHX_HOST") || raise("PHX_HOST environment variable is required")
  port = String.to_integer(System.get_env("PORT", "4000"))

  config :lantern_demo, LanternDemoWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  # Turnstile — must be real keys in prod (not the always-pass test keys)
  config :lantern_demo,
    turnstile_site_key:
      System.get_env("TURNSTILE_SITE_KEY") || raise("TURNSTILE_SITE_KEY required"),
    turnstile_secret_key:
      System.get_env("TURNSTILE_SECRET_KEY") || raise("TURNSTILE_SECRET_KEY required")

  # LANTERN_DEMO_DATABASE_URL is read directly in LanternDemo.DemoDB at runtime.
  # Raise early here so a missing DB URL surfaces at startup, not on first request.
  System.get_env("LANTERN_DEMO_DATABASE_URL") ||
    raise "LANTERN_DEMO_DATABASE_URL environment variable is required"

  # Flicker branch sandbox — required in prod so sandboxes use real Flicker branches.
  config :lantern_demo,
    flicker_api_key:
      System.get_env("FLICKER_API_KEY") || raise("FLICKER_API_KEY required"),
    flicker_database_id:
      System.get_env("FLICKER_DATABASE_ID") || raise("FLICKER_DATABASE_ID required")
end
