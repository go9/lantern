# Lantern Demo

A Phoenix LiveView showcase for the Lantern ecosystem: the Postgres explorer,
S3 browser, LiveCode editor, and a permanent lantern-ui component reference.
It never asks for production credentials; interactive sandboxes are isolated and
short-lived.

The public deployment is <https://lantern-demo.flickercloud.com>. Run it locally
when developing the demo or component documentation.

## Run it

```bash
cd examples/demo
docker compose up -d
mix setup
mix phx.server
```

Open <http://localhost:4001>. Component documentation starts at
<http://localhost:4001/components>.

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

## Component reference

Every component page uses the real lantern-ui implementation, includes a live
preview and copyable HEEx, and inherits the global light/dark and
compact/comfortable controls. In addition to the existing catalog, the demo now
covers:

- `/components/accordion` — required-open and multiple-open disclosure groups
- `/components/autocomplete` — static filtering plus server-backed grouped search
- `/components/alert-dialog` — cancel-first destructive confirmation semantics
- `/components/skeleton` — accessible loading-region composition and geometry
- `/components/stat` — standalone metrics and responsive linked/unlinked grids

## What the tools demonstrate

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
