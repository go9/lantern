defmodule Lantern.Connection do
  @moduledoc """
  Opens one-shot Postgrex connections from a `Lantern.Source`.

  Lantern deliberately avoids a long-lived pool: an embeddable `live_component`
  has no reliable teardown hook, so each operation opens a connection, runs, and
  closes it. The per-call cost is irrelevant for an administrative tool and it
  leaves nothing for host applications to supervise.
  """

  alias Lantern.Source

  # Budget for the diagnostic probe in `real_connect_error/1`. It's a budget
  # rather than a connect timeout: the probe only ever runs on a path that has
  # already spent seconds failing, so capping Postgrex's own connect and
  # handshake timeouts at it (the latter otherwise inherits `:timeout`, i.e.
  # 30s) keeps a truly unreachable host from taking noticeably longer to report
  # than it does today, while still leaving room for TLS and auth on a slow but
  # live server.
  @probe_timeout 5_000

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
    opts = Source.to_postgrex_opts(source)

    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        # Unlink so a Postgres disconnect mid-query doesn't propagate an EXIT
        # signal and kill the caller (typically a LiveView). Errors then surface
        # through Postgrex.query's return value instead.
        Process.unlink(conn)

        # Lantern's introspection assumes the `public` schema; pin search_path
        # so DML queries don't accidentally hit a different table than the
        # sidebar listed if the role has a non-default search_path.
        #
        # This is also the first statement that needs the connection to actually
        # exist, so its result doubles as the liveness check — a dead database is
        # not observable before this point. See `real_connect_error/1`.
        case Postgrex.query(conn, "SET search_path TO public", []) do
          {:error, %DBConnection.ConnectionError{}} ->
            stop(conn)
            {:error, real_connect_error(opts)}

          _ ->
            try do
              fun.(conn)
            catch
              :exit, _reason -> {:error, Lantern.Errors.connection_error()}
            after
              stop(conn)
            end
        end

      {:error, _reason} ->
        {:error, real_connect_error(opts)}
    end
  end

  # `Postgrex.start_link/1` starts a *pool*. It returns `{:ok, pid}` as soon as
  # the pool process boots — the connection behind it is opened asynchronously,
  # and when that fails the real error is only ever *logged*, never returned.
  # The pool just keeps retrying, so every query against it fails with the same
  # generic "connection not available and request was dropped from queue after
  # 5991ms" timeout: copy that describes our queue rather than their database.
  #
  # The real reason is far more actionable, and often self-explaining:
  #
  #   * the database failed to resume; please retry    (FATAL 08006)
  #   * password authentication failed for user "..."  (FATAL 28P01)
  #   * tcp connect (host:5432): non-existing domain   (:nxdomain)
  #
  # To recover it, open one throwaway connection with `Postgrex.Protocol` — the
  # same module the pool drives — and read the error it hands back directly.
  #
  # Tradeoff: `Postgrex.Protocol` is internal-ish Postgrex API. Accepted, because
  # it's the only way to obtain the error at all and the blast radius is small:
  # it runs only on a path that is already failing (the happy path never touches
  # it and is unchanged), it's confined to these three functions, and if a future
  # Postgrex changes it the probe process simply dies and we fall back to today's
  # generic copy.
  defp real_connect_error(opts) do
    case probe(opts) do
      {:error, exception} -> Lantern.Errors.humanize_connect_error(exception)
      :no_diagnosis -> Lantern.Errors.connection_error()
    end
  end

  # `Postgrex.Protocol.connect/1` expects to be running inside a DBConnection
  # process, and mutates whichever process calls it: it sets `trap_exit`,
  # relabels the process, and puts the socket in active mode so Postgres traffic
  # lands in that mailbox. None of that may happen to the caller (a LiveView), so
  # the probe runs in a throwaway process — whose death is also the cleanup, for
  # the socket, the flags, and any straggling messages alike.
  #
  # The result travels back as the exit reason: a monitor is then the only thing
  # that can put a message in the caller's mailbox, and `demonitor(:flush)`
  # guarantees none is left behind on any path out of here.
  defp probe(opts) do
    tag = make_ref()
    opts = probe_opts(opts)

    {pid, monitor} = spawn_monitor(fn -> exit({tag, connect_and_close(opts)}) end)

    receive do
      {:DOWN, ^monitor, :process, ^pid, {^tag, result}} ->
        result

      # The probe crashed rather than answering — nothing to report but the
      # generic copy, which is what the caller would have shown anyway.
      {:DOWN, ^monitor, :process, ^pid, _crash} ->
        :no_diagnosis
    after
      # Backstop only: Postgrex's own timeouts are capped inside the probe, so
      # getting here means it hung some other way. Never make an already-failing
      # page wait on a diagnostic.
      @probe_timeout * 2 ->
        Process.demonitor(monitor, [:flush])
        Process.exit(pid, :kill)
        :no_diagnosis
    end
  end

  defp connect_and_close(opts) do
    case Postgrex.Protocol.connect(opts) do
      # The pool couldn't connect but a direct connect can (a transient blip, or
      # a pool that's merely saturated). There's no real error to surface, but we
      # did just open a socket — close it politely instead of letting Postgres
      # discover the drop and log it.
      {:ok, state} ->
        Postgrex.Protocol.disconnect(
          %DBConnection.ConnectionError{message: "lantern diagnostic probe"},
          state
        )

        :no_diagnosis

      {:error, _exception} = error ->
        error
    end
  end

  # `types: nil` skips Postgrex's type bootstrap — a `pg_type` round trip routed
  # through `Postgrex.TypeSupervisor`. A connect fails at TCP, TLS, or
  # startup/auth, all strictly before that, so the probe has no use for types.
  defp probe_opts(opts) do
    opts
    |> Keyword.put(:types, nil)
    |> Keyword.put(:connect_timeout, @probe_timeout)
    |> Keyword.put(:handshake_timeout, @probe_timeout)
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
