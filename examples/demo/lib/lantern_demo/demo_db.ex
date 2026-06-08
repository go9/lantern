defmodule LanternDemo.DemoDB do
  @moduledoc """
  Creates and seeds the local database used by the Lantern demo.

  The demo intentionally uses a database owned by the developer running it. It
  never asks for production credentials and never persists connection strings.
  """

  @default_url "postgres://postgres:postgres@localhost:5432/lantern_demo"

  @doc "Returns the demo database URL."
  @spec url() :: String.t()
  def url, do: System.get_env("LANTERN_DEMO_DATABASE_URL", @default_url)

  @doc "Creates the demo schema and deterministic sample data."
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
        ('flicker-branch-cleanup', false, 'Waiting for hosted ephemeral branch workflow', now())
      """
    ]
  end

  defp query!(conn, sql), do: Postgrex.query!(conn, sql, [])
end
