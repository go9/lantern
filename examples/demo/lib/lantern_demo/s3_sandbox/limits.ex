defmodule LanternDemo.S3Sandbox.Limits do
  @moduledoc """
  Server-side upload limits for the ephemeral S3 demo sandbox — the single
  enforcement point for a public write surface. Pure functions, no storage
  dependency, so they are unit-tested in isolation and reused by both the
  presign adapter (pre-upload rejection) and the completion/reaper sweep
  (post-upload re-check).

  Contract (flicker #986):

    * allowlist: jpg / jpeg / png / webp / gif / pdf
    * ≤ 5 MB per file, ≤ 5 files per session, ≤ 25 MB per session
    * object keys are built server-side from a sanitized basename under the
      session's own prefix — the client never supplies a path, and `../`,
      absolute paths, empty/dot names, and hidden dotfiles are rejected.
  """

  @max_file_bytes 5 * 1_024 * 1_024
  @max_files 5
  @max_session_bytes 25 * 1_024 * 1_024
  @max_filename 128

  # ext => allowed client-declared content-types (advisory type must match one).
  @allowlist %{
    "jpg" => ["image/jpeg"],
    "jpeg" => ["image/jpeg"],
    "png" => ["image/png"],
    "webp" => ["image/webp"],
    "gif" => ["image/gif"],
    "pdf" => ["application/pdf"]
  }

  def max_file_bytes, do: @max_file_bytes
  def max_files, do: @max_files
  def max_session_bytes, do: @max_session_bytes
  def allowed_extensions, do: Map.keys(@allowlist)

  @doc "Canonical content-type to pin on the presigned PUT for `ext`."
  @spec content_type(String.t()) :: {:ok, String.t()} | {:error, :type_not_allowed}
  def content_type(ext) do
    case @allowlist[String.downcase(ext)] do
      [ct | _] -> {:ok, ct}
      _ -> {:error, :type_not_allowed}
    end
  end

  @doc """
  Validate one upload against the type allowlist, per-file size, per-session
  file count, and per-session byte quota. `session` carries the running totals
  (`%{bytes: used, count: used}`).
  """
  @spec validate_upload(%{filename: String.t(), content_type: String.t(), size: term()}, map()) ::
          :ok | {:error, atom()}
  def validate_upload(%{filename: filename, content_type: content_type, size: size}, session) do
    used_bytes = Map.get(session, :bytes, 0)
    used_count = Map.get(session, :count, 0)

    with {:ok, base} <- sanitize_basename(filename),
         ext = extension(base),
         :ok <- check_type(ext, content_type),
         :ok <- check_size(size),
         :ok <- check_count(used_count),
         :ok <- check_quota(used_bytes, size) do
      :ok
    end
  end

  @doc "Build the object key under `prefix` from a sanitized basename. Never escapes `prefix`."
  @spec object_key(String.t(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def object_key(prefix, filename) do
    with {:ok, base} <- sanitize_basename(filename) do
      {:ok, prefix <> base}
    end
  end

  @doc """
  Reduce a client filename to a safe basename: directory components dropped,
  charset restricted to `[A-Za-z0-9._-]`, extension required and allowlisted.
  Traversal, absolute paths, empty/dot names, and hidden dotfiles are rejected.
  """
  @spec sanitize_basename(term()) :: {:ok, String.t()} | {:error, atom()}
  def sanitize_basename(filename) when is_binary(filename) do
    cleaned =
      filename
      |> Path.basename()
      |> String.replace(~r/[^A-Za-z0-9._-]/u, "_")
      |> String.slice(0, @max_filename)

    cond do
      cleaned in ["", ".", ".."] -> {:error, :invalid_name}
      String.starts_with?(cleaned, ".") -> {:error, :invalid_name}
      String.contains?(cleaned, "/") -> {:error, :invalid_name}
      not Map.has_key?(@allowlist, extension(cleaned)) -> {:error, :type_not_allowed}
      true -> {:ok, cleaned}
    end
  end

  def sanitize_basename(_), do: {:error, :invalid_name}

  @doc "Human message for a rejection reason."
  def message(:type_not_allowed),
    do: "That file type isn't allowed. Try jpg, png, webp, gif, or pdf."

  def message(:type_mismatch), do: "The file's declared type didn't match its extension."
  def message(:file_too_large), do: "Files must be 5 MB or smaller."
  def message(:too_many_files), do: "You can upload up to 5 files per session."
  def message(:session_quota_exceeded), do: "That would exceed the 25 MB per-session limit."
  def message(:invalid_name), do: "That filename isn't allowed."
  def message(_), do: "Upload rejected."

  # ---------------------------------------------------------------------------

  defp extension(name),
    do: name |> Path.extname() |> String.trim_leading(".") |> String.downcase()

  defp check_type(ext, content_type) do
    case @allowlist[ext] do
      nil -> {:error, :type_not_allowed}
      types -> if content_type in types, do: :ok, else: {:error, :type_mismatch}
    end
  end

  defp check_size(size) when is_integer(size) and size >= 0 and size <= @max_file_bytes, do: :ok
  defp check_size(_), do: {:error, :file_too_large}

  defp check_count(used) when is_integer(used) and used < @max_files, do: :ok
  defp check_count(_), do: {:error, :too_many_files}

  defp check_quota(used, size)
       when is_integer(used) and is_integer(size) and used + size <= @max_session_bytes,
       do: :ok

  defp check_quota(_, _), do: {:error, :session_quota_exceeded}
end
