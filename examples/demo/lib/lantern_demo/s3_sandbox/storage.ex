defmodule LanternDemo.S3Sandbox.Storage do
  @moduledoc """
  S3 config + bucket resolution for the demo upload sandbox.

  One private bucket (`:s3_sandbox_bucket`), with creds scoped to just that
  bucket, sourced from the `:ex_aws` env. Sessions are isolated by **prefix**,
  not by bucket — so the demo app never needs bucket create/delete power.

  Everything is optional: when unset (`configured?/0` is false) the S3 upload
  demo degrades to a "coming soon" state and the rest of the page is unaffected.
  """

  alias LanternS3.Storage.S3

  @default_region "auto"
  @default_host "t3.storage.dev"

  @spec bucket() :: String.t() | nil
  def bucket, do: Application.get_env(:lantern_demo, :s3_sandbox_bucket)

  @spec configured?() :: boolean()
  def configured? do
    ex = Application.get_all_env(:ex_aws)
    is_binary(bucket()) and is_binary(ex[:access_key_id]) and is_binary(ex[:secret_access_key])
  end

  @spec s3_config() :: {:ok, S3.Config.t()} | {:error, :not_configured}
  def s3_config do
    if configured?() do
      ex = Application.get_all_env(:ex_aws)
      s3 = Application.get_env(:ex_aws, :s3, [])

      {:ok,
       S3.Config.new(
         access_key_id: ex[:access_key_id],
         secret_access_key: ex[:secret_access_key],
         region: s3[:region] || @default_region,
         host: s3[:host] || @default_host
       )}
    else
      {:error, :not_configured}
    end
  end
end
