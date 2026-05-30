# Lantern

An embeddable Postgres **table viewer and editor** for Phoenix LiveView. Hand
it a database connection and drop the component into any LiveView — you get a
sidebar of tables, a sortable/filterable grid, inline editing, row insertion,
bulk delete, type-aware inputs, foreign-key lookups, and fullscreen mode.

- **Drop-in** — one `live_component`, a stylesheet, and a JS hook. No Fluxon, no
  icon library, no design-system assumptions.
- **Connection-agnostic** — point it at any Postgres via a `postgres://` URL, a
  keyword list, a map, or a struct. It opens short-lived connections; there's
  no pool for you to supervise.
- **Safe writes** — every value is sent as a cast text parameter
  (`$1::text::int4`), never interpolated into SQL. Edits and deletes are scoped
  to the row's primary key; a table without one is insert-only (you can add
  rows, but not edit or delete existing ones).
- **Schema editing** — create and drop tables, add/rename/drop columns, and
  rename tables from the UI or the data API. Identifiers are always quoted and
  column types pass an allowlist, so DDL can't be used for injection.
- **Themeable** — all styling is semantic `lt-*` classes in a low-priority
  cascade layer, driven by `--lt-*` CSS variables. Override a handful of
  variables, or any class, with zero specificity fights.

> ⚠️ **Lantern exposes whatever database you connect it to, including every
> column.** It is meant for operators/admins. Always put it behind your own
> authentication and authorization — see [Security](#security). The raw SQL
> filter input is **disabled by default**; pass `allow_raw_filter: true` to
> enable it only in trusted operator contexts.

## Installation

Add Lantern to your deps. From Hex:

```elixir
def deps do
  [{:lantern, "~> 0.1.0"}]
end
```

Or straight from GitHub:

```elixir
def deps do
  [{:lantern, github: "go9/lantern"}]
end
```

Lantern needs `phoenix_live_view ~> 1.0`, `postgrex`, and `jason` (all pulled in
transitively).

## Quick start

Render the component in any LiveView, passing a `:source`:

```elixir
def render(assigns) do
  ~H"""
  <.live_component
    module={Lantern.Explorer}
    id="db"
    source={"postgres://user:pass@localhost:5432/my_db"}
    title="My database"
  />
  """
end
```

Then wire up the [CSS](#styling) and the [JS hook](#javascript-hook). That's it.

## Connection sources

`:source` is anything `Lantern.Source.from/1` accepts:

```elixir
# URL string
"postgres://user:pass@host:5432/my_db?sslmode=require"

# keyword list / map
[hostname: "localhost", port: 5432, username: "postgres",
 password: "postgres", database: "my_db"]

# a struct/record exposing host(name)/port/username/password/database,
# e.g. one you already use to describe a tenant or branch database
%MyApp.Database{host: "...", port: 5432, username: "...", password: "...", database: "..."}
```

## Styling

Import the bundled stylesheet so the explorer looks good out of the box. With
esbuild/Tailwind, import it from the dep in your `app.css`:

```css
@import "../../deps/lantern/priv/static/lantern/lantern.css";
```

It's self-contained and lives in a low-priority `@layer lantern`, so any rule
you write outside that layer overrides it. Re-theme by setting `--lt-*`
variables on `.lantern` (or a parent):

```css
.lantern {
  --lt-accent: #e0552d;
  --lt-radius: 0.75rem;
  --lt-height: 720px;     /* fixed shell height */
  --lt-font: "Inter", sans-serif;
  --lt-mono: "JetBrains Mono", monospace;
}
```

Force dark mode with `.lantern.lt-dark`; otherwise it follows the OS setting.

**Using Tailwind?** Optionally import the preset to map Lantern's variables onto
your Tailwind color scale:

```css
@import "../../deps/lantern/priv/static/lantern/lantern.css";
@import "../../deps/lantern/priv/static/lantern/lantern.tailwind.css";
```

## JavaScript hook

Column resizing, the "set NULL" buttons, and live JSON validation use a
LiveView hook. Register it on your `LiveSocket`. With esbuild, point at the dep:

```js
import { LanternGrid } from "../deps/lantern/priv/static/lantern/hooks"

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: { LanternGrid },
})
```

(Browsing and editing still work without the hook — you just lose resizing,
one-click NULL, and the JSON syntax highlight.)

## Headless data API

The data layer is usable on its own, without the component:

```elixir
{:ok, tables}  = Lantern.list_tables(source)
{:ok, columns} = Lantern.columns(source, "users")          # name, type, nullable, enum, fk
{:ok, page}    = Lantern.query(source, "users",
                   where_clause: "active = true",
                   sort_by: "inserted_at", sort_dir: :desc,
                   limit: 50, offset: 0)

{:ok, row}     = Lantern.insert(source, "users", %{"email" => "a@b.co"})
{:ok, updated} = Lantern.update(source, "users", %{"name" => "Ada"}, %{"id" => "1"})
{:ok, count}   = Lantern.delete(source, "users", [%{"id" => "1"}, %{"id" => "2"}])
```

Write values are passed as strings (or `nil` for SQL `NULL`) and cast to each
column's type by Postgres.

Schema changes (DDL) are available too. Identifiers are quoted and types are
checked against an allowlist before anything touches the database:

```elixir
:ok = Lantern.create_table(source, "widgets", [
        %{name: "id", type: "bigserial", nullable: false, primary_key: true},
        %{name: "label", type: "text"}
      ])
:ok = Lantern.add_column(source, "widgets", %{name: "qty", type: "integer"})
:ok = Lantern.rename_column(source, "widgets", "label", "name")
:ok = Lantern.drop_column(source, "widgets", "qty")
:ok = Lantern.rename_table(source, "widgets", "gadgets")
:ok = Lantern.drop_table(source, "gadgets")
```

## Security

Lantern runs arbitrary reads and writes against the database you give it. By
default, **the raw SQL filter input is hidden** (`allow_raw_filter: false`),
because a literal SQL fragment appended after `WHERE` can execute data-
modifying CTEs, sub-selects, and other arbitrary SQL under the connection
role's privileges — that's an open SQL proxy in disguise.

For operator-facing pages where you trust the user, opt in:

```elixir
<.live_component module={Lantern.Explorer} id="db" source={...} allow_raw_filter={true} />
```

You are responsible for:

- Gating the page behind authentication/authorization (e.g. an admin pipeline).
- Only handing Lantern a `:source` you control. Never build a `:source` from
  untrusted user input — that turns your server into an open SQL proxy.
- Only enabling `allow_raw_filter: true` in trusted operator contexts.

Because the connection is operator-supplied, Lantern itself adds no extra
sandboxing; the trust boundary is your auth layer.

## Development

```bash
mix deps.get
mix test                      # unit tests (no database needed)
```

Integration tests run real Postgres round-trips and are excluded by default.
Point them at a database you can create/drop tables in:

```bash
LANTERN_TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/lantern_test \
  mix test --include integration
```

## License

MIT © John Orlando. See [LICENSE](LICENSE).
