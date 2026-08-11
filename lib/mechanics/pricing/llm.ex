defmodule Mechanics.Pricing.LLM do
  @moduledoc """
  HTTP client for the pricing agent's chat-completions provider (v1: Groq).

  Isolated so the provider can be swapped without changing `Pricing.Agent`.
  """

  require Logger

  @default_base_url "https://api.groq.com/openai/v1"
  @default_model "llama-3.3-70b-versatile"

  @doc """
  Posts a chat completion request. Returns decoded JSON map on success.
  """
  def chat_completion(messages, tools \\ [], opts \\ []) do
    api_key = Keyword.get(opts, :api_key) || System.get_env("GROQ_API_KEY")
    model = Keyword.get(opts, :model) || System.get_env("GROQ_MODEL") || @default_model
    base_url = Keyword.get(opts, :base_url) || System.get_env("PRICING_LLM_BASE_URL") || @default_base_url
    http_client = Keyword.get(opts, :http_client, &default_http_post/3)

    if is_nil(api_key) or api_key == "" do
      {:error, :missing_api_key}
    else
      body =
        %{
          "model" => model,
          "messages" => messages,
          "temperature" => 0.2
        }
        |> maybe_put_tools(tools)

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"},
        {"Accept", "application/json"}
      ]

      url = String.trim_trailing(base_url, "/") <> "/chat/completions"

      case http_client.(url, headers, Jason.encode!(body)) do
        {:ok, %{status: status, body: response_body}} when status in 200..299 ->
          case Jason.decode(response_body) do
            {:ok, decoded} -> {:ok, decoded}
            {:error, _} -> {:error, :invalid_json}
          end

        {:ok, %{status: status, body: response_body}} ->
          Logger.warning("Pricing LLM HTTP #{status}: #{String.slice(to_string(response_body), 0, 500)}")
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.warning("Pricing LLM request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp maybe_put_tools(body, []), do: body
  defp maybe_put_tools(body, tools), do: Map.merge(body, %{"tools" => tools, "tool_choice" => "auto"})

  defp default_http_post(url, headers, body) do
    Finch.build(:post, url, headers, body) |> Finch.request(Mechanics.Finch)
  end
end
