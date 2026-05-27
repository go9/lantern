defmodule Lantern.TestDB do
  @moduledoc """
  Connection details for the integration test suite.

  Set `LANTERN_TEST_DATABASE_URL` to point at a Postgres the tests can create
  and drop tables in; otherwise a local default is used. These tests are tagged
  `:integration` and excluded unless you run `mix test --include integration`.
  """

  @default "postgres://postgres:postgres@localhost:5432/lantern_test"

  @doc "The connection URL the integration tests run against."
  def url, do: System.get_env("LANTERN_TEST_DATABASE_URL", @default)
end
