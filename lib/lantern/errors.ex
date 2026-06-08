defmodule Lantern.Errors do
  @moduledoc """
  Turns raw database and query errors into honest, human-readable copy for the
  UI. The cardinal rule: **never leak a raw struct** (a `%DBConnection.ConnectionError{}`
  or `%Postgrex.Error{}` dumped via `inspect/1`) into the interface.

  `humanize/1` is the single chokepoint every error-rendering path routes
  through — table loads, the SQL workspace, row edits, and connection setup.

  For Postgres query errors it surfaces Postgres's own message and, when it can,
  appends a short plain-language hint (the server's own `HINT:` if present, else
  one derived from the SQLSTATE code).
  """

  # Shown whenever the database can't be reached: pool checkout timed out, the
  # backend is asleep/starting, the socket dropped, DNS/connect failed, etc.
  @connection_copy "Couldn't connect to this database. It may be starting up or unreachable; try again in a moment."

  # Bare reasons that all mean "the connection isn't usable right now".
  @connection_reasons [
    :queue_timeout,
    :timeout,
    :closed,
    :killed,
    :disconnected,
    :econnrefused,
    :nxdomain,
    :ehostunreach,
    :etimedout
  ]

  @doc """
  The friendly connection-failure message. Exposed so callers that already know
  the failure is a connection problem (e.g. opening the socket) can use it
  directly without constructing an error term.
  """
  @spec connection_error() :: String.t()
  def connection_error, do: @connection_copy

  @doc """
  Converts an error term into display copy. Always returns a string; never an
  `inspect/1` of a struct.
  """
  @spec humanize(term()) :: String.t()
  def humanize(error)

  # Already human (e.g. a message a lower layer formatted).
  def humanize(message) when is_binary(message), do: message

  # Connection failures — DB unreachable, pool exhausted/timed out, socket gone.
  def humanize(%DBConnection.ConnectionError{}), do: @connection_copy
  def humanize(reason) when reason in @connection_reasons, do: @connection_copy
  def humanize({:shutdown, _}), do: @connection_copy

  # Postgres query/DDL errors — clean message, plus a hint when we have one.
  def humanize(%Postgrex.Error{postgres: pg}) when is_map(pg) do
    base = Map.get(pg, :message) || "Database error."

    case hint(pg) do
      nil -> base
      hint -> base <> "\n\n" <> hint
    end
  end

  def humanize(%Postgrex.Error{message: message}) when is_binary(message), do: message

  # Any other exception struct: its own message, never the raw struct.
  def humanize(error) when is_exception(error), do: Exception.message(error)

  # Last resort for unknown non-struct reasons (atoms, small tuples). These are
  # short and safe to show; structs are handled by the clauses above.
  def humanize(reason), do: inspect(reason)

  # --- Hints -----------------------------------------------------------------

  # Prefer Postgres's own HINT when it sent one; otherwise map the SQLSTATE.
  defp hint(pg) do
    case Map.get(pg, :hint) do
      hint when is_binary(hint) and hint != "" -> "Hint: " <> hint
      _ -> code_hint(Map.get(pg, :code))
    end
  end

  defp code_hint(:undefined_table),
    do:
      "Hint: that table doesn't exist. Check the name, and qualify it as schema.table if it isn't in public."

  defp code_hint(:undefined_column),
    do: "Hint: that column doesn't exist. Browse the table to see its columns."

  defp code_hint(:syntax_error),
    do:
      "Hint: SQL syntax error. Check for a missing comma, quote, or keyword near the reported position."

  defp code_hint(:insufficient_privilege),
    do:
      "Hint: the connected role isn't allowed to do this; a role with more privileges may be required."

  defp code_hint(:unique_violation),
    do: "Hint: a row with that value already exists (unique constraint)."

  defp code_hint(:foreign_key_violation),
    do:
      "Hint: this references a row that doesn't exist, or is still referenced elsewhere (foreign key)."

  defp code_hint(:not_null_violation),
    do: "Hint: a required (NOT NULL) column was left empty."

  defp code_hint(:check_violation), do: "Hint: a value failed a CHECK constraint."

  defp code_hint(_), do: nil
end
