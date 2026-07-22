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
  turnstile_secret_key:
    System.get_env("TURNSTILE_SECRET_KEY", "1x0000000000000000000000000000000AA"),
  # Flicker branch sandbox — omit in local dev to fall back to raw Postgres.
  flicker_api_key: System.get_env("FLICKER_API_KEY"),
  flicker_database_id: System.get_env("FLICKER_DATABASE_ID")

# Both demos share the slot+queue admission engine: 5 concurrent sessions per
# pool with a FIFO wait queue.
config :lantern_demo, LanternDemo.SandboxManager,
  pools: %{
    db: [max: 5, provider: LanternDemo.Sandbox.DbProvider],
    s3: [max: 5, provider: LanternDemo.S3Sandbox.PrefixProvider]
  }

# S3 upload sandbox (optional). Backed by a single flicker-managed bucket reached
# through flicker's S3 gateway (storage.flickercloud.com) with a bucket-scoped
# Flicker BucketCredential — no provider root key in this public app. Sessions
# isolate by prefix. Unset ⇒ the upload demo shows a "coming soon" state; the
# rest of the page is fine.
config :ex_aws, json_codec: Jason

config :ex_aws,
  access_key_id: System.get_env("S3_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("S3_SECRET_ACCESS_KEY")

config :ex_aws, :s3,
  scheme: "https://",
  host: System.get_env("S3_ENDPOINT", "storage.flickercloud.com"),
  region: System.get_env("S3_REGION", "auto")

config :lantern_demo, :s3_sandbox_bucket, System.get_env("S3_SANDBOX_BUCKET")
