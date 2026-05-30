# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-05-30

### Changed

- A table **without a primary key is now insert-only** rather than fully
  read-only. The "New row" affordance stays available so rows can be added,
  while inline edit and delete — which need a primary key to address an
  existing row — remain disabled. `Lantern.Explorer` now derives `insertable`
  (a table is loaded with columns) separately from `editable` (the table has a
  primary key), and the empty-state note reflects the new behavior.

## [0.2.0] - 2026-05-29

### Added

- Table-level DDL on the `Lantern` facade: `create_table/3`, `drop_table/2`,
  `add_column/3`, `drop_column/3`, `rename_column/4`, and `rename_table/3`.
  Each validates names and builds (and type-checks) its statement before
  opening a connection, so a bad request never spends one.
- `Lantern.SQL` DDL builders and a `validate_type/1` allowlist. Since DDL
  can't parameterize identifiers or types, the safety boundary is
  `quote_ident/1` for every identifier plus a curated type allowlist
  (simple + parameterized `(n)`/`(n,m)` types); injection attempts such as
  `"text; drop table users"` are rejected.
- `Lantern.Explorer` table editor UI: a "New table" dialog (named columns,
  per-column type/nullable/primary-key, add/remove rows), and a per-table
  menu to edit columns (add/rename/drop), rename the table, or drop it.
  Destructive actions are guarded by confirmations.

## [0.1.0] - 2026-05-28

Initial release.

### Added

- `Lantern` data layer: introspection (`list_tables/1`, `columns/2`,
  `primary_keys/2`, `schema/2`), reads with filter/sort/pagination
  (`query/3`), safe primary-key-scoped writes (`insert/3`, `update/4`,
  `delete/3`), and FK lookup options (`reference_options/4`). Values are
  always sent as cast text parameters; nothing is interpolated into SQL.
- `Lantern.Explorer` LiveComponent: table sidebar, sortable/filterable grid,
  inline editing, row insertion, bulk delete, fixed-height shell with
  internal scroll, fullscreen mode (Esc to exit), and an inline filter help
  popover with click-to-apply examples.
- Type-aware editors: dropdowns for booleans, enums, and single-column
  foreign keys; native date/time/datetime pickers; number inputs; a JSON
  textarea with live validation; a `∅` "set NULL" control on nullable
  fields. Arrays render as Postgres array literals and round-trip through
  the editor.
- Connection-agnostic `Lantern.Source`: parses `postgres://` URLs, keyword
  lists, maps, or any struct exposing host/port/username/password/database.
- One-shot connections with `Process.unlink` + `search_path` pinned to
  `public`, so a Postgres disconnect can't kill the host LiveView and DML
  hits the same schema the introspection scanned.
- `:allow_raw_filter` attribute (default `false`). The raw WHERE-fragment
  filter input is hidden unless explicitly opted in for trusted operators.
- Composite-foreign-key safety: detected and excluded from FK dropdowns so
  a mis-paired option can't write the wrong column.
- Standalone `lantern.css` (themeable via `--lt-*` variables, light + dark),
  an optional `lantern.tailwind.css` preset, and a `LanternGrid` JS hook
  (column resize with persistence, set-NULL, JSON validation; cleans up
  window listeners on `destroyed()` and supports touch via `pointercancel`).
- Test suite: pure SQL/Source/Coercion unit tests, real-Postgres integration
  tests (introspection, read/write round-trips, UUID/bytea, enum, FK),
  and event-handler tests that exercise `update/2` + `handle_event/3` on a
  constructed socket. 80 tests + 6 doctests.
