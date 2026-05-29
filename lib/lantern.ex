defmodule Lantern do
  @moduledoc """
  An embeddable Postgres viewer/editor.

  Lantern is a self-contained data layer plus a `Phoenix.LiveComponent`
  (`Lantern.Explorer`) that lets you browse and edit any Postgres
  database from a connection you supply. It is connection-agnostic: hand it a
  URL string, keyword options, or a struct exposing host/port/username/password
  (see `Lantern.Source`) and it opens short-lived connections on demand.

  This module is the public data API. It performs introspection
  (`list_tables/1`, `columns/2`, `primary_keys/2`), reads (`query/3`), and safe,
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
          fk: %{table: String.t(), column: String.t()} | nil
        }

  # ---------------------------------------------------------------------------
  # Introspection
  # ---------------------------------------------------------------------------

  @doc "Lists base tables in the `public` schema."
  @spec list_tables(source()) :: {:ok, [String.t()]} | {:error, String.t()}
  def list_tables(source) do
    sql = """
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
    ORDER BY table_name
    """

    Connection.run(source, fn conn ->
      with {:ok, %{rows: rows}} <- run_sql(conn, sql, []) do
        {:ok, Enum.map(rows, &hd/1)}
      end
    end)
  end

  @doc "Returns column metadata (name, type, udt, nullability) for a table."
  @spec columns(source(), String.t()) :: {:ok, [column()]} | {:error, String.t()}
  def columns(source, table) do
    Connection.run(source, fn conn -> fetch_columns(conn, table) end)
  end

  @doc "Returns the ordered primary-key column names for a table (may be empty)."
  @spec primary_keys(source(), String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def primary_keys(source, table) do
    Connection.run(source, fn conn -> fetch_primary_keys(conn, table) end)
  end

  # ---------------------------------------------------------------------------
  # Read
  # ---------------------------------------------------------------------------

  @doc """
  Reads rows from `table` with optional filtering, sorting, and pagination.

  ## Options
    * `:where_clause` — raw SQL fragment without `WHERE` (operator's own DB)
    * `:sort_by` — column name (validated against the live column list)
    * `:sort_dir` — `:asc` (default) or `:desc`
    * `:limit` — default #{@default_limit}
    * `:offset` — default 0

  Returns `{:ok, %{columns: [name], rows: [[value]], count: integer}}`.
  """
  @spec query(source(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def query(source, table, opts \\ []) do
    where_clause = Keyword.get(opts, :where_clause)
    sort_by = Keyword.get(opts, :sort_by)
    sort_dir = Keyword.get(opts, :sort_dir, :asc)
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, table),
           names = Enum.map(cols, & &1.name),
           :ok <- ensure_sort_valid(sort_by, names) do
        {select_sql, _} = SQL.select(table, where_clause, sort_by, sort_dir, limit, offset)
        {count_sql, _} = SQL.count(table, where_clause)

        with {:ok, %{columns: result_cols, rows: rows}} <- run_sql(conn, select_sql, []),
             {:ok, %{rows: [[count]]}} <- run_sql(conn, count_sql, []) do
          {:ok, %{columns: result_cols, rows: rows, count: count}}
        end
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
  @spec insert(source(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def insert(source, table, values) when is_map(values) do
    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, table),
           {:ok, fields} <- build_fields(values, cols),
           {:ok, {sql, params}} <- SQL.insert(table, fields),
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
  @spec update(source(), String.t(), map(), map()) :: {:ok, map()} | {:error, term()}
  def update(source, table, changes, key) when is_map(changes) and is_map(key) do
    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, table),
           {:ok, pks} <- fetch_primary_keys(conn, table),
           :ok <- ensure_key_matches(key, pks),
           {:ok, set_fields} <- build_fields(changes, cols),
           {:ok, pk_fields} <- build_fields(key, cols),
           {:ok, {sql, params}} <- SQL.update(table, set_fields, pk_fields),
           {:ok, result} <- run_sql(conn, sql, params) do
        {:ok, single_row(result)}
      end
    end)
  end

  @doc """
  Deletes one or more rows. `keys` is a list of `%{pk_column => value}` maps.

  Returns `{:ok, deleted_count}`.
  """
  @spec delete(source(), String.t(), [map()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def delete(_source, _table, []), do: {:ok, 0}

  def delete(source, table, keys) when is_list(keys) do
    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, table),
           {:ok, pks} <- fetch_primary_keys(conn, table),
           :ok <- ensure_keys_match(keys, pks),
           {:ok, rows} <- build_key_rows(keys, cols),
           {:ok, {sql, params}} <- SQL.delete(table, rows),
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
  @spec create_table(source(), String.t(), [SQL.column()]) :: :ok | {:error, String.t()}
  def create_table(source, table, columns) when is_list(columns) do
    with :ok <- validate_name("Table name", table),
         {:ok, statement} <- build_ddl(SQL.create_table(table, columns)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Drops a table. Returns `:ok` or `{:error, message}`."
  @spec drop_table(source(), String.t()) :: :ok | {:error, String.t()}
  def drop_table(source, table) do
    with :ok <- validate_name("Table name", table),
         {:ok, statement} <- build_ddl(SQL.drop_table(table)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Adds a column. `column` is a column spec. Returns `:ok` or `{:error, message}`."
  @spec add_column(source(), String.t(), SQL.column()) :: :ok | {:error, String.t()}
  def add_column(source, table, column) when is_map(column) do
    with :ok <- validate_name("Table name", table),
         {:ok, statement} <- build_ddl(SQL.add_column(table, column)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Drops a column. Returns `:ok` or `{:error, message}`."
  @spec drop_column(source(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def drop_column(source, table, column) do
    with :ok <- validate_name("Table name", table),
         :ok <- validate_name("Column name", column),
         {:ok, statement} <- build_ddl(SQL.drop_column(table, column)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Renames a column. Returns `:ok` or `{:error, message}`."
  @spec rename_column(source(), String.t(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def rename_column(source, table, from, to) do
    with :ok <- validate_name("Table name", table),
         :ok <- validate_name("Column name", from),
         :ok <- validate_name("New column name", to),
         {:ok, statement} <- build_ddl(SQL.rename_column(table, from, to)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  @doc "Renames a table. Returns `:ok` or `{:error, message}`."
  @spec rename_table(source(), String.t(), String.t()) :: :ok | {:error, String.t()}
  def rename_table(source, table, new_name) do
    with :ok <- validate_name("Table name", table),
         :ok <- validate_name("New table name", new_name),
         {:ok, statement} <- build_ddl(SQL.rename_table(table, new_name)) do
      Connection.run(source, fn conn -> exec_ddl(conn, statement) end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private — introspection queries
  # ---------------------------------------------------------------------------

  defp fetch_columns(conn, table) do
    sql = """
    SELECT column_name, data_type, udt_name, is_nullable
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = $1
    ORDER BY ordinal_position
    """

    case run_sql(conn, sql, [table]) do
      {:ok, %{rows: []}} ->
        {:error, "Table not found: #{table}"}

      {:ok, %{rows: rows}} ->
        enums = fetch_enums(conn)
        fks = fetch_foreign_keys(conn, table)

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
  defp fetch_foreign_keys(conn, table) do
    sql = """
    SELECT tc.constraint_name, kcu.column_name, ccu.table_name, ccu.column_name
    FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
      ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
    JOIN information_schema.constraint_column_usage ccu
      ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND tc.table_schema = 'public' AND tc.table_name = $1
    """

    case run_sql(conn, sql, [table]) do
      {:ok, %{rows: rows}} ->
        rows
        |> Enum.group_by(fn [constraint, _, _, _] -> constraint end)
        |> Enum.flat_map(fn
          # Single-column FK → 1 cross-product row → safe to expose.
          {_constraint, [[_, col, ftable, fcol]]} -> [{col, %{table: ftable, column: fcol}}]
          # Composite FK (or anything that produced > 1 row) → skip.
          _ -> []
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
  @spec reference_options(source(), String.t(), String.t(), pos_integer()) ::
          {:ok, [{String.t(), String.t()}]} | {:error, term()}
  def reference_options(source, ftable, fcolumn, limit \\ 100) do
    Connection.run(source, fn conn -> do_reference_options(conn, ftable, fcolumn, limit) end)
  end

  defp do_reference_options(conn, ftable, fcolumn, limit) do
    # Clamp the caller-supplied limit so a bad value can't end up in the SQL
    # string. (Identifiers are already quoted via SQL.quote_ident.)
    limit = if is_integer(limit) and limit > 0, do: min(limit, 1000), else: 100

    with {:ok, cols} <- fetch_columns(conn, ftable) do
      names = Enum.map(cols, & &1.name)
      label = Enum.find(~w(name title label display_name email username slug), &(&1 in names))
      label_col = label || fcolumn

      sql =
        "SELECT #{SQL.quote_ident(fcolumn)}, #{SQL.quote_ident(label_col)} " <>
          "FROM #{SQL.quote_ident(ftable)} ORDER BY 2 LIMIT #{limit}"

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
  @spec schema(source(), String.t()) ::
          {:ok, %{columns: [column()], primary_keys: [String.t()], fk_options: map()}}
          | {:error, String.t()}
  def schema(source, table) do
    Connection.run(source, fn conn ->
      with {:ok, cols} <- fetch_columns(conn, table),
           {:ok, pks} <- fetch_primary_keys(conn, table) do
        fk_options =
          for %{name: name, fk: fk} <- cols, fk != nil, into: %{} do
            case do_reference_options(conn, fk.table, fk.column, 100) do
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
  defp fetch_enums(conn) do
    # Scope to the `public` schema so two enums with the same name in
    # different schemas don't merge their labels.
    sql = """
    SELECT t.typname, e.enumlabel
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
    ORDER BY t.typname, e.enumsortorder
    """

    case run_sql(conn, sql, []) do
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

  defp fetch_primary_keys(conn, table) do
    sql = """
    SELECT a.attname
    FROM pg_index i
    JOIN pg_class c ON c.oid = i.indrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE c.relname = $1 AND n.nspname = 'public' AND i.indisprimary
    ORDER BY array_position(i.indkey, a.attnum)
    """

    case run_sql(conn, sql, [table]) do
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

  defp format_error(%Postgrex.Error{postgres: %{message: message}}), do: message
  defp format_error(%Postgrex.Error{message: message}) when is_binary(message), do: message
  defp format_error(reason), do: inspect(reason)
end
