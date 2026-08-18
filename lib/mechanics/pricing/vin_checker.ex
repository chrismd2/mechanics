defmodule Mechanics.Pricing.VinChecker do
  @moduledoc """
  VIN decode / check tool used by the pricing suggest flow.

  Default strategy:
  1. Look up stored vehicle market prices with the same VIN
  2. Fall back to the public NHTSA vPIC DecodeVinValues API

  Inject `:checker` or `:http_client` in tests.
  """

  require Logger

  import Ecto.Query, warn: false

  alias Mechanics.Pricing.VehicleMarketPrice
  alias Mechanics.Repo

  @nhtsa_base "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues"

  def normalize(vin) when is_binary(vin) do
    vin
    |> String.trim()
    |> String.replace(" ", "")
    |> String.upcase()
  end

  def normalize(_), do: ""

  def valid_vin?(vin) when is_binary(vin) do
    normalized = normalize(vin)
    String.length(normalized) == 17 and String.match?(normalized, ~r/\A[A-HJ-NPR-Z0-9]+\z/)
  end

  def valid_vin?(_), do: false

  @doc """
  Returns `{:ok, attrs}` with string keys (`vin`, and any of make/model/year/miles)
  or `{:error, reason}`.
  """
  def check(vin, opts \\ []) do
    checker =
      Keyword.get(opts, :checker) ||
        Keyword.get(Application.get_env(:mechanics, __MODULE__, []), :checker) ||
        &default_check/2

    normalized = normalize(vin)

    cond do
      not valid_vin?(normalized) ->
        {:error, :invalid_vin}

      true ->
        checker.(normalized, opts)
    end
  end

  defp default_check(vin, opts) do
    case from_market_prices(vin) do
      {:ok, _} = ok ->
        ok

      :error ->
        from_nhtsa(vin, opts)
    end
  end

  defp from_market_prices(vin) do
    row =
      from(m in VehicleMarketPrice,
        where: fragment("upper(?)", m.vin) == ^vin,
        order_by: [desc: m.inserted_at, desc: m.id],
        limit: 1
      )
      |> Repo.one()

    case row do
      %VehicleMarketPrice{} = m ->
        {:ok,
         %{
           "vin" => vin,
           "make" => m.make,
           "model" => m.model,
           "year" => m.year,
           "miles" => m.miles,
           "zipcode" => m.zipcode || "00000"
         }}

      nil ->
        :error
    end
  end

  defp from_nhtsa(vin, opts) do
    http_client = Keyword.get(opts, :http_client, &default_http_get/1)
    url = "#{@nhtsa_base}/#{URI.encode(vin)}?format=json"

    case http_client.(url) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        parse_nhtsa_body(vin, body)

      {:ok, %{status: status}} ->
        Logger.info("VIN checker NHTSA HTTP #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.info("VIN checker NHTSA failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_nhtsa_body(vin, body) do
    with {:ok, decoded} <- Jason.decode(body),
         [result | _] <- List.wrap(Map.get(decoded, "Results")),
         make when is_binary(make) and make != "" <- blank_to_nil(Map.get(result, "Make")),
         model when is_binary(model) and model != "" <- blank_to_nil(Map.get(result, "Model")),
         {:ok, year} <- Mechanics.NumberParse.to_integer(Map.get(result, "ModelYear")) do
      {:ok,
       %{
         "vin" => vin,
         "make" => make,
         "model" => model,
         "year" => year
       }}
    else
      _ ->
        {:error, :vin_decode_failed}
    end
  end

  defp default_http_get(url) do
    headers = [
      {"Accept", "application/json"},
      {"User-Agent", "MechanicsPricingBot/1.0"}
    ]

    Finch.build(:get, url, headers) |> Finch.request(Mechanics.Finch, receive_timeout: 15_000)
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.trim(value)
  defp blank_to_nil(value), do: value
end
