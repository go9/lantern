defmodule LanternDemo.Captcha do
  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc "Returns the Turnstile site key for embedding in HTML."
  def site_key do
    Application.get_env(:lantern_demo, :turnstile_site_key, "1x00000000000000000000AA")
  end

  @doc "Verifies a Turnstile token. Returns :ok or {:error, reason}."
  @spec verify(String.t()) :: :ok | {:error, String.t()}
  def verify(token) when is_binary(token) and token != "" do
    secret = Application.get_env(:lantern_demo, :turnstile_secret_key, "1x0000000000000000000000000000000AA")

    case Req.post(@verify_url, form: [secret: secret, response: token]) do
      {:ok, %{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"error-codes" => codes}}} ->
        {:error, "Turnstile rejected: #{Enum.join(codes, ", ")}"}

      {:ok, %{status: status}} ->
        {:error, "Turnstile API returned #{status}"}

      {:error, reason} ->
        {:error, "Turnstile request failed: #{inspect(reason)}"}
    end
  end

  def verify(_), do: {:error, "Missing captcha token"}
end
