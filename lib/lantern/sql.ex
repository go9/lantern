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

  @doc "Quotes a Postgres identifier, escaping embedded double-quotes."
  @spec quote_ident(String.t()) :: String.t()
  def quote_ident(name) when is_binary(name) do
    ~s("#{String.replace(name, ~s("), ~s(""))}")
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

  @doc "Builds a `SELECT COUNT(*)` honoring the same optional WHERE fragment."
  @spec count(String.t(), String.t() | nil) :: {String.t(), []}
  def count(table, where_clause) do
    sql = maybe_where("SELECT COUNT(*) FROM #{quote_ident(table)}", where_clause)
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
