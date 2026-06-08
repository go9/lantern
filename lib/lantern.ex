defmodule Lantern do
  @moduledoc """
  An embeddable Postgres viewer/editor.

  Lantern is a self-contained data layer plus a `Phoenix.LiveComponent`
  (`Lantern.Explorer`) that lets you browse and edit any Postgres
  database from a connection you supply. It is connection-agnostic: hand it a
  URL string, keyword options, or a struct exposing host/port/username/password
  (see `Lantern.Source`) and it opens short-lived connections on demand.

  This module is the public data API. It performs introspection
  (`list_schemas/1`, `list_tables/2`, `columns/3`, `primary_keys/3`), reads (`query/3`), and safe,
  primary-key-scoped writes (`insert/3`, `update/4`, `delete/3`). Writes send
  values as text parameters cast to each column's type, so no value is ever
  interpolated into SQL.
  """

  alias Lantern.Connection
  alias Lantern.Coercion
  alias Lantern.SQL

  @default_limit 100

  @type source :: Lantern.Source.t() | String.t() | keyword() | map()
  @type column :: %{
          name: String.t(),
          type: String.t(),
          udt: String.t(),
          nullable: boolean(),
          enum_values: [String.t()] | nil,
          fk: %{schema: String.t(), table: String.t(), column: String.t()} | nil
        }

  @type table_stat :: %{
          name: String.t(),
          total_bytes: non_neg_integer(),
          table_bytes: non_neg_integer(),
          index_bytes: non_neg_integer(),
          total_size: String.t(),
          table_size: String.t(),
          index_size: String.t()
        }

  @type table_info :: %{
          schema: String.t(),
          name: String.t(),
          stats: table_stat() | nil,
          estimated_rows: non_neg_integer(),
          row_level_security?: boolean(),
          columns: [column()],
          primary_keys: [String.t()],
          constraints: [%{name: String.t(), type: String.t(), definition: String.t()}],
          indexes: [%{name: String.t(), definition: String.t()}]
        }

  # ---------------------------------------------------------------------------
  # Introspection
  # ---------------------------------------------------------------------------

  @doc "Lists user-visible schemas that contain base tables."
  @spec list_schemas(source()) :: {:ok, [String.t()]} | {:error, String.t()}
  def list_schemas(source) do
    sql = """
    SELECT DISTINCT table_schema
    FROM information_schema.tables
    WHERE table_type = 'BASE TABLE'
      AND table_schema NOT IN ('pg_catalog', 'information_schema')
      AND table_schema NOT LIKE 'pg_toast%'
    ORDER BY table_schema
    """

    Connection.run(source, fn conn ->
      with {:ok, %{rows: rows}} <- run_sql(conn, sql, []) do
        {:ok, Enum.map(rows, &hd/1)}
      end
    end)
  end

  @doc "Lists views in a schema. Defaults to `public`."
  @spec list_views(source(), keyword()) :: {:ok, [String.t()]} | {:error, String.t()}
  def list_views(source, opts \\ []) do
    schema = schema_opt(opts)

    sql = """
    SELECT table_name
    FROM information_schema.views
    WHERE table_schema = $1
    ORDER BY table_name
    """

    Connection.run(source, fn conn ->
      with {:ok, %{rows: rows}} <- run_sql(conn, sql, [schema]) do
        {:ok, Enum.map(rows, &hd/1)}
      end
    end)
  end

  @doc "Lists enum types in a schema. Defaults to `public`."
  @spec list_enums(source(), keyword()) ::
          {:ok, [%{name: String.t(), values: [String.t()]}]} | {:error, String.t()}
  def list_enums(source, opts \\ []) do
    schema = schema_opt(opts)

    Connection.run(source, fn conn ->
      enums = fetch_enums(conn, schema)
      {:ok, Enum.map(enums, fn {name, values} -> %{name: name, values: values} end)}
    end)
  end

  @doc "Lists base tables in a schema. Defaults to `public`."
  @spec list_tables(source(), keyword()) :: {:ok, [String.t()]} | {:error, String.t()}
  def list_tables(source, opts \\ []) do
    schema = schema_opt(opts)

    sql = """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = $1 AND table_type = 'BASE TABLE'
    ORDER BY table_name
    """

    Connection.run(source, fn conn ->
      with {:ok, %{rows: rows}} <- run_sql(conn, sql, [schema]) do
        {:ok, Enum.map(rows, &hd/1)}
      end
    end)
  end

  @doc "Lists base tables with total/table/index size metadata."
  @spec table_stats(source(), keyword()) :: {:ok, [table_stat()]} | {:error, String.t()}
  def table_stats(source, opts \\ []) do
    schema = schema_opt(opts)

    sql = """
    SELECT
      c.relname,
      pg_total_relation_size(c.oid) AS total_bytes,
      pg_relation_size(c.oid) AS table_bytes,
      pg_indexes_size(c.oid) AS index_bytes,
      pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
      pg_size_pretty(pg_relation_size(c.oid)) AS table_size,
      pg_size_pretty(pg_indexes_size(c.oid)) AS index_size
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relkind IN ('r', 'p')
    ORDER BY c.relname
    """

    Connection.run(source, fn conn ->
      with {:ok, %{rows: rows}} <- run_sql(conn, sql, [schema]) do
        {:ok,
         Enum.map(rows, fn [
                             name,
                             total_bytes,
                             table_bytes,
                             index_bytes,
                             total_size,
                             table_size,
                             index_size
                           ] ->
           %{
             name: name,
             total_bytes: total_bytes,
             table_bytes: table_bytes,
             index_bytes: index_bytes,
             total_size: total_size,
             table_size: table_size,
             index_size: index_size
           }
         end)}
      end
    end)
  end

  @doc "Returns detailed metadata for one table."
  @spec table_info(source(), String.t(), keyword()) :: {:ok, table_info()} | {:error, String.t()}
  def table_info(source, table, opts \\ []) do
    schema = schema_opt(opts)

    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, schema, table),
           {:ok, pks} <- fetch_primary_keys(conn, schema, table),
           {:ok, stats} <- fetch_table_stat(conn, schema, table),
           {:ok, rel} <- fetch_table_relation(conn, schema, table),
           {:ok, constraints} <- fetch_constraints(conn, schema, table),
           {:ok, indexes} <- fetch_indexes(conn, schema, table) do
        {:ok,
         %{
           schema: schema,
           name: table,
           stats: stats,
           estimated_rows: rel.estimated_rows,
           row_level_security?: rel.row_level_security?,
           columns: cols,
           primary_keys: pks,
           constraints: constraints,
           indexes: indexes
         }}
      end
    end)
  end

  @doc "Returns column metadata (name, type, udt, nullability) for a table."
  @spec columns(source(), String.t(), keyword()) :: {:ok, [column()]} | {:error, String.t()}
  def columns(source, table, opts \\ []) do
    Connection.run(source, fn conn -> fetch_columns(conn, schema_opt(opts), table) end)
  end

  @doc "Returns the ordered primary-key column names for a table (may be empty)."
  @spec primary_keys(source(), String.t(), keyword()) ::
          {:ok, [String.t()]} | {:error, String.t()}
  def primary_keys(source, table, opts \\ []) do
    Connection.run(source, fn conn -> fetch_primary_keys(conn, schema_opt(opts), table) end)
  end

  # ---------------------------------------------------------------------------
  # Read
  # ---------------------------------------------------------------------------

  @doc """
  Reads rows from `table` with optional filtering, sorting, and pagination.

  ## Options
    * `:schema` — Postgres schema/namespace. Default `"public"`
    * `:where_clause` — raw SQL fragment without `WHERE` (operator's own DB)
    * `:filters` — safe filter descriptors (`%{column:, op:, value:}`) combined with AND
    * `:sort_by` — column name (validated against the live column list)
    * `:sort_dir` — `:asc` (default) or `:desc`
    * `:limit` — default #{@default_limit}
    * `:offset` — default 0
    * `:count` — `:exact` (default) or `false` to skip `COUNT(*)`

  Returns `{:ok, %{columns: [name], rows: [[value]], count: integer | nil, count_kind: atom}}`.
  """
  @spec query(source(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def query(source, table, opts \\ []) do
    schema = schema_opt(opts)
    where_clause = Keyword.get(opts, :where_clause)
    filters = Keyword.get(opts, :filters, [])
    sort_by = Keyword.get(opts, :sort_by)
    sort_dir = Keyword.get(opts, :sort_dir, :asc)
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    count_mode = Keyword.get(opts, :count, :exact)

    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, schema, table),
           names = Enum.map(cols, & &1.name),
           :ok <- ensure_sort_valid(sort_by, names),
           {:ok, filter_clause, filter_params} <- build_filter_clause(filters, cols),
           {:ok, effective_where, params} <-
             combine_where(where_clause, filter_clause, filter_params) do
        {select_sql, _} =
          SQL.select(schema, table, effective_where, sort_by, sort_dir, limit, offset)

        with {:ok, %{columns: result_cols, rows: rows}} <- run_sql(conn, select_sql, params),
             {:ok, count, count_kind} <-
               query_count(conn, schema, table, effective_where, params, count_mode) do
          {:ok, %{columns: result_cols, rows: rows, count: count, count_kind: count_kind}}
        end
      end
    end)
  end

  @doc """
  Runs an operator-supplied SQL statement and returns its columns and rows.

  This is intentionally a low-level escape hatch for trusted database workspaces.
  Embedders should expose it only to operators who are allowed to run arbitrary SQL
  against the configured connection.
  """
  @spec run_query(source(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def run_query(source, sql, opts \\ []) when is_binary(sql) do
    params = Keyword.get(opts, :params, [])

    Connection.run(source, fn conn ->
      with {:ok, %{columns: columns, rows: rows}} <- run_sql(conn, sql, params) do
        {:ok, %{columns: columns || [], rows: rows || []}}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Write
  # ---------------------------------------------------------------------------

  @doc """
  Inserts a row. `values` is a `%{column => value}` map (value `nil` → NULL).

  Returns `{:ok, inserted_row_map}` keyed by column name.
  """
  @spec insert(source(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def insert(source, table, values, opts \\ []) when is_map(values) do
    schema = schema_opt(opts)

    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, schema, table),
           {:ok, fields} <- build_fields(values, cols),
           {:ok, {sql, params}} <- SQL.insert(schema, table, fields),
           {:ok, result} <- run_sql(conn, sql, params) do
        {:ok, single_row(result)}
      end
    end)
  end

  @doc """
  Updates one row identified by its primary key.

  `changes` is `%{column => value}`; `key` is `%{pk_column => value}`. Requires
  the table to have a primary key and `key` to cover it exactly.
  """
  @spec update(source(), String.t(), map(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def update(source, table, changes, key, opts \\ []) when is_map(changes) and is_map(key) do
    schema = schema_opt(opts)

    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, schema, table),
           {:ok, pks} <- fetch_primary_keys(conn, schema, table),
           :ok <- ensure_key_matches(key, pks),
           {:ok, set_fields} <- build_fields(changes, cols),
           {:ok, pk_fields} <- build_fields(key, cols),
           {:ok, {sql, params}} <- SQL.update(schema, table, set_fields, pk_fields),
           {:ok, result} <- run_sql(conn, sql, params) do
        {:ok, single_row(result)}
      end
    end)
  end

  @doc """
  Applies update/delete changes in one database transaction.

  Changes are maps with either `%{action: :update, changes: map, key: map}` or
  `%{action: :delete, keys: [map]}`. Returns `{:ok, count}` for applied change
  groups, or rolls the transaction back and returns the first error.
  """
  @spec apply_changes(source(), String.t(), [map()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def apply_changes(source, table, changes, opts \\ []) when is_list(changes) do
    schema = schema_opt(opts)

    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, schema, table),
           {:ok, pks} <- fetch_primary_keys(conn, schema, table) do
        case Postgrex.transaction(conn, fn tx ->
               Enum.reduce_while(changes, {:ok, 0}, fn change, {:ok, count} ->
                 case apply_change(tx, schema, table, change, cols, pks) do
                   :ok -> {:cont, {:ok, count + 1}}
                   {:error, reason} -> Postgrex.rollback(tx, reason)
                 end
               end)
             end) do
          {:ok, {:ok, count}} -> {:ok, count}
          {:error, reason} -> {:error, reason}
        end
      end
    end)
  end

  @doc """
  Deletes one or more rows. `keys` is a list of `%{pk_column => value}` maps.

  Returns `{:ok, deleted_count}`.
  """
  @spec delete(source(), String.t(), [map()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def delete(source, table, keys, opts \\ [])
  def delete(_source, _table, [], _opts), do: {:ok, 0}

  def delete(source, table, keys, opts) when is_list(keys) do
    schema = schema_opt(opts)

    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, schema, table),
           {:ok, pks} <- fetch_primary_keys(conn, schema, table),
           :ok <- ensure_keys_match(keys, pks),
           {:ok, rows} <- build_key_rows(keys, cols),
           {:ok, {sql, params}} <- SQL.delete(schema, table, rows),
           {:ok, %{num_rows: n}} <- run_sql(conn, sql, params) do
        {:ok, n}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Schema changes (DDL)
  # ---------------------------------------------------------------------------

  @doc """
  Creates a table. `columns` is a list of column specs (see
  `t:Lantern.SQL.column/0`); at least one is required.

  Returns `:ok` or `{:error, message}` — both validation failures (blank name,
  no columns, unsupported type) and Postgres errors come back as a message
  string ready to show the operator.
  """
  @spec create_table(source(), String.t(), [SQL.column()], keyword()) ::
          :ok | {:error, String.t()}
  def create_table(source, table, columns, opts \\ []) when is_list(columns) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         {:ok, statement} <- build_ddl(SQL.create_table(schema, table, columns)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Drops a table. Returns `:ok` or `{:error, message}`."
  @spec drop_table(source(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def drop_table(source, table, opts \\ []) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         {:ok, statement} <- build_ddl(SQL.drop_table(schema, table)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Adds a column. `column` is a column spec. Returns `:ok` or `{:error, message}`."
  @spec add_column(source(), String.t(), SQL.column(), keyword()) :: :ok | {:error, String.t()}
  def add_column(source, table, column, opts \\ []) when is_map(column) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         {:ok, statement} <- build_ddl(SQL.add_column(schema, table, column)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Drops a column. Returns `:ok` or `{:error, message}`."
  @spec drop_column(source(), String.t(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def drop_column(source, table, column, opts \\ []) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         :ok <- validate_name("Column name", column),
         {:ok, statement} <- build_ddl(SQL.drop_column(schema, table, column)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Changes a column's type. Returns `:ok` or `{:error, message}`."
  @spec alter_column_type(source(), String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, String.t()}
  def alter_column_type(source, table, column, type, opts \\ []) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         :ok <- validate_name("Column name", column),
         {:ok, statement} <- build_ddl(SQL.alter_column_type(schema, table, column, type)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Sets whether a column accepts NULL. Returns `:ok` or `{:error, message}`."
  @spec set_column_nullable(source(), String.t(), String.t(), boolean(), keyword()) ::
          :ok | {:error, String.t()}
  def set_column_nullable(source, table, column, nullable, opts \\ [])
      when is_boolean(nullable) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         :ok <- validate_name("Column name", column),
         {:ok, statement} <- build_ddl(SQL.set_column_nullable(schema, table, column, nullable)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Renames a column. Returns `:ok` or `{:error, message}`."
  @spec rename_column(source(), String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, String.t()}
  def rename_column(source, table, from, to, opts \\ []) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         :ok <- validate_name("Column name", from),
         :ok <- validate_name("New column name", to),
         {:ok, statement} <- build_ddl(SQL.rename_column(schema, table, from, to)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Drops a table constraint. Returns `:ok` or `{:error, message}`."
  @spec drop_constraint(source(), String.t(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def drop_constraint(source, table, constraint_name, opts \\ []) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         :ok <- validate_name("Constraint name", constraint_name),
         {:ok, statement} <- build_ddl(SQL.drop_constraint(schema, table, constraint_name)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Creates an index on a table. Returns `:ok` or `{:error, message}`."
  @spec create_index(source(), String.t(), String.t(), [String.t()], keyword()) ::
          :ok | {:error, String.t()}
  def create_index(source, table, index_name, columns, opts \\ []) when is_list(columns) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         :ok <- validate_name("Index name", index_name),
         :ok <- validate_column_names(columns),
         {:ok, statement} <- build_ddl(SQL.create_index(schema, table, index_name, columns)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Drops an index. Returns `:ok` or `{:error, message}`."
  @spec drop_index(source(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def drop_index(source, index_name, opts \\ []) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Index name", index_name),
         {:ok, statement} <- build_ddl(SQL.drop_index(schema, index_name)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Renames a table. Returns `:ok` or `{:error, message}`."
  @spec rename_table(source(), String.t(), String.t(), keyword()) :: :ok | {:error, String.t()}
  def rename_table(source, table, new_name, opts \\ []) do
    schema = schema_opt(opts)

    with :ok <- validate_name("Schema name", schema),
         :ok <- validate_name("Table name", table),
         :ok <- validate_name("New table name", new_name),
         {:ok, statement} <- build_ddl(SQL.rename_table(schema, table, new_name)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private — introspection queries
  # ---------------------------------------------------------------------------

  defp apply_change(
         conn,
         schema,
         table,
         %{action: :update, changes: changes, key: key},
         cols,
         pks
       ) do
    with :ok <- ensure_key_matches(key, pks),
         {:ok, set_fields} <- build_fields(changes, cols),
         {:ok, pk_fields} <- build_fields(key, cols),
         {:ok, {sql, params}} <- SQL.update(schema, table, set_fields, pk_fields),
         {:ok, _result} <- run_sql(conn, sql, params) do
      :ok
    end
  end

  defp apply_change(conn, schema, table, %{action: :delete, keys: keys}, cols, pks) do
    with :ok <- ensure_keys_match(keys, pks),
         {:ok, rows} <- build_key_rows(keys, cols),
         {:ok, {sql, params}} <- SQL.delete(schema, table, rows),
         {:ok, _result} <- run_sql(conn, sql, params) do
      :ok
    end
  end

  defp apply_change(_conn, _schema, _table, _change, _cols, _pks), do: {:error, :invalid_change}

  defp fetch_table_stat(conn, schema, table) do
    sql = """
    SELECT
      c.relname,
      pg_total_relation_size(c.oid) AS total_bytes,
      pg_relation_size(c.oid) AS table_bytes,
      pg_indexes_size(c.oid) AS index_bytes,
      pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
      pg_size_pretty(pg_relation_size(c.oid)) AS table_size,
      pg_size_pretty(pg_indexes_size(c.oid)) AS index_size
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relname = $2 AND c.relkind IN ('r', 'p')
    """

    case run_sql(conn, sql, [schema, table]) do
      {:ok,
       %{
         rows: [[name, total_bytes, table_bytes, index_bytes, total_size, table_size, index_size]]
       }} ->
        {:ok,
         %{
           name: name,
           total_bytes: total_bytes,
           table_bytes: table_bytes,
           index_bytes: index_bytes,
           total_size: total_size,
           table_size: table_size,
           index_size: index_size
         }}

      {:ok, %{rows: []}} ->
        {:ok, nil}

      other ->
        other
    end
  end

  defp fetch_table_relation(conn, schema, table) do
    sql = """
    SELECT GREATEST(c.reltuples::bigint, 0), c.relrowsecurity
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relname = $2 AND c.relkind IN ('r', 'p')
    """

    case run_sql(conn, sql, [schema, table]) do
      {:ok, %{rows: [[estimated_rows, row_level_security?]]}} ->
        {:ok, %{estimated_rows: estimated_rows, row_level_security?: row_level_security?}}

      {:ok, %{rows: []}} ->
        {:ok, %{estimated_rows: 0, row_level_security?: false}}

      other ->
        other
    end
  end

  defp fetch_constraints(conn, schema, table) do
    sql = """
    SELECT con.conname,
           CASE con.contype
             WHEN 'p' THEN 'PRIMARY KEY'
             WHEN 'f' THEN 'FOREIGN KEY'
             WHEN 'u' THEN 'UNIQUE'
             WHEN 'c' THEN 'CHECK'
             WHEN 'x' THEN 'EXCLUDE'
             ELSE con.contype::text
           END,
           pg_get_constraintdef(con.oid, true)
    FROM pg_constraint con
    JOIN pg_class c ON c.oid = con.conrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1 AND c.relname = $2
    ORDER BY con.contype DESC, con.conname
    """

    case run_sql(conn, sql, [schema, table]) do
      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(rows, fn [name, type, definition] ->
           %{name: name, type: type, definition: definition}
         end)}

      other ->
        other
    end
  end

  defp fetch_indexes(conn, schema, table) do
    sql = """
    SELECT indexname, indexdef
    FROM pg_indexes
    WHERE schemaname = $1 AND tablename = $2
    ORDER BY indexname
    """

    case run_sql(conn, sql, [schema, table]) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, fn [name, definition] -> %{name: name, definition: definition} end)}

      other ->
        other
    end
  end

  defp fetch_columns(conn, schema, table) do
    sql = """
    SELECT column_name, data_type, udt_name, is_nullable
    FROM information_schema.columns
    WHERE table_schema = $1 AND table_name = $2
    ORDER BY ordinal_position
    """

    case run_sql(conn, sql, [schema, table]) do
      {:ok, %{rows: []}} ->
        {:error, "Table not found: #{table}"}

      {:ok, %{rows: rows}} ->
        enums = fetch_enums(conn, schema)
        fks = fetch_foreign_keys(conn, schema, table)

        cols =
          Enum.map(rows, fn [name, type, udt, nullable] ->
            %{
              name: name,
              type: type,
              udt: udt,
              nullable: nullable == "YES",
              enum_values: Map.get(enums, udt),
              fk: Map.get(fks, name)
            }
          end)

        {:ok, cols}

      other ->
        other
    end
  end

  # Maps each foreign-key column to the table/column it references, so the UI
  # can offer a lookup dropdown instead of a raw id field. Composite foreign
  # keys are deliberately skipped: the information_schema join below produces
  # a cross product across all (local, referenced) pairs in the constraint, so
  # we can't reliably pair them by ordinal position. Treating composite-FK
  # columns as plain text is safer than offering a dropdown that might write
  # the wrong value into the wrong column.
  defp fetch_foreign_keys(conn, schema, table) do
    sql = """
    SELECT tc.constraint_name, kcu.column_name, ccu.table_schema, ccu.table_name, ccu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = $1 AND tc.table_name = $2
    """

    case run_sql(conn, sql, [schema, table]) do
      {:ok, %{rows: rows}} ->
        rows
        |> Enum.group_by(fn [constraint, _, _, _, _] -> constraint end)
        |> Enum.flat_map(fn
          # Single-column FK → 1 cross-product row → safe to expose.
          {_constraint, [[_, col, fschema, ftable, fcol]]} ->
            [{col, %{schema: fschema, table: ftable, column: fcol}}]

          # Composite FK (or anything that produced > 1 row) → skip.
          _ ->
            []
        end)
        |> Map.new()

      _ ->
        %{}
    end
  end

  @doc """
  Returns up to `limit` `{value, label}` options from a referenced table, for
  rendering a foreign-key lookup. Labels prefer a human-readable column
  (name/title/email/…) and fall back to the referenced key itself.
  """
  @spec reference_options(source(), String.t(), String.t(), pos_integer(), keyword()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, term()}
  def reference_options(source, ftable, fcolumn, limit \\ 100, opts \\ []) do
    schema = schema_opt(opts)

    Connection.run(source, fn conn ->
      do_reference_options(conn, schema, ftable, fcolumn, limit)
    end)
  end

  defp do_reference_options(conn, schema, ftable, fcolumn, limit) do
    # Clamp the caller-supplied limit so a bad value can't end up in the SQL
    # string. (Identifiers are already quoted via SQL.quote_ident.)
    limit = if is_integer(limit) and limit > 0, do: min(limit, 1000), else: 100

    with {:ok, cols} <- fetch_columns(conn, schema, ftable) do
      names = Enum.map(cols, & &1.name)
      label = Enum.find(~w(name title label display_name email username slug), &(&1 in names))
      label_col = label || fcolumn

      sql =
        "SELECT #{SQL.quote_ident(fcolumn)}, #{SQL.quote_ident(label_col)} " <>
          "FROM #{SQL.quote_table(schema, ftable)} ORDER BY 2 LIMIT #{limit}"

      fcol_type = Enum.find_value(cols, &if(&1.name == fcolumn, do: &1.type))

      case run_sql(conn, sql, []) do
        {:ok, %{rows: rows}} ->
          {:ok, Enum.map(rows, &reference_row(&1, label != nil, fcol_type))}

        other ->
          other
      end
    end
  end

  @doc """
  Loads everything `Lantern.Explorer` needs to display a table — columns
  (typed), primary keys, and pre-fetched FK lookup options — using a single
  Postgres connection instead of N+1.
  """
  @spec schema(source(), String.t(), keyword()) ::
          {:ok, %{columns: [column()], primary_keys: [String.t()], fk_options: map()}}
          | {:error, String.t()}
  def schema(source, table, opts \\ []) do
    schema = schema_opt(opts)

    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, schema, table),
           {:ok, pks} <- fetch_primary_keys(conn, schema, table) do
        fk_options =
          for %{name: name, fk: fk} <- cols, fk != nil, into: %{} do
            case do_reference_options(
                   conn,
                   Map.get(fk, :schema, schema),
                   fk.table,
                   fk.column,
                   100
                 ) do
              {:ok, opts} -> {name, opts}
              _ -> {name, nil}
            end
          end

        {:ok, %{columns: cols, primary_keys: pks, fk_options: fk_options}}
      end
    end)
  end

  defp reference_row([value, label], labeled?, fcol_type) do
    value_str = Coercion.edit_value(value, fcol_type)
    text = if labeled?, do: "#{Coercion.edit_value(label)} — #{value_str}", else: value_str
    {value_str, text}
  end

  # Maps each enum type name to its ordered labels, so enum columns can render
  # as dropdowns instead of free text.
  defp fetch_enums(conn, schema) do
    # Scope to the selected schema so two enums with the same name in
    # different schemas don't merge their labels.
    sql = """
    SELECT t.typname, e.enumlabel
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = $1
    ORDER BY t.typname, e.enumsortorder
    """

    case run_sql(conn, sql, [schema]) do
      {:ok, %{rows: rows}} ->
        # Build with prepends + reverse, not list ++, to keep this O(n).
        rows
        |> Enum.reduce(%{}, fn [name, label], acc ->
          Map.update(acc, name, [label], &[label | &1])
        end)
        |> Map.new(fn {name, labels} -> {name, Enum.reverse(labels)} end)

      _ ->
        %{}
    end
  end

  defp fetch_primary_keys(conn, schema, table) do
    sql = """
    SELECT a.attname
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE c.relname = $1 AND n.nspname = $2 AND i.indisprimary
    ORDER BY array_position(i.indkey, a.attnum)
    """

    case run_sql(conn, sql, [table, schema]) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &hd/1)}
      other -> other
    end
  end

  # ---------------------------------------------------------------------------
  # Private — field building / validation
  # ---------------------------------------------------------------------------

  defp build_fields(values, cols) do
    types = Map.new(cols, fn c -> {c.name, c} end)

    Enum.reduce_while(values, {:ok, []}, fn {column, value}, {:ok, acc} ->
      name = to_string(column)

      case Map.fetch(types, name) do
        {:ok, col} ->
          field = %{column: name, value: value, cast: Coercion.cast_expr(col.type, col.udt)}
          {:cont, {:ok, acc ++ [field]}}

        :error ->
          {:halt, {:error, "Unknown column: #{name}"}}
      end
    end)
  end

  defp build_key_rows(keys, cols) do
    Enum.reduce_while(keys, {:ok, []}, fn key, {:ok, acc} ->
      case build_fields(key, cols) do
        {:ok, fields} -> {:cont, {:ok, acc ++ [fields]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_filter_clause([], _cols), do: {:ok, nil, []}

  defp build_filter_clause(filters, cols) when is_list(filters) do
    names = MapSet.new(Enum.map(cols, & &1.name))

    filters
    |> Enum.reject(&empty_filter?/1)
    |> Enum.reduce_while({[], []}, fn filter, {parts, params} ->
      column = filter |> Map.get(:column, Map.get(filter, "column")) |> to_string()
      op = filter |> Map.get(:op, Map.get(filter, "op")) |> normalize_op()
      value = Map.get(filter, :value, Map.get(filter, "value"))

      cond do
        not MapSet.member?(names, column) ->
          {:halt, {:error, "Invalid filter column: #{column}"}}

        op in [:is_null, :is_not_null] ->
          sql_op = if op == :is_null, do: "IS NULL", else: "IS NOT NULL"
          {:cont, {parts ++ ["#{SQL.quote_ident(column)} #{sql_op}"], params}}

        op in [:eq, :neq, :gt, :lt, :gte, :lte, :contains] ->
          idx = length(params) + 1
          {sql_op, param} = filter_op(op, value)
          {:cont, {parts ++ ["#{SQL.quote_ident(column)} #{sql_op} $#{idx}"], params ++ [param]}}

        true ->
          {:halt, {:error, "Invalid filter operator: #{inspect(op)}"}}
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      {[], []} -> {:ok, nil, []}
      {parts, params} -> {:ok, Enum.join(parts, " AND "), params}
    end
  end

  defp build_filter_clause(_filters, _cols), do: {:error, "Invalid filters"}

  defp empty_filter?(filter) do
    value = Map.get(filter, :value, Map.get(filter, "value"))
    op = filter |> Map.get(:op, Map.get(filter, "op")) |> normalize_op()
    op not in [:is_null, :is_not_null] and (is_nil(value) or value == "")
  end

  defp normalize_op(op)
       when op in [:eq, :neq, :gt, :lt, :gte, :lte, :contains, :is_null, :is_not_null],
       do: op

  defp normalize_op("eq"), do: :eq
  defp normalize_op("neq"), do: :neq
  defp normalize_op("gt"), do: :gt
  defp normalize_op("lt"), do: :lt
  defp normalize_op("gte"), do: :gte
  defp normalize_op("lte"), do: :lte
  defp normalize_op("contains"), do: :contains
  defp normalize_op("is_null"), do: :is_null
  defp normalize_op("is_not_null"), do: :is_not_null
  defp normalize_op(_), do: :invalid

  defp filter_op(:eq, value), do: {"=", value}
  defp filter_op(:neq, value), do: {"<>", value}
  defp filter_op(:gt, value), do: {">", value}
  defp filter_op(:lt, value), do: {"<", value}
  defp filter_op(:gte, value), do: {">=", value}
  defp filter_op(:lte, value), do: {"<=", value}
  defp filter_op(:contains, value), do: {"ILIKE", "%#{value}%"}

  defp combine_where(nil, nil, _params), do: {:ok, nil, []}
  defp combine_where("", nil, _params), do: {:ok, nil, []}
  defp combine_where(raw, nil, _params), do: {:ok, raw, []}
  defp combine_where(nil, safe, params), do: {:ok, safe, params}
  defp combine_where("", safe, params), do: {:ok, safe, params}

  defp combine_where(_raw, _safe, _params),
    do: {:error, "Use either raw SQL filter or safe filters, not both"}

  defp query_count(_conn, _schema, _table, _where_clause, _params, false), do: {:ok, nil, :none}

  defp query_count(conn, schema, table, where_clause, params, _mode) do
    {count_sql, _} = SQL.count(schema, table, where_clause)

    with {:ok, %{rows: [[count]]}} <- run_sql(conn, count_sql, params) do
      {:ok, count, :exact}
    end
  end

  defp schema_opt(opts), do: Keyword.get(opts, :schema, "public") |> to_string()

  defp ensure_sort_valid(nil, _names), do: :ok

  defp ensure_sort_valid(col, names) do
    if col in names, do: :ok, else: {:error, "Invalid sort column: #{col}"}
  end

  defp ensure_key_matches(_key, []), do: {:error, :no_primary_key}

  defp ensure_key_matches(key, pks) do
    provided = key |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    if provided == Enum.sort(pks), do: :ok, else: {:error, :key_mismatch}
  end

  defp ensure_keys_match(keys, pks) do
    Enum.reduce_while(keys, :ok, fn key, :ok ->
      case ensure_key_matches(key, pks) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — execution helpers
  # ---------------------------------------------------------------------------

  defp run_sql(conn, sql, params) do
    case Postgrex.query(conn, sql, params) do
      {:ok, result} -> {:ok, result}
      {:error, error} -> {:error, format_error(error)}
    end
  end

  # Translates a SQL builder result into an executable statement or a
  # human-readable validation message, before any connection is opened.
  defp build_ddl({:ok, statement}), do: {:ok, statement}
  defp build_ddl({:error, reason}), do: {:error, ddl_error(reason)}

  defp exec_ddl(conn, {sql, params}) do
    with {:ok, _result} <- run_sql(conn, sql, params), do: :ok
  end

  defp validate_column_names([]), do: {:error, "Add at least one index column"}

  defp validate_column_names(columns) do
    Enum.reduce_while(columns, :ok, fn column, :ok ->
      case validate_name("Column name", column) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_name(label, name) do
    if is_binary(name) and String.trim(name) != "" do
      :ok
    else
      {:error, "#{label} can't be blank"}
    end
  end

  defp ddl_error(:no_columns), do: "Add at least one column"
  defp ddl_error(:missing_name), do: "Every column needs a name"
  defp ddl_error({:invalid_type, type}), do: "Unsupported column type: #{type}"
  defp ddl_error(other), do: format_error(other)

  defp single_row(%{columns: cols, rows: [row | _]}), do: Enum.zip(cols, row) |> Map.new()
  defp single_row(%{columns: cols, rows: []}), do: cols |> Enum.map(&{&1, nil}) |> Map.new()

  # All DB/query errors humanize through one place so nothing reaches the UI as
  # a raw struct (connection failures, Postgres errors, hints). See Lantern.Errors.
  defp format_error(reason), do: Lantern.Errors.humanize(reason)
end
