# Integration tests need a reachable Postgres and are excluded by default.
# Run them with: mix test --include integration
# Point them at a database with:
#   LANTERN_TEST_DATABASE_URL=postgres://user:pass@localhost:5432/lantern_test

{:ok, _} = Lantern.TestEndpoint.start_link()

ExUnit.start(exclude: [:integration])
