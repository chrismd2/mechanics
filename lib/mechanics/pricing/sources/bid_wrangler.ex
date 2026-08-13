defmodule Mechanics.Pricing.Sources.BidWrangler do
  @moduledoc false

  @behaviour Mechanics.Pricing.Sources

  alias Mechanics.Pricing.AuctionSource
  alias Mechanics.Pricing.BidWrangler, as: BW

  @impl true
  def search(%AuctionSource{base_url: base_url}, query, opts) do
    http_get = Keyword.get(opts, :http_get, &default_http_get/1)
    page = Keyword.get(opts, :page, 1)
    origin = String.trim_trailing(base_url, "/")
    url = "#{origin}/api/items/search?query=#{URI.encode_www_form(query)}&page=#{page}"

    with {:ok, body} <- http_get.(url),
         {:ok, data} when is_map(data) <- Jason.decode(body) do
      items = Map.get(data, "items") || []

      hits =
        Enum.map(items, fn item ->
          id = Map.get(item, "id")
          auction_id = Map.get(item, "auction_id")

          source_url =
            cond do
              is_integer(auction_id) and is_integer(id) ->
                "#{origin}/ui/auctions/#{auction_id}/#{id}"

              is_integer(id) ->
                "#{origin}/api/items/#{id}"

              true ->
                "#{origin}/api/items/#{id}"
            end

          %{
            "external_id" => to_string(id),
            "source_url" => source_url,
            "title" => Map.get(item, "name") || Map.get(item, "title"),
            "raw" => compact_item(item)
          }
        end)

      {:ok, hits}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_search_json}
    end
  end

  @impl true
  def fetch_detail(url_or_id, opts) do
    http_get = Keyword.get(opts, :http_get, &default_http_get/1)

    api_url =
      case BW.parse_item_ui_url(url_or_id) do
        {:ok, %{origin: origin, item_id: item_id}} -> "#{origin}/api/items/#{item_id}"
        :error -> url_or_id
      end

    with {:ok, body} <- http_get.(api_url),
         {:ok, item} when is_map(item) <- Jason.decode(body) do
      {:ok, BW.attrs_from_item(item)}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_item_json}
    end
  end

  defp compact_item(item) when is_map(item) do
    Map.take(item, [
      "id",
      "name",
      "vin",
      "status",
      "auction_id",
      "auction_name",
      "currency_name",
      "simple_id",
      "lot_identifier",
      "api_bidding_state"
    ])
  end

  defp default_http_get(url) do
    headers = [
      {"Accept", "application/json"},
      {"User-Agent", "MechanicsPricingBot/1.0"}
    ]

    case Finch.build(:get, url, headers) |> Finch.request(Mechanics.Finch, receive_timeout: 15_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
