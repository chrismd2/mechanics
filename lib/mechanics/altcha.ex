defmodule Mechanics.Altcha do
  @moduledoc """
  Self-hosted ALTCHA challenge generation and payload verification.
  """

  alias Altcha.ChallengeOptions

  @default_ttl_seconds 600
  @default_max_number 50_000

  def enabled? do
    Application.get_env(:mechanics, :altcha, [])
    |> Keyword.get(:enabled, false)
  end

  def create_challenge do
    if enabled?() do
      options = %ChallengeOptions{
        algorithm: :sha256,
        expires: DateTime.to_unix(DateTime.utc_now(), :second) + @default_ttl_seconds,
        hmac_key: hmac_key!(),
        max_number: @default_max_number
      }

      {:ok, Altcha.create_challenge(options)}
    else
      {:error, :disabled}
    end
  end

  def verify_payload(payload) do
    if enabled?() do
      do_verify_payload(payload)
    else
      :ok
    end
  end

  defp do_verify_payload(payload) when is_binary(payload) and payload != "" do
    if Altcha.verify_solution(payload, hmac_key!()) do
      :ok
    else
      {:error, :invalid_payload}
    end
  end

  defp do_verify_payload(_), do: {:error, :missing_payload}

  defp hmac_key! do
    Application.get_env(:mechanics, :altcha, [])
    |> Keyword.fetch!(:hmac_key)
  end
end
