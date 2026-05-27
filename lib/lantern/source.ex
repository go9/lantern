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
            ssl: false

  @type t :: %__MODULE__{
          hostname: String.t(),
          port: pos_integer(),
          username: String.t(),
          password: String.t() | nil,
          database: String.t(),
          ssl: boolean()
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
      ssl: fetch(map, [:ssl]) || false
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
          ssl: parse_ssl(uri.query)
        }

        validate(source)
    end
  end

  @doc """
  Converts a `Source` into the keyword list passed to `Postgrex.start_link/1`.

  `pool_size` is fixed at 1 — Lantern opens single, short-lived connections.
  """
  @spec to_postgrex_opts(t()) :: keyword()
  def to_postgrex_opts(%__MODULE__{} = source) do
    [
      hostname: source.hostname,
      port: source.port,
      username: source.username,
      password: source.password,
      database: source.database,
      ssl: source.ssl,
      pool_size: 1,
      connect_timeout: 10_000,
      timeout: 30_000
    ]
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

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
      {int, _} -> int
      :error -> @default_port
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

  defp decode(value), do: URI.decode_www_form(value)

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
