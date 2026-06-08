# Lantern Demo

A local Phoenix LiveView app that embeds `Lantern.Explorer` against a disposable
Postgres database seeded with representative tables.

This is intentionally local-only. It does not collect database URLs or ask for
production credentials. Later, the hosted demo can use Flicker to create an
isolated short-lived branch for each visitor and delete it after 15 minutes.

## Run it

```bash
cd examples/demo
docker compose up -d
mix setup
mix phx.server
```

Open <http://localhost:4001>.

The default database URL is:

```text
postgres://postgres:postgres@localhost:5432/lantern_demo
```

Override it if needed:

```bash
export LANTERN_DEMO_DATABASE_URL=postgres://postgres:postgres@localhost:5432/lantern_demo
mix lantern_demo.seed
mix phx.server
```

## What it demonstrates

- table list and automatic first-table selection
- sorting and pagination
- inline edits and inserts
- bulk deletion for tables with primary keys
- insert-only behavior for a table without a primary key
- foreign-key lookup dropdowns
- JSON, arrays, booleans, dates, numerics, and timestamps
- schema editing controls
- component-level styling via `class` and `style`
- fullscreen mode and the bundled `LanternGrid` hook
