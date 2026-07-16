defmodule Lantern.Source do
  @moduledoc """
  A normalized description of how to reach a Postgres database.

  Lantern is connection-agnostic: a host application hands it a *source* and
  Lantern opens one-shot connections from it. A source can be built from:

    * a `postgres://` / `postgresql://` URL string,
    * a keyword list / map of connection options, or
    * any struct/map exposing `host`/`hostname`, `port`, `username`, `password`,
      and `database` (e.g. an Ecto-backed connection record), via `from/1`.

  The struct mirrors the subset of `Postgrex.start_link/1` options Lantern
  needs. `to_postgrex_opts/1` produces the final option list.
  """

  @enforce_keys [:hostname, :port, :username, :database]
  defstruct hostname: nil,
            port: 5432,
            username: nil,
            password: nil,
            database: nil,
            ssl: false,
            parameters: [],
            types: nil

  @type t :: %__MODULE__{
          hostname: String.t(),
          port: pos_integer(),
          username: String.t(),
          password: String.t() | nil,
          database: String.t(),
          ssl: boolean(),
          parameters: [{String.t(), String.t()}],
          types: module() | nil
        }

  @default_port 5432
  @default_database "postgres"

  @doc """
  Builds a `Source` from a URL string, keyword list, map, or existing struct.

  Returns `{:ok, source}` or `{:error, reason}`.
  """
  @spec from(t() | String.t() | keyword() | map()) :: {:ok, t()} | {:error, String.t()}
  def from(%__MODULE__{} = source), do: validate(source)

  def from(url) when is_binary(url), do: parse_url(url)

  def from(opts) when is_list(opts), do: from(Map.new(opts))

  def from(map) when is_map(map) do
    source = %__MODULE__{
      hostname: fetch(map, [:hostname, :host]),
      port: fetch(map, [:port]) |> normalize_port(),
      username: fetch(map, [:username, :user]),
      password: fetch(map, [:password, :pass]),
      database: fetch(map, [:database, :db]) || @default_database,
      ssl: fetch(map, [:ssl]) || false,
      types: fetch(map, [:types])
    }

    validate(source)
  end

  @doc """
  Parses a `postgres://user:pass@host:port/database?sslmode=...` URL.
  """
  @spec parse_url(String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse_url(url) when is_binary(url) do
    uri = URI.parse(url)

    cond do
      uri.scheme not in ["postgres", "postgresql"] ->
        {:error, "Connection URL must start with postgres:// or postgresql://"}

      is_nil(uri.host) or uri.host == "" ->
        {:error, "Connection URL is missing a host"}

      true ->
        {username, password} = parse_userinfo(uri.userinfo)

        source = %__MODULE__{
          hostname: uri.host,
          port: uri.port || @default_port,
          username: username,
          password: password,
          database: parse_database(uri.path),
          ssl: parse_ssl(uri.query),
          parameters: parse_parameters(uri.query)
        }

        validate(source)
    end
  end

  @doc """
  Converts a `Source` into the keyword list passed to `Postgrex.start_link/1`.

  `pool_size` is fixed at 1 — Lantern opens single, short-lived connections.

  A `types` module (from `Postgrex.Types.define/3`) is passed through when set,
  so a host app can teach the connection about extension types its databases
  use — e.g. pgvector's `vector`, which `Postgrex.DefaultTypes` can't decode and
  which otherwise crashes any table preview that selects such a column.
  """
  @spec to_postgrex_opts(t()) :: keyword()
  def to_postgrex_opts(%__MODULE__{} = source) do
    base = [
      hostname: source.hostname,
      port: source.port,
      username: source.username,
      password: source.password,
      database: source.database,
      ssl: ssl_opts(source),
      pool_size: 1,
      connect_timeout: 10_000,
      timeout: 30_000
    ]

    base
    |> maybe_put(:parameters, source.parameters, &(&1 != []))
    |> maybe_put(:types, source.types, &(&1 != nil))
  end

  defp maybe_put(opts, key, value, keep?) do
    if keep?.(value), do: Keyword.put(opts, key, value), else: opts
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  # When SSL is disabled, pass `false` (Postgrex skips TLS entirely).
  #
  # When enabled, build a verifying TLS config rather than a bare `ssl: true`.
  # Two hosting realities force the extra options:
  #
  #   * **OTP 26/27 PKIX strictness** rejects some real-world chains (e.g.
  #     intermediates whose KeyUsage/ExtendedKeyUsage are flagged as a
  #     `key_usage_mismatch` per RFC 5280) at the TLS layer — surfacing as a
  #     "Unsupported Certificate" alert before Postgres auth even begins. We
  #     tolerate that one specific bad_cert reason while keeping every other
  #     check intact.
  #   * **Wildcard certs** (e.g. `*.db.host.com` fronting per-branch endpoints)
  #     only match correctly under the HTTPS hostname rules, so we install the
  #     `:https` match_fun explicitly.
  defp ssl_opts(%__MODULE__{ssl: false}), do: false

  defp ssl_opts(%__MODULE__{ssl: true} = source) do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(source.hostname),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ],
      verify_fun:
        {fn
           _cert, {:bad_cert, {:key_usage_mismatch, _}}, state -> {:valid, state}
           _cert, {:bad_cert, reason}, _state -> {:fail, {:bad_cert, reason}}
           _cert, {:extension, _}, state -> {:unknown, state}
           _cert, :valid, state -> {:valid, state}
           _cert, :valid_peer, state -> {:valid, state}
         end, []}
    ]
  end

  defp validate(%__MODULE__{} = source) do
    cond do
      blank?(source.hostname) -> {:error, "Source is missing a host"}
      blank?(source.username) -> {:error, "Source is missing a username"}
      blank?(source.database) -> {:error, "Source is missing a database"}
      not is_integer(source.port) or source.port <= 0 -> {:error, "Source has an invalid port"}
      true -> {:ok, source}
    end
  end

  defp fetch(map, keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(map, key) do
        nil -> Map.get(map, to_string(key))
        value -> value
      end
    end)
  end

  defp normalize_port(nil), do: @default_port
  defp normalize_port(port) when is_integer(port), do: port

  defp normalize_port(port) when is_binary(port) do
    case Integer.parse(port) do
      {int, ""} -> int
      _ -> :invalid
    end
  end

  defp parse_userinfo(nil), do: {nil, nil}

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {decode(user), nil}
      [user, pass] -> {decode(user), decode(pass)}
    end
  end

  defp parse_database(nil), do: @default_database
  defp parse_database("/"), do: @default_database
  defp parse_database("/" <> rest) when rest != "", do: decode(rest)
  defp parse_database(_), do: @default_database

  defp parse_ssl(nil), do: false

  defp parse_ssl(query) do
    case URI.decode_query(query) do
      %{"sslmode" => mode} when mode in ["require", "verify-ca", "verify-full", "prefer"] -> true
      _ -> false
    end
  end

  # Neon (and Flicker branch) connection strings carry `options=endpoint%3D<id>`
  # as a startup parameter for SNI-based routing. Postgrex forwards the
  # `parameters` list verbatim to Postgres as startup message parameters.
  defp parse_parameters(nil), do: []

  defp parse_parameters(query) do
    case URI.decode_query(query) do
      %{"options" => options} -> [{"options", options}]
      _ -> []
    end
  end

  defp decode(value), do: URI.decode_www_form(value)

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
