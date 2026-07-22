defmodule LanternDemo.S3Sandbox.Adapter do
  @moduledoc """
  `LanternS3.Uploader.Adapter` for the ephemeral demo sandbox — the presign-time
  server-side gate on the public write surface.

  LiveView's `allow_upload/3` enforces file **count** (`max_entries: 5`), per-file
  **size** (`max_file_size: 5 MB`), and thus the 25 MB session aggregate, and
  refuses entries before this adapter is ever called. This adapter re-validates
  **type** (the client `accept` is advisory) and builds the object **key**
  server-side under the session's own prefix — the client never supplies a path.
  The presigned PUT pins `Content-Type`, and a post-completion `head/3` sweep
  (see the reaper) is the backstop for a client that lies about size/type.

  `config` (the component's `:adapter_config` assign) is just the session's
  `%{bucket: String.t(), prefix: String.t()}` — the scoped S3 credentials are
  fetched internally from `S3Sandbox.Storage`, never carried through LiveView
  assigns.
  """

  @behaviour LanternS3.Uploader.Adapter

  alias LanternDemo.S3Sandbox.Limits
  alias LanternDemo.S3Sandbox.Storage
  alias LanternS3.Storage.S3

  # Presigned PUT lifetime — short, since the client uploads immediately.
  @put_expiry_seconds 120

  @impl true
  def presign(%{bucket: bucket, prefix: prefix}, entry, _opts) do
    %{filename: filename, content_type: content_type} = entry
    ext = filename |> Path.extname() |> String.trim_leading(".")

    with {:ok, config} <- Storage.s3_config(),
         {:ok, key} <- Limits.object_key(prefix, filename),
         :ok <- validate_type(ext, content_type),
         {:ok, canonical_type} <- Limits.content_type(ext),
         {:ok, url} <-
           S3.presigned_put(config, bucket, key,
             content_type: canonical_type,
             expires_in: @put_expiry_seconds
           ) do
      {:ok, %{uploader: "S3", key: key, url: url}}
    else
      {:error, :not_configured} -> {:error, "The upload sandbox isn't configured."}
      other -> other
    end
  end

  def presign(_config, _entry, _opts), do: {:error, :not_configured}

  # Re-validate the client-declared type against the allowlist. Uses the same
  # rules as the completion sweep, so pre- and post-checks can't disagree.
  defp validate_type(ext, content_type) do
    case Limits.validate_type(ext, content_type) do
      :ok -> :ok
      {:error, reason} -> {:error, Limits.message(reason)}
    end
  end
end
