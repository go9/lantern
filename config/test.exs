import Config

config :lantern, Lantern.TestEndpoint,
  http: [port: 4002],
  server: false,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "lantern_test_salt"]

config :phoenix, :json_library, Jason
