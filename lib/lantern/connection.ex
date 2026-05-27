defmodule Lantern.Connection do
  @moduledoc """
  Opens one-shot Postgrex connections from a `Lantern.Source`.

  Lantern deliberately avoids a long-lived pool: an embeddable `live_component`
  has no reliable teardown hook, so each operation opens a connection, runs, and
  closes it. The per-call cost is irrelevant for an administrative tool and it
  leaves nothing for host applications to supervise.
  """

  alias Lantern.Source

  @doc """
  Resolves `source_input` to a `Source`, opens a connection, and runs `fun`.

  `fun` receives the Postgrex connection pid and its result is returned as-is.
  Connection/resolution failures return `{:error, reason}`.
  """
  @spec run(Source.t() | String.t() | keyword() | map(), (pid() -> result)) ::
          result | {:error, String.t()}
        when result: term()
  def run(source_input, fun) when is_function(fun, 1) do
    case Source.from(source_input) do
      {:ok, source} -> with_connection(source, fun)
      {:error, reason} -> {:error, reason}
    end
  end

  defp with_connection(%Source{} = source, fun) do
    case Postgrex.start_link(Source.to_postgrex_opts(source)) do
      {:ok, conn} ->
        # Unlink so a Postgres disconnect mid-query doesn't propagate an EXIT
        # signal and kill the caller (typically a LiveView). Errors then surface
        # through Postgrex.query's return value instead.
        Process.unlink(conn)

        # Lantern's introspection assumes the `public` schema; pin search_path
        # so DML queries don't accidentally hit a different table than the
        # sidebar listed if the role has a non-default search_path.
        Postgrex.query(conn, "SET search_path TO public", [])

        try do
          fun.(conn)
        catch
          :exit, reason -> {:error, "Could not connect to database: #{inspect(reason)}"}
        after
          stop(conn)
        end

      {:error, reason} ->
        {:error, "Could not connect to database: #{inspect(reason)}"}
    end
  end

  defp stop(conn) do
    GenServer.stop(conn, :normal, 5_000)
  rescue
    _ -> :ok
  catch
    # `GenServer.stop/3` can also propagate an `:exit` if the target process is
    # already gone; treat that as a successful teardown.
    :exit, _ -> :ok
  end
end
