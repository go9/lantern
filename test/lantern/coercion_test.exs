defmodule Lantern.CoercionTest do
  use ExUnit.Case, async: true

  alias Lantern.Coercion

  doctest Coercion

  describe "cast_expr/2" do
    test "textual types need no cast" do
      textual = ["text", "character varying", "character", "name", "bpchar", "varchar", "citext"]

      for type <- textual do
        assert Coercion.cast_expr(type, nil) == nil
      end
    end

    test "scalar types cast to their data_type" do
      assert Coercion.cast_expr("integer", "int4") == "integer"
      assert Coercion.cast_expr("boolean", "bool") == "boolean"
      assert Coercion.cast_expr("jsonb", "jsonb") == "jsonb"
      assert Coercion.cast_expr("numeric", "numeric") == "numeric"

      assert Coercion.cast_expr("timestamp without time zone", "timestamp") ==
               "timestamp without time zone"

      assert Coercion.cast_expr("uuid", "uuid") == "uuid"
    end

    test "arrays cast via udt_name" do
      assert Coercion.cast_expr("ARRAY", "_int4") == "int4[]"
      assert Coercion.cast_expr("ARRAY", "_text") == "text[]"
    end

    test "user-defined types cast to the quoted udt name" do
      assert Coercion.cast_expr("USER-DEFINED", "mood") == ~s("mood")
    end
  end

  describe "display/1" do
    test "nil becomes :null" do
      assert Coercion.display(nil) == :null
    end

    test "passes strings through" do
      assert Coercion.display("hello") == "hello"
    end

    test "formats integers and booleans" do
      assert Coercion.display(42) == "42"
      assert Coercion.display(true) == "true"
      assert Coercion.display(false) == "false"
    end

    test "trims trailing zeros from floats" do
      assert Coercion.display(1.5) == "1.5"
      assert Coercion.display(2.0) == "2"
    end

    test "formats temporal and decimal types" do
      assert Coercion.display(~D[2026-05-26]) == "2026-05-26"
      assert Coercion.display(~T[09:30:00]) == "09:30:00"
      assert Coercion.display(~N[2026-05-26 09:30:00]) == "2026-05-26 09:30:00"
      assert Coercion.display(Decimal.new("3.14")) == "3.14"
    end

    test "encodes maps and lists as JSON" do
      assert Coercion.display(%{"a" => 1}) == ~s({"a":1})
      assert Coercion.display([1, 2, 3]) == "[1,2,3]"
    end

    test "formats a raw 16-byte uuid binary as a uuid string" do
      bin = Base.decode16!("550E8400E29B41D4A716446655440000")
      refute String.valid?(bin)
      assert Coercion.display(bin) == "550e8400-e29b-41d4-a716-446655440000"
    end

    test "falls back to hex for other non-utf8 binaries" do
      assert Coercion.display(<<0, 255, 16>>) == "00ff10"
    end

    test "with column type, disambiguates uuid from bytea" do
      bin = Base.decode16!("550E8400E29B41D4A716446655440000")
      assert Coercion.display(bin, "uuid") == "550e8400-e29b-41d4-a716-446655440000"
      assert Coercion.display(bin, "bytea") == "\\x550e8400e29b41d4a716446655440000"
    end
  end

  describe "edit_value/1" do
    test "nil becomes an empty string" do
      assert Coercion.edit_value(nil) == ""
    end

    test "renders other values like display/1" do
      assert Coercion.edit_value(42) == "42"
      assert Coercion.edit_value(~D[2026-05-26]) == "2026-05-26"
    end

    test "with a column type, formats binaries accurately" do
      bin = Base.decode16!("550E8400E29B41D4A716446655440000")
      assert Coercion.edit_value(bin, "uuid") == "550e8400-e29b-41d4-a716-446655440000"
      assert Coercion.edit_value(bin, "bytea") == "\\x550e8400e29b41d4a716446655440000"
    end
  end

  describe "input_type/1" do
    test "maps Postgres types to control kinds" do
      assert Coercion.input_type("boolean") == :boolean
      assert Coercion.input_type("integer") == :integer
      assert Coercion.input_type("bigint") == :integer
      assert Coercion.input_type("numeric") == :decimal
      assert Coercion.input_type("double precision") == :decimal
      assert Coercion.input_type("date") == :date
      assert Coercion.input_type("time without time zone") == :time
      assert Coercion.input_type("timestamp without time zone") == :datetime
      assert Coercion.input_type("timestamp with time zone") == :datetime
      assert Coercion.input_type("jsonb") == :json
      assert Coercion.input_type("text") == :text
      assert Coercion.input_type("uuid") == :text
    end
  end

  describe "control_value/2" do
    test "nil is always blank" do
      assert Coercion.control_value(nil, :datetime) == ""
    end

    test "date keeps only the calendar date" do
      assert Coercion.control_value(~D[2026-05-26], :date) == "2026-05-26"
    end

    test "datetime preserves milliseconds for round-tripping" do
      assert Coercion.control_value(~N[2026-05-26 09:30:00.123456], :datetime) ==
               "2026-05-26T09:30:00.123"
    end

    test "datetime strips the trailing Z that timestamptz produces" do
      dt = DateTime.from_naive!(~N[2026-05-26 09:30:00.123456], "Etc/UTC")
      assert Coercion.control_value(dt, :datetime) == "2026-05-26T09:30:00.123"
    end

    test "time preserves milliseconds when present" do
      assert Coercion.control_value(~T[09:30:00.123456], :time) == "09:30:00.123"
      assert Coercion.control_value(~T[09:30:00], :time) == "09:30:00"
    end

    test "other kinds fall back to edit_value" do
      assert Coercion.control_value(42, :integer) == "42"
    end
  end
end
