defmodule Lantern.Coercion do
  @moduledoc """
  Pure helpers for moving values between Postgres and the UI.

  Two concerns live here:

    * **`cast_expr/2`** — given a column's `information_schema` `data_type`
      (and `udt_name` for arrays / user-defined types), returns the Postgres
      type expression a text parameter should be cast to on write, or `nil`
      when the column is already textual and needs no cast.

    * **display / edit formatting** — Postgrex returns native Elixir terms
      (`Date`, `Decimal`, `NaiveDateTime`, …). `display/1` renders them for the
      grid; `edit_value/1` renders them for an editable text input.
  """

  # Textual columns accept a bare text parameter without an explicit cast.
  @textual ["text", "character varying", "character", "name", "bpchar", "varchar", "citext"]

  @doc """
  Returns the cast target for a column, or `nil` if no cast is needed.

  ## Examples

      iex> Lantern.Coercion.cast_expr("integer", "int4")
      "integer"

      iex> Lantern.Coercion.cast_expr("text", "text")
      nil

      iex> Lantern.Coercion.cast_expr("ARRAY", "_int4")
      "int4[]"
  """
  @spec cast_expr(String.t(), String.t() | nil) :: String.t() | nil
  def cast_expr(data_type, udt_name \\ nil)

  def cast_expr(data_type, _udt) when data_type in @textual, do: nil

  def cast_expr("ARRAY", udt_name) when is_binary(udt_name) do
    base = String.replace_prefix(udt_name, "_", "")
    "#{base}[]"
  end

  def cast_expr("USER-DEFINED", udt_name) when is_binary(udt_name), do: quote_type(udt_name)

  def cast_expr(data_type, _udt) when is_binary(data_type), do: data_type

  @doc """
  Renders a Postgrex value for read-only display.

  Returns `:null` for `nil` so callers can distinguish SQL NULL from an empty
  string; every other value becomes a `String.t()`.
  """
  @spec display(term()) :: String.t() | :null
  def display(value), do: display(value, nil)

  @doc """
  Like `display/1`, but uses the column's Postgres type to render binaries
  accurately. Pass the `information_schema` `data_type` (e.g. `"uuid"`,
  `"bytea"`) as the second argument; without it, 16-byte binaries are
  optimistically rendered as UUIDs (since a UUID PK is by far the more common
  case to render in a grid).
  """
  @spec display(term(), String.t() | nil) :: String.t() | :null
  def display(nil, _type), do: :null

  # Postgrex returns some column types (notably uuid) as raw binaries rather
  # than printable strings. A non-UTF-8 binary would crash HEEx rendering, so
  # disambiguate by column type when we have it: uuid → uuid string,
  # bytea → hex (with `\\x` prefix for round-trip), otherwise fall back to
  # length-based heuristics.
  def display(value, "uuid") when is_binary(value) and byte_size(value) == 16,
    do: uuid_string(value)

  def display(value, "bytea") when is_binary(value),
    do: "\\x" <> Base.encode16(value, case: :lower)

  def display(value, _type) when is_binary(value) do
    cond do
      String.valid?(value) -> value
      byte_size(value) == 16 -> uuid_string(value)
      true -> Base.encode16(value, case: :lower)
    end
  end

  def display(value, _type) when is_integer(value), do: Integer.to_string(value)
  def display(value, _type) when is_float(value), do: trim_float(value)
  def display(true, _type), do: "true"
  def display(false, _type), do: "false"
  def display(%Date{} = d, _type), do: Date.to_string(d)
  def display(%Time{} = t, _type), do: Time.to_string(t)
  def display(%NaiveDateTime{} = dt, _type), do: NaiveDateTime.to_string(dt)
  def display(%DateTime{} = dt, _type), do: DateTime.to_string(dt)
  def display(%Decimal{} = d, _type), do: Decimal.to_string(d)

  # Arrays (postgres `ARRAY` columns) render as Postgres array literals so the
  # user can edit them and have the text cast back via `::int4[]`/`::text[]`.
  # JSON/JSONB cells (returned as maps/lists) still go through Jason.
  def display(value, "ARRAY") when is_list(value), do: postgres_array_literal(value)

  def display(value, _type) when is_list(value) or is_map(value) do
    case Jason.encode(value) do
      {:ok, json} -> json
      {:error, _} -> inspect(value)
    end
  end

  def display(value, _type), do: inspect(value)

  @doc """
  Renders a value for an editable text input. NULL becomes an empty string.

  Pass the column's Postgres type (e.g. `"uuid"`, `"bytea"`) as the second
  argument so binary values are disambiguated. Without it, 16-byte binaries are
  treated as UUIDs.
  """
  @spec edit_value(term(), String.t() | nil) :: String.t()
  def edit_value(value, type \\ nil)
  def edit_value(nil, _type), do: ""

  def edit_value(value, type) do
    case display(value, type) do
      :null -> ""
      string -> string
    end
  end

  @doc """
  Maps a Postgres `data_type` to the kind of form control to render.

  ## Examples

      iex> Lantern.Coercion.input_type("boolean")
      :boolean

      iex> Lantern.Coercion.input_type("timestamp without time zone")
      :datetime

      iex> Lantern.Coercion.input_type("text")
      :text
  """
  @spec input_type(String.t()) :: atom()
  def input_type("boolean"), do: :boolean
  def input_type(t) when t in ["integer", "bigint", "smallint"], do: :integer
  def input_type(t) when t in ["numeric", "real", "double precision"], do: :decimal
  def input_type("date"), do: :date
  def input_type("time without time zone"), do: :time
  def input_type("time with time zone"), do: :time
  def input_type("timestamp without time zone"), do: :datetime
  def input_type("timestamp with time zone"), do: :datetime
  def input_type(t) when t in ["json", "jsonb"], do: :json
  def input_type(_), do: :text

  @doc """
  Formats a value for a specific HTML control.

  Date/time controls need ISO shapes (`YYYY-MM-DD`, `YYYY-MM-DDTHH:MM:SS`,
  `HH:MM:SS`); everything else falls back to `edit_value/1`.
  """
  @spec control_value(term(), atom()) :: String.t()
  def control_value(nil, _kind), do: ""

  def control_value(value, :date), do: value |> edit_value() |> String.slice(0, 10)

  def control_value(value, :datetime) do
    # Preserve up to milliseconds (browser <input type="datetime-local"> caps
    # at ms precision). Strip a trailing `Z` (Postgrex's DateTime renders one
    # for `timestamptz`) — `datetime-local` rejects time-zone designators.
    value
    |> edit_value()
    |> String.replace(" ", "T")
    |> String.trim_trailing("Z")
    |> String.slice(0, 23)
  end

  def control_value(value, :time), do: value |> edit_value() |> String.slice(0, 12)

  def control_value(value, _kind), do: edit_value(value)

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # Quote a user-defined type name so an enum like `my type` casts correctly.
  defp quote_type(name), do: ~s("#{String.replace(name, ~s("), ~s(""))}")

  defp uuid_string(
         <<a::binary-size(4), b::binary-size(2), c::binary-size(2), d::binary-size(2),
           e::binary-size(6)>>
       ) do
    [a, b, c, d, e]
    |> Enum.map_join("-", &Base.encode16(&1, case: :lower))
  end

  defp trim_float(value) do
    :erlang.float_to_binary(value, decimals: 10)
    |> String.trim_trailing("0")
    |> String.trim_trailing(".")
  end

  # Minimal Postgres array literal: `{a,"with comma","quote\""}`. Handles flat
  # arrays of strings/numbers/bool/nil. Nested arrays are inspected (a known
  # limitation flagged in the README's "data types" section).
  defp postgres_array_literal(list) when is_list(list) do
    "{" <> Enum.map_join(list, ",", &array_elem/1) <> "}"
  end

  defp array_elem(nil), do: "NULL"
  defp array_elem(true), do: "t"
  defp array_elem(false), do: "f"
  defp array_elem(n) when is_integer(n), do: Integer.to_string(n)
  defp array_elem(n) when is_float(n), do: trim_float(n)

  defp array_elem(s) when is_binary(s) do
    if String.valid?(s) do
      ~s("#{String.replace(s, ["\\", "\""], &"\\#{&1}")}")
    else
      ~s("#{Base.encode16(s, case: :lower)}")
    end
  end

  defp array_elem(other), do: ~s("#{String.replace(inspect(other), ~s("), "\\\"")}")
end
