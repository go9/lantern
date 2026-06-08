defmodule Lantern.SQL do
  @moduledoc """
  Pure SQL string builders.

  Every builder returns `{sql, params}` where `params` is the ordered list of
  values bound to `$1..$n`. Nothing in this module touches the database, which
  keeps the SQL surface exhaustively unit-testable.

  ## Field descriptors

  Write builders take *field descriptors* — maps of the shape:

      %{column: "age", value: "42", cast: "integer"}

  `:value` is the raw parameter sent to Postgrex (a string, or `nil` for SQL
  NULL). `:cast` is an optional Postgres type expression; when present the
  placeholder becomes `$n::text::<cast>` so Postgrex sends the string verbatim
  and Postgres parses it into the column's type. When `:cast` is `nil` the
  placeholder is bare (textual columns infer a text parameter naturally).
  """

  @type field :: %{column: String.t(), value: term(), cast: String.t() | nil}

  @typedoc """
  A column spec for DDL builders. `:name` and `:type` are required; `:nullable`
  defaults to `true` and `:primary_key` to `false`.
  """
  @type column :: %{
          required(:name) => String.t(),
          required(:type) => String.t(),
          optional(:nullable) => boolean(),
          optional(:primary_key) => boolean()
        }

  # Column types accepted verbatim (no length/precision argument). DDL cannot
  # bind types as parameters, so this allowlist is the injection boundary for
  # the type portion of a column definition — identifiers are handled by
  # `quote_ident/1`.
  @simple_types MapSet.new([
                  "smallint",
                  "integer",
                  "bigint",
                  "smallserial",
                  "serial",
                  "bigserial",
                  "int2",
                  "int4",
                  "int8",
                  "serial2",
                  "serial4",
                  "serial8",
                  "real",
                  "double precision",
                  "float4",
                  "float8",
                  "numeric",
                  "decimal",
                  "money",
                  "boolean",
                  "bool",
                  "text",
                  "varchar",
                  "character varying",
                  "char",
                  "character",
                  "uuid",
                  "json",
                  "jsonb",
                  "bytea",
                  "date",
                  "time",
                  "timetz",
                  "timestamp",
                  "timestamptz",
                  "time with time zone",
                  "time without time zone",
                  "timestamp with time zone",
                  "timestamp without time zone",
                  "interval",
                  "bit",
                  "bit varying",
                  "varbit",
                  "inet",
                  "cidr",
                  "macaddr",
                  "macaddr8",
                  "xml"
                ])

  # Base types that may carry a `(n)` or `(n,m)` length/precision argument.
  @parameterized_types MapSet.new([
                         "varchar",
                         "character varying",
                         "char",
                         "character",
                         "numeric",
                         "decimal",
                         "bit",
                         "bit varying",
                         "varbit",
                         "time",
                         "timetz",
                         "timestamp",
                         "timestamptz",
                         "interval"
                       ])

  @doc "Quotes a Postgres identifier, escaping embedded double-quotes."
  @spec quote_ident(String.t()) :: String.t()
  def quote_ident(name) when is_binary(name) do
    ~s("#{String.replace(name, ~s("), ~s(""))}")
  end

  @doc "Quotes a schema-qualified table identifier."
  @spec quote_table(String.t(), String.t()) :: String.t()
  def quote_table(schema, table) when is_binary(schema) and is_binary(table) do
    quote_ident(schema) <> "." <> quote_ident(table)
  end

  @doc """
  Builds a paginated `SELECT *`.

  `where_clause` is a raw fragment (without `WHERE`) or `nil`. `sort_col` is a
  validated column name or `nil`. `sort_dir` is `:asc` or `:desc`.
  """
  @spec select(
          String.t(),
          String.t() | nil,
          String.t() | nil,
          :asc | :desc,
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {String.t(), []}
  def select(table, where_clause, sort_col, sort_dir, limit, offset) do
    sql =
      "SELECT * FROM #{quote_ident(table)}"
      |> maybe_where(where_clause)
      |> maybe_order(sort_col, sort_dir)
      |> Kernel.<>(" LIMIT #{to_int(limit)} OFFSET #{to_int(offset)}")

    {sql, []}
  end

  @spec select(
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          :asc | :desc,
          non_neg_integer(),
          non_neg_integer()
        ) :: {String.t(), []}
  def select(schema, table, where_clause, sort_col, sort_dir, limit, offset) do
    sql =
      "SELECT * FROM #{quote_table(schema, table)}"
      |> maybe_where(where_clause)
      |> maybe_order(sort_col, sort_dir)
      |> Kernel.<>(" LIMIT #{to_int(limit)} OFFSET #{to_int(offset)}")

    {sql, []}
  end

  @doc "Builds a `SELECT COUNT(*)` honoring the same optional WHERE fragment."
  @spec count(String.t(), String.t() | nil) :: {String.t(), []}
  def count(table, where_clause) do
    sql = maybe_where("SELECT COUNT(*) FROM #{quote_ident(table)}", where_clause)
    {sql, []}
  end

  @spec count(String.t(), String.t(), String.t() | nil) :: {String.t(), []}
  def count(schema, table, where_clause) do
    sql = maybe_where("SELECT COUNT(*) FROM #{quote_table(schema, table)}", where_clause)
    {sql, []}
  end

  @doc """
  Builds an `INSERT ... RETURNING *`.

  An empty field list emits `INSERT INTO t DEFAULT VALUES RETURNING *`, so a
  blank submission against a table whose columns all have defaults still works.
  """
  @spec insert(String.t(), [field()]) :: {:ok, {String.t(), [term()]}}
  def insert(table, []),
    do: {:ok, {"INSERT INTO #{quote_ident(table)} DEFAULT VALUES RETURNING *", []}}

  def insert(table, fields) when is_list(fields) do
    columns = Enum.map_join(fields, ", ", &quote_ident(&1.column))

    {placeholders, params} =
      fields
      |> Enum.with_index(1)
      |> Enum.map(fn {field, idx} -> {placeholder(field, idx), field.value} end)
      |> Enum.unzip()

    sql =
      "INSERT INTO #{quote_ident(table)} (#{columns}) " <>
        "VALUES (#{Enum.join(placeholders, ", ")}) RETURNING *"

    {:ok, {sql, params}}
  end

  @spec insert(String.t(), String.t(), [field()]) :: {:ok, {String.t(), [term()]}}
  def insert(schema, table, []),
    do: {:ok, {"INSERT INTO #{quote_table(schema, table)} DEFAULT VALUES RETURNING *", []}}

  def insert(schema, table, fields) when is_list(fields) do
    columns = Enum.map_join(fields, ", ", &quote_ident(&1.column))

    {placeholders, params} =
      fields
      |> Enum.with_index(1)
      |> Enum.map(fn {field, idx} -> {placeholder(field, idx), field.value} end)
      |> Enum.unzip()

    sql =
      "INSERT INTO #{quote_table(schema, table)} (#{columns}) " <>
        "VALUES (#{Enum.join(placeholders, ", ")}) RETURNING *"

    {:ok, {sql, params}}
  end

  @doc """
  Builds an `UPDATE ... WHERE <pk match> RETURNING *`.

  `fields` are the columns to set; `pk_fields` identify the single row. Both are
  field descriptors. Returns `{:error, :no_fields}` or `{:error, :no_key}`.
  """
  @spec update(String.t(), [field()], [field()]) ::
          {:ok, {String.t(), [term()]}} | {:error, :no_fields | :no_key}
  def update(_table, [], _pk_fields), do: {:error, :no_fields}
  def update(_table, _fields, []), do: {:error, :no_key}

  def update(table, fields, pk_fields) when is_list(fields) and is_list(pk_fields) do
    {set_parts, set_params, next} = assignments(fields, 1)
    {where_sql, where_params, _} = pk_where(pk_fields, next)

    sql =
      "UPDATE #{quote_ident(table)} SET #{Enum.join(set_parts, ", ")} " <>
        "WHERE #{where_sql} RETURNING *"

    {:ok, {sql, set_params ++ where_params}}
  end

  @spec update(String.t(), String.t(), [field()], [field()]) ::
          {:ok, {String.t(), [term()]}} | {:error, :no_fields | :no_key}
  def update(_schema, _table, [], _pk_fields), do: {:error, :no_fields}
  def update(_schema, _table, _fields, []), do: {:error, :no_key}

  def update(schema, table, fields, pk_fields) when is_list(fields) and is_list(pk_fields) do
    {set_parts, set_params, next} = assignments(fields, 1)
    {where_sql, where_params, _} = pk_where(pk_fields, next)

    sql =
      "UPDATE #{quote_table(schema, table)} SET #{Enum.join(set_parts, ", ")} " <>
        "WHERE #{where_sql} RETURNING *"

    {:ok, {sql, set_params ++ where_params}}
  end

  @doc """
  Builds a `DELETE` for one or more rows, each identified by its PK fields.

  `rows` is a list of pk-field lists. Rows are matched with OR'd, parenthesized
  AND groups. Returns `{:error, :no_rows}` or `{:error, :no_key}`.
  """
  @spec delete(String.t(), [[field()]]) ::
          {:ok, {String.t(), [term()]}} | {:error, :no_rows | :no_key}
  def delete(_table, []), do: {:error, :no_rows}

  def delete(table, rows) when is_list(rows) do
    if Enum.any?(rows, &(&1 == [])) do
      {:error, :no_key}
    else
      {groups, params, _} =
        Enum.reduce(rows, {[], [], 1}, fn pk_fields, {groups, params, idx} ->
          {where_sql, row_params, next} = pk_where(pk_fields, idx)
          {groups ++ ["(#{where_sql})"], params ++ row_params, next}
        end)

      sql = "DELETE FROM #{quote_ident(table)} WHERE #{Enum.join(groups, " OR ")}"
      {:ok, {sql, params}}
    end
  end

  @spec delete(String.t(), String.t(), [[field()]]) ::
          {:ok, {String.t(), [term()]}} | {:error, :no_rows | :no_key}
  def delete(_schema, _table, []), do: {:error, :no_rows}

  def delete(schema, table, rows) when is_list(rows) do
    if Enum.any?(rows, &(&1 == [])) do
      {:error, :no_key}
    else
      {groups, params, _} =
        Enum.reduce(rows, {[], [], 1}, fn pk_fields, {groups, params, idx} ->
          {where_sql, row_params, next} = pk_where(pk_fields, idx)
          {groups ++ ["(#{where_sql})"], params ++ row_params, next}
        end)

      sql = "DELETE FROM #{quote_table(schema, table)} WHERE #{Enum.join(groups, " OR ")}"
      {:ok, {sql, params}}
    end
  end

  # ---------------------------------------------------------------------------
  # DDL builders
  # ---------------------------------------------------------------------------

  @doc """
  Builds a `CREATE TABLE`.

  `columns` is a list of column specs (see `t:column/0`). Columns flagged
  `primary_key: true` are collected into a single `PRIMARY KEY (...)` table
  constraint, so composite keys work. Identifiers are quoted and every type is
  validated against the allowlist.

  Returns `{:error, :no_columns}` when `columns` is empty,
  `{:error, :missing_name}` when a spec lacks a usable name, or
  `{:error, {:invalid_type, type}}` for a disallowed type.
  """
  @spec create_table(String.t(), [column()]) ::
          {:ok, {String.t(), []}}
          | {:error, :no_columns | :missing_name | {:invalid_type, String.t()}}
  def create_table(_table, []), do: {:error, :no_columns}

  def create_table(table, columns) when is_binary(table) and is_list(columns) do
    with {:ok, defs} <- column_definitions(columns) do
      pk_cols =
        columns
        |> Enum.filter(&Map.get(&1, :primary_key, false))
        |> Enum.map(&quote_ident(&1.name))

      constraint = if pk_cols == [], do: [], else: ["PRIMARY KEY (#{Enum.join(pk_cols, ", ")})"]
      body = Enum.join(defs ++ constraint, ", ")
      {:ok, {"CREATE TABLE #{quote_ident(table)} (#{body})", []}}
    end
  end

  @spec create_table(String.t(), String.t(), [column()]) ::
          {:ok, {String.t(), []}}
          | {:error, :no_columns | :missing_name | {:invalid_type, String.t()}}
  def create_table(_schema, _table, []), do: {:error, :no_columns}

  def create_table(schema, table, columns)
      when is_binary(schema) and is_binary(table) and is_list(columns) do
    with {:ok, defs} <- column_definitions(columns) do
      pk_cols =
        columns
        |> Enum.filter(&Map.get(&1, :primary_key, false))
        |> Enum.map(&quote_ident(&1.name))

      constraint = if pk_cols == [], do: [], else: ["PRIMARY KEY (#{Enum.join(pk_cols, ", ")})"]
      body = Enum.join(defs ++ constraint, ", ")
      {:ok, {"CREATE TABLE #{quote_table(schema, table)} (#{body})", []}}
    end
  end

  @doc "Builds a `DROP TABLE`. No `CASCADE` — a table with dependents errors loudly."
  @spec drop_table(String.t()) :: {:ok, {String.t(), []}}
  def drop_table(table) when is_binary(table) do
    {:ok, {"DROP TABLE #{quote_ident(table)}", []}}
  end

  @spec drop_table(String.t(), String.t()) :: {:ok, {String.t(), []}}
  def drop_table(schema, table) when is_binary(schema) and is_binary(table) do
    {:ok, {"DROP TABLE #{quote_table(schema, table)}", []}}
  end

  @doc """
  Builds an `ALTER TABLE ... ADD COLUMN`.

  `column` is a single column spec (see `t:column/0`). Returns the same
  validation errors as `create_table/2`.
  """
  @spec add_column(String.t(), column()) ::
          {:ok, {String.t(), []}} | {:error, :missing_name | {:invalid_type, String.t()}}
  def add_column(table, column) when is_binary(table) and is_map(column) do
    with {:ok, definition} <- column_definition(column) do
      {:ok, {"ALTER TABLE #{quote_ident(table)} ADD COLUMN #{definition}", []}}
    end
  end

  @spec add_column(String.t(), String.t(), column()) ::
          {:ok, {String.t(), []}} | {:error, :missing_name | {:invalid_type, String.t()}}
  def add_column(schema, table, column)
      when is_binary(schema) and is_binary(table) and is_map(column) do
    with {:ok, definition} <- column_definition(column) do
      {:ok, {"ALTER TABLE #{quote_table(schema, table)} ADD COLUMN #{definition}", []}}
    end
  end

  @doc "Builds an `ALTER TABLE ... DROP COLUMN`."
  @spec drop_column(String.t(), String.t()) :: {:ok, {String.t(), []}}
  def drop_column(table, column) when is_binary(table) and is_binary(column) do
    {:ok, {"ALTER TABLE #{quote_ident(table)} DROP COLUMN #{quote_ident(column)}", []}}
  end

  @spec drop_column(String.t(), String.t(), String.t()) :: {:ok, {String.t(), []}}
  def drop_column(schema, table, column)
      when is_binary(schema) and is_binary(table) and is_binary(column) do
    {:ok, {"ALTER TABLE #{quote_table(schema, table)} DROP COLUMN #{quote_ident(column)}", []}}
  end

  @doc "Builds an `ALTER TABLE ... ALTER COLUMN ... TYPE ...`."
  @spec alter_column_type(String.t(), String.t(), String.t()) ::
          {:ok, {String.t(), []}} | {:error, {:invalid_type, String.t()}}
  def alter_column_type(table, column, type)
      when is_binary(table) and is_binary(column) and is_binary(type) do
    case validate_type(type) do
      {:ok, normalized} ->
        {:ok,
         {"ALTER TABLE #{quote_ident(table)} ALTER COLUMN #{quote_ident(column)} TYPE #{normalized}",
          []}}

      :error ->
        {:error, {:invalid_type, type}}
    end
  end

  @spec alter_column_type(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, {String.t(), []}} | {:error, {:invalid_type, String.t()}}
  def alter_column_type(schema, table, column, type)
      when is_binary(schema) and is_binary(table) and is_binary(column) and is_binary(type) do
    case validate_type(type) do
      {:ok, normalized} ->
        {:ok,
         {"ALTER TABLE #{quote_table(schema, table)} ALTER COLUMN #{quote_ident(column)} TYPE #{normalized}",
          []}}

      :error ->
        {:error, {:invalid_type, type}}
    end
  end

  @doc "Builds an `ALTER TABLE ... ALTER COLUMN ... SET/DROP NOT NULL`."
  @spec set_column_nullable(String.t(), String.t(), boolean()) :: {:ok, {String.t(), []}}
  def set_column_nullable(table, column, nullable)
      when is_binary(table) and is_binary(column) and is_boolean(nullable) do
    action = if nullable, do: "DROP NOT NULL", else: "SET NOT NULL"
    {:ok, {"ALTER TABLE #{quote_ident(table)} ALTER COLUMN #{quote_ident(column)} #{action}", []}}
  end

  @spec set_column_nullable(String.t(), String.t(), String.t(), boolean()) ::
          {:ok, {String.t(), []}}
  def set_column_nullable(schema, table, column, nullable)
      when is_binary(schema) and is_binary(table) and is_binary(column) and is_boolean(nullable) do
    action = if nullable, do: "DROP NOT NULL", else: "SET NOT NULL"

    {:ok,
     {"ALTER TABLE #{quote_table(schema, table)} ALTER COLUMN #{quote_ident(column)} #{action}",
      []}}
  end

  @doc "Builds an `ALTER TABLE ... RENAME COLUMN`."
  @spec rename_column(String.t(), String.t(), String.t()) :: {:ok, {String.t(), []}}
  def rename_column(table, from, to)
      when is_binary(table) and is_binary(from) and is_binary(to) do
    sql =
      "ALTER TABLE #{quote_ident(table)} " <>
        "RENAME COLUMN #{quote_ident(from)} TO #{quote_ident(to)}"

    {:ok, {sql, []}}
  end

  @spec rename_column(String.t(), String.t(), String.t(), String.t()) :: {:ok, {String.t(), []}}
  def rename_column(schema, table, from, to)
      when is_binary(schema) and is_binary(table) and is_binary(from) and is_binary(to) do
    sql =
      "ALTER TABLE #{quote_table(schema, table)} " <>
        "RENAME COLUMN #{quote_ident(from)} TO #{quote_ident(to)}"

    {:ok, {sql, []}}
  end

  @doc "Builds an `ALTER TABLE ... DROP CONSTRAINT` statement."
  @spec drop_constraint(String.t(), String.t()) ::
          {:ok, {String.t(), []}} | {:error, :missing_name}
  def drop_constraint(table, constraint_name)
      when is_binary(table) and is_binary(constraint_name) do
    drop_constraint_sql(nil, table, constraint_name)
  end

  @spec drop_constraint(String.t(), String.t(), String.t()) ::
          {:ok, {String.t(), []}} | {:error, :missing_name}
  def drop_constraint(schema, table, constraint_name)
      when is_binary(schema) and is_binary(table) and is_binary(constraint_name) do
    drop_constraint_sql(schema, table, constraint_name)
  end

  @doc "Builds a `CREATE INDEX` statement."
  @spec create_index(String.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, {String.t(), []}} | {:error, :missing_name | :no_columns}
  def create_index(table, index_name, columns)
      when is_binary(table) and is_binary(index_name) and is_list(columns) do
    create_index_sql(nil, table, index_name, columns)
  end

  @spec create_index(String.t(), String.t(), String.t(), [String.t()]) ::
          {:ok, {String.t(), []}} | {:error, :missing_name | :no_columns}
  def create_index(schema, table, index_name, columns)
      when is_binary(schema) and is_binary(table) and is_binary(index_name) and is_list(columns) do
    create_index_sql(schema, table, index_name, columns)
  end

  @doc "Builds a `DROP INDEX` statement."
  @spec drop_index(String.t()) :: {:ok, {String.t(), []}} | {:error, :missing_name}
  def drop_index(index_name) when is_binary(index_name) do
    if String.trim(index_name) == "" do
      {:error, :missing_name}
    else
      {:ok, {"DROP INDEX #{quote_ident(index_name)}", []}}
    end
  end

  @spec drop_index(String.t(), String.t()) :: {:ok, {String.t(), []}} | {:error, :missing_name}
  def drop_index(schema, index_name) when is_binary(schema) and is_binary(index_name) do
    if String.trim(index_name) == "" do
      {:error, :missing_name}
    else
      {:ok, {"DROP INDEX #{quote_table(schema, index_name)}", []}}
    end
  end

  @doc "Builds an `ALTER TABLE ... RENAME TO`."
  @spec rename_table(String.t(), String.t()) :: {:ok, {String.t(), []}}
  def rename_table(table, new_name) when is_binary(table) and is_binary(new_name) do
    {:ok, {"ALTER TABLE #{quote_ident(table)} RENAME TO #{quote_ident(new_name)}", []}}
  end

  @spec rename_table(String.t(), String.t(), String.t()) :: {:ok, {String.t(), []}}
  def rename_table(schema, table, new_name)
      when is_binary(schema) and is_binary(table) and is_binary(new_name) do
    {:ok, {"ALTER TABLE #{quote_table(schema, table)} RENAME TO #{quote_ident(new_name)}", []}}
  end

  @doc """
  Validates a column type against the allowlist, returning the normalized
  (trimmed, downcased, single-spaced) form or `:error`.

  Accepts bare types (`"bigint"`, `"text"`) and parameterized forms
  (`"varchar(255)"`, `"numeric(10,2)"`) whose base type is allowlisted.
  """
  @spec validate_type(String.t()) :: {:ok, String.t()} | :error
  def validate_type(type) when is_binary(type) do
    normalized = type |> String.trim() |> String.downcase() |> collapse_spaces()

    cond do
      MapSet.member?(@simple_types, normalized) -> {:ok, normalized}
      parameterized_type?(normalized) -> {:ok, normalized}
      true -> :error
    end
  end

  def validate_type(_), do: :error

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp assignments(fields, start_idx) do
    fields
    |> Enum.with_index(start_idx)
    |> Enum.reduce({[], [], start_idx}, fn {field, idx}, {parts, params, _} ->
      part = "#{quote_ident(field.column)} = #{placeholder(field, idx)}"
      {parts ++ [part], params ++ [field.value], idx + 1}
    end)
  end

  defp pk_where(pk_fields, start_idx) do
    pk_fields
    |> Enum.with_index(start_idx)
    |> Enum.reduce({[], [], start_idx}, fn {field, idx}, {parts, params, _} ->
      part = "#{quote_ident(field.column)} = #{placeholder(field, idx)}"
      {parts ++ [part], params ++ [field.value], idx + 1}
    end)
    |> then(fn {parts, params, _} ->
      {Enum.join(parts, " AND "), params, start_idx + length(pk_fields)}
    end)
  end

  # A bare placeholder lets Postgres infer a text parameter for textual columns.
  # For everything else we pin the parameter to text first (`$n::text`) so
  # Postgrex sends the string as-is, then let Postgres parse it into the column
  # type (`::<cast>`). Casting straight to the target would make Postgrex infer
  # the parameter as that type and reject the string.
  defp placeholder(%{cast: nil}, idx), do: "$#{idx}"
  defp placeholder(%{cast: cast}, idx) when is_binary(cast), do: "$#{idx}::text::#{cast}"
  defp placeholder(_field, idx), do: "$#{idx}"

  defp drop_constraint_sql(schema, table, constraint_name) do
    if String.trim(constraint_name) == "" do
      {:error, :missing_name}
    else
      table_sql = if schema, do: quote_table(schema, table), else: quote_ident(table)
      {:ok, {"ALTER TABLE #{table_sql} DROP CONSTRAINT #{quote_ident(constraint_name)}", []}}
    end
  end

  defp create_index_sql(schema, table, index_name, columns) do
    cols =
      columns |> Enum.map(&to_string/1) |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

    cond do
      String.trim(index_name) == "" ->
        {:error, :missing_name}

      cols == [] ->
        {:error, :no_columns}

      true ->
        table_sql = if schema, do: quote_table(schema, table), else: quote_ident(table)
        columns_sql = Enum.map_join(cols, ", ", &quote_ident/1)
        {:ok, {"CREATE INDEX #{quote_ident(index_name)} ON #{table_sql} (#{columns_sql})", []}}
    end
  end

  defp column_definitions(columns) do
    Enum.reduce_while(columns, {:ok, []}, fn column, {:ok, acc} ->
      case column_definition(column) do
        {:ok, definition} -> {:cont, {:ok, acc ++ [definition]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp column_definition(%{name: name, type: type} = column)
       when is_binary(name) and is_binary(type) do
    cond do
      String.trim(name) == "" ->
        {:error, :missing_name}

      true ->
        case validate_type(type) do
          {:ok, normalized} ->
            null_clause = if Map.get(column, :nullable, true), do: "", else: " NOT NULL"
            {:ok, "#{quote_ident(name)} #{normalized}#{null_clause}"}

          :error ->
            {:error, {:invalid_type, type}}
        end
    end
  end

  defp column_definition(_), do: {:error, :missing_name}

  defp parameterized_type?(type) do
    case Regex.run(~r/^([a-z ]+)\(\d+(?:,\s*\d+)?\)$/, type) do
      [_, base] -> MapSet.member?(@parameterized_types, String.trim(base))
      _ -> false
    end
  end

  defp collapse_spaces(str), do: String.replace(str, ~r/\s+/, " ")

  defp maybe_where(sql, clause) do
    if present?(clause), do: sql <> " WHERE #{clause}", else: sql
  end

  defp maybe_order(sql, nil, _dir), do: sql

  defp maybe_order(sql, col, dir) do
    direction = if dir == :desc, do: "DESC", else: "ASC"
    sql <> " ORDER BY #{quote_ident(col)} #{direction}"
  end

  defp present?(nil), do: false
  defp present?(str) when is_binary(str), do: String.trim(str) != ""
  defp present?(_), do: false

  defp to_int(n) when is_integer(n) and n >= 0, do: n
  defp to_int(_), do: 0
end
