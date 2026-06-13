defmodule LanternDemo.DemoDB do
  @moduledoc """
  Demo database management — seed data for the read-only view, and sandbox
  creation/teardown for writable sessions.

  **Sandbox strategy (prod):** Flicker branch API. Each sandbox is a fork of the
  demo database's default branch — it inherits all seed data instantly, is
  writable, and self-destructs via `ttl: "5m"` even if the app crashes. Set
  `FLICKER_API_KEY` and `FLICKER_DATABASE_ID` to enable.

  **Sandbox strategy (local dev):** raw `CREATE DATABASE` + seed + `DROP DATABASE`
  when Flicker credentials are absent.
  """

  require Logger

  @default_url "postgres://postgres:postgres@localhost:5432/lantern_demo"
  @flicker_api "https://flickercloud.com"
  @poll_interval_ms 500
  @poll_max_attempts 180

  # OTP 26+ added stricter PKIX path validation that rejects CA certs whose
  # KeyUsage (keyCertSign/cRLSign) and ExtendedKeyUsage (serverAuth/clientAuth)
  # are considered mismatched per RFC 5280. Some CAs (including certain
  # Let's Encrypt intermediates) produce chains that trigger this. We tolerate
  # the specific key_usage_mismatch error while keeping all other checks intact.
  # Defined as a function (not a module attribute) because anonymous funs can't
  # be stored as attributes.
  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      verify_fun:
        {fn
           _cert, {:bad_cert, {:key_usage_mismatch, _}}, state -> {:valid, state}
           _cert, {:bad_cert, reason}, _state -> {:fail, {:bad_cert, reason}}
           _cert, {:extension, _}, state -> {:unknown, state}
           _cert, :valid, state -> {:valid, state}
           _cert, :valid_peer, state -> {:valid, state}
         end, []}
    ]
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc "Returns the demo database URL."
  @spec url() :: String.t()
  def url, do: System.get_env("LANTERN_DEMO_DATABASE_URL", @default_url)

  @doc """
  Creates a writable sandbox. Returns `{:ok, connection_url, sandbox_id}`.

  In prod (Flicker creds present): forks a Flicker branch with a 5-minute TTL.
  In local dev: creates a raw Postgres database and seeds it.

  The returned `sandbox_id` is opaque — pass it back to `drop_sandbox/1`.
  """
  @spec create_sandbox() :: {:ok, String.t(), term()} | {:error, String.t()}
  def create_sandbox do
    api_key = Application.get_env(:lantern_demo, :flicker_api_key)
    db_id = Application.get_env(:lantern_demo, :flicker_database_id)

    if api_key && db_id do
      create_flicker_branch(api_key, db_id)
    else
      create_local_sandbox()
    end
  end

  @doc "Tears down a sandbox created by `create_sandbox/0`."
  @spec drop_sandbox(term()) :: :ok
  def drop_sandbox(sandbox_id) when is_integer(sandbox_id) do
    api_key = Application.get_env(:lantern_demo, :flicker_api_key)
    db_id = Application.get_env(:lantern_demo, :flicker_database_id)

    if api_key && db_id do
      case Req.delete("#{@flicker_api}/api/v1/databases/#{db_id}/branches/#{sandbox_id}",
             auth: {:bearer, api_key},
             connect_options: [transport_opts: ssl_opts()]
           ) do
        {:ok, %{status: s}} when s in [200, 204] ->
          Logger.info("[DemoDB] dropped Flicker branch #{sandbox_id}")

        {:ok, %{status: 404}} ->
          :ok

        other ->
          Logger.warning("[DemoDB] unexpected response dropping branch #{sandbox_id}: #{inspect(other)}")
      end
    end

    :ok
  end

  def drop_sandbox(db_name) when is_binary(db_name) do
    with {:ok, source} <- Lantern.Source.from(url()) do
      maintenance_source = %{source | database: "postgres"}

      case Postgrex.start_link(Lantern.Source.to_postgrex_opts(maintenance_source)) do
        {:ok, conn} ->
          try do
            Postgrex.query!(conn, "DROP DATABASE IF EXISTS #{Lantern.SQL.quote_ident(db_name)}", [])
          rescue
            _ -> :ok
          after
            GenServer.stop(conn)
          end

        _ ->
          :ok
      end
    end

    :ok
  end

  @doc "Creates the demo schema and deterministic sample data (idempotent)."
  @spec ensure() :: :ok | {:error, String.t()}
  def ensure do
    with {:ok, source} <- Lantern.Source.from(url()),
         :ok <- ensure_database_exists(source),
         {:ok, conn} <- Postgrex.start_link(Lantern.Source.to_postgrex_opts(source)) do
      try do
        seed!(conn)
        :ok
      rescue
        exception -> {:error, Exception.message(exception)}
      after
        GenServer.stop(conn)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Creates the demo schema and raises on failure."
  @spec ensure!() :: :ok
  def ensure! do
    case ensure() do
      :ok -> :ok
      {:error, reason} -> raise reason
    end
  end

  # ---------------------------------------------------------------------------
  # Flicker branch sandbox
  # ---------------------------------------------------------------------------

  defp create_flicker_branch(api_key, db_id) do
    suffix =
      :crypto.strong_rand_bytes(4)
      |> Base.url_encode64(padding: false)
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")

    name = "sandbox-#{suffix}"

    case Req.post("#{@flicker_api}/api/v1/databases/#{db_id}/branches",
           auth: {:bearer, api_key},
           json: %{name: name, ttl: "5m"},
           connect_options: [transport_opts: ssl_opts()]
         ) do
      {:ok, %{status: 202, body: %{"branch" => %{"id" => branch_id}}}} ->
        poll_branch_ready(api_key, db_id, branch_id)

      {:ok, %{status: status, body: body}} ->
        {:error, "Flicker returned HTTP #{status}: #{inspect(body)}"}

      {:error, exception} ->
        {:error, "Flicker API error: #{Exception.message(exception)}"}
    end
  end

  # A Flicker branch is a CNPG VolumeSnapshot clone of its parent (the demo's
  # `main` branch), so it inherits `main`'s Postgres roles AND their password
  # hashes verbatim. The branch row's own `password` column is left empty,
  # though, so the `connection_string` Flicker hands back authenticates as
  # `postgres` with an *empty* password — which Postgres rejects (28P01).
  #
  # We already hold credentials that authenticate against `main` (the demo's
  # LANTERN_DEMO_DATABASE_URL); since the fork shares those roles, graft that
  # URL's userinfo onto the branch connection string while keeping the branch's
  # own host, database, and `options=endpoint=...` SNI parameter.
  defp graft_credentials(branch_cs) do
    branch_uri = URI.parse(branch_cs)

    case URI.parse(url()) do
      %URI{userinfo: userinfo} when is_binary(userinfo) and userinfo != "" ->
        URI.to_string(%{branch_uri | userinfo: userinfo})

      _ ->
        branch_cs
    end
  end

  defp poll_branch_ready(api_key, db_id, branch_id, attempt \\ 0)

  defp poll_branch_ready(_api_key, _db_id, _branch_id, @poll_max_attempts) do
    {:error, "Timed out waiting for sandbox to become ready"}
  end

  defp poll_branch_ready(api_key, db_id, branch_id, attempt) do
    case Req.get("#{@flicker_api}/api/v1/databases/#{db_id}/branches/#{branch_id}",
           auth: {:bearer, api_key},
           connect_options: [transport_opts: ssl_opts()]
         ) do
      {:ok, %{status: 200, body: %{"branch" => %{"status" => "ready", "connection_string" => cs}}}}
      when is_binary(cs) ->
        {:ok, graft_credentials(cs), branch_id}

      {:ok, %{status: 200}} ->
        Process.sleep(@poll_interval_ms)
        poll_branch_ready(api_key, db_id, branch_id, attempt + 1)

      {:ok, %{status: status, body: body}} ->
        {:error, "Unexpected status #{status} polling branch: #{inspect(body)}"}

      {:error, _exception} ->
        Process.sleep(@poll_interval_ms)
        poll_branch_ready(api_key, db_id, branch_id, attempt + 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Local dev sandbox (raw Postgres)
  # ---------------------------------------------------------------------------

  defp create_local_sandbox do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    with {:ok, source} <- Lantern.Source.from(url()) do
      db_name = "lantern_demo_sandbox_#{String.downcase(id) |> String.replace(~r/[^a-z0-9]/, "")}"
      sandbox_source = %{source | database: db_name}
      sandbox_url = source_to_url(sandbox_source)

      with :ok <- ensure_database_exists(sandbox_source),
           {:ok, conn} <- Postgrex.start_link(Lantern.Source.to_postgrex_opts(sandbox_source)) do
        try do
          seed!(conn)
          {:ok, sandbox_url, db_name}
        rescue
          exception -> {:error, Exception.message(exception)}
        after
          GenServer.stop(conn)
        end
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Seed helpers
  # ---------------------------------------------------------------------------

  defp ensure_database_exists(source) do
    maintenance_source = %{source | database: "postgres"}

    with {:ok, conn} <- Postgrex.start_link(Lantern.Source.to_postgrex_opts(maintenance_source)) do
      try do
        case Postgrex.query!(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [
               source.database
             ]) do
          %{rows: [[1]]} ->
            :ok

          %{rows: []} ->
            Postgrex.query!(
              conn,
              "CREATE DATABASE #{Lantern.SQL.quote_ident(source.database)}",
              []
            )

            :ok
        end
      rescue
        error in Postgrex.Error -> {:error, Exception.message(error)}
        error in DBConnection.ConnectionError -> {:error, Exception.message(error)}
      after
        GenServer.stop(conn)
      end
    else
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp seed!(conn) do
    Enum.each(schema_statements(), &query!(conn, &1))

    query!(
      conn,
      "TRUNCATE order_items, orders, products, customers, audit_events, import_queue, ops.incidents, ops.release_checks RESTART IDENTITY CASCADE"
    )

    Enum.each(seed_statements(), &query!(conn, &1))
  end

  defp schema_statements do
    [
      """
      CREATE SCHEMA IF NOT EXISTS ops
      """,
      """
      CREATE TABLE IF NOT EXISTS customers (
        id serial PRIMARY KEY,
        email text NOT NULL UNIQUE,
        name text NOT NULL,
        status text NOT NULL DEFAULT 'active',
        signup_date date NOT NULL,
        vip boolean NOT NULL DEFAULT false,
        profile jsonb NOT NULL DEFAULT '{}'::jsonb
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS products (
        id serial PRIMARY KEY,
        sku text NOT NULL UNIQUE,
        name text NOT NULL,
        price numeric(10,2) NOT NULL,
        stock integer NOT NULL DEFAULT 0,
        active boolean NOT NULL DEFAULT true,
        tags text[] NOT NULL DEFAULT '{}'
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS orders (
        id serial PRIMARY KEY,
        customer_id integer NOT NULL REFERENCES customers(id),
        status text NOT NULL DEFAULT 'pending',
        total_cents integer NOT NULL DEFAULT 0,
        placed_at timestamp without time zone NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS order_items (
        id serial PRIMARY KEY,
        order_id integer NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        product_id integer NOT NULL REFERENCES products(id),
        quantity integer NOT NULL,
        unit_price_cents integer NOT NULL
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS audit_events (
        id bigserial PRIMARY KEY,
        actor text NOT NULL,
        action text NOT NULL,
        metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
        created_at timestamp with time zone NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS import_queue (
        source text NOT NULL,
        payload jsonb NOT NULL,
        received_at timestamp with time zone NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS ops.incidents (
        id serial PRIMARY KEY,
        title text NOT NULL,
        severity text NOT NULL,
        customer_id integer REFERENCES public.customers(id),
        opened_at timestamp with time zone NOT NULL DEFAULT now(),
        resolved boolean NOT NULL DEFAULT false
      )
      """,
      """
      CREATE TABLE IF NOT EXISTS ops.release_checks (
        id serial PRIMARY KEY,
        release_name text NOT NULL,
        passed boolean NOT NULL DEFAULT false,
        notes text,
        checked_at timestamp with time zone NOT NULL DEFAULT now()
      )
      """
    ]
  end

  defp seed_statements do
    [
      """
      INSERT INTO customers (email, name, status, signup_date, vip, profile) VALUES
        ('ada@example.test', 'Ada Lovelace', 'active', '2024-01-12', true, '{"plan":"enterprise","region":"EU"}'),
        ('grace@example.test', 'Grace Hopper', 'active', '2024-02-08', true, '{"plan":"pro","region":"US"}'),
        ('katherine@example.test', 'Katherine Johnson', 'paused', '2024-03-15', false, '{"plan":"starter","region":"US"}'),
        ('radia@example.test', 'Radia Perlman', 'active', '2024-04-19', false, '{"plan":"pro","region":"CA"}')
      """,
      """
      INSERT INTO products (sku, name, price, stock, active, tags) VALUES
        ('LTN-001', 'Brass Lantern', 48.00, 18, true, ARRAY['featured', 'brass']),
        ('LTN-002', 'Storm Lantern', 64.50, 7, true, ARRAY['outdoor']),
        ('WCK-001', 'Replacement Wick Pack', 8.25, 120, true, ARRAY['accessory']),
        ('OIL-001', 'Smokeless Lamp Oil', 14.99, 42, false, ARRAY['fuel', 'hazmat'])
      """,
      """
      INSERT INTO orders (customer_id, status, total_cents, placed_at) VALUES
        (1, 'paid', 5625, '2025-05-01 10:15:00'),
        (2, 'shipped', 6450, '2025-05-03 16:42:00'),
        (3, 'pending', 4800, '2025-05-08 09:05:00')
      """,
      """
      INSERT INTO order_items (order_id, product_id, quantity, unit_price_cents) VALUES
        (1, 1, 1, 4800),
        (1, 3, 1, 825),
        (2, 2, 1, 6450),
        (3, 1, 1, 4800)
      """,
      """
      INSERT INTO audit_events (actor, action, metadata, created_at) VALUES
        ('system', 'demo.seeded', '{"tables":6}', now() - interval '3 days'),
        ('ada@example.test', 'order.created', '{"order_id":1}', now() - interval '2 days'),
        ('grace@example.test', 'order.shipped', '{"order_id":2,"carrier":"UPS"}', now() - interval '1 day')
      """,
      """
      INSERT INTO import_queue (source, payload, received_at) VALUES
        ('csv-upload', '{"row":1,"status":"needs_review"}', now() - interval '4 hours'),
        ('api-sync', '{"external_id":"abc-123","status":"pending"}', now() - interval '2 hours')
      """,
      """
      INSERT INTO ops.incidents (title, severity, customer_id, opened_at, resolved) VALUES
        ('Delayed branch clone', 'medium', 1, now() - interval '90 minutes', false),
        ('Extension install verification', 'low', 2, now() - interval '1 day', true)
      """,
      """
      INSERT INTO ops.release_checks (release_name, passed, notes, checked_at) VALUES
        ('lantern-demo-v1', true, 'Seed data and schema switcher verified', now() - interval '30 minutes'),
        ('flicker-branch-sandbox', true, 'Ephemeral branches via Flicker API', now())
      """
    ]
  end

  defp source_to_url(%Lantern.Source{} = s) do
    auth =
      if s.password,
        do: "#{URI.encode_www_form(s.username)}:#{URI.encode_www_form(s.password)}",
        else: URI.encode_www_form(s.username)

    "postgres://#{auth}@#{s.hostname}:#{s.port}/#{s.database}"
  end

  defp query!(conn, sql), do: Postgrex.query!(conn, sql, [])
end
