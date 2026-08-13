defmodule Mechanics.Pricing.Sources.Royal do
  @moduledoc false

  @behaviour Mechanics.Pricing.Sources

  alias Mechanics.Pricing.AuctionSource

  @lot_ui ~r{\A(?<origin>https?://[^/]+)/auctions/(?<auction_id>\d+)/lot/(?<lot_id>\d+)(?:-[^/]*)?/?\z}i

  @search_query """
  query get_lots_search($pagination: Pagination, $filter: AuctionLotFilterInput, $search: AuctionLotSearchInput, $order: [AuctionLotOrderInput]) {
    lots(pagination: $pagination, filter: $filter, search: $search, order: $order) {
      total
      lots {
        auction_lot_id
        lot_number
        title
        public_url
        auction_lot_status
        winning_bid_amount
        starting_bid
        auction { auction_id title auction_status end_time }
      }
    }
  }
  """

  @lot_query """
  query get_lot($auction_lot_id: String!) {
    lot(auction_lot_id: $auction_lot_id) {
      auction_lot_id
      auction_id
      lot_number
      title
      public_url
      auction_lot_status
      winning_bid_amount
      starting_bid
      description_plain
      auction { auction_id title }
    }
  }
  """

  @past_auctions_query """
  query get_past_auctions($pagination: AuctionPaginationInput, $filter: AuctionFilterInput) {
    auctions(pagination: $pagination, filter: $filter) {
      total
      auctions {
        auction_id
        title
        auction_status
        start_time
        end_time
      }
    }
  }
  """

  @impl true
  def search(%AuctionSource{base_url: base_url}, query, opts) do
    http_post = Keyword.get(opts, :http_post, &default_http_post/2)
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    origin = String.trim_trailing(base_url, "/")
    endpoint = "#{origin}/api"

    variables = %{
      "pagination" => %{"page" => page, "pageSize" => page_size},
      "filter" => %{
        "auction_lot_status" => [100, 200],
        "auction_visible_on_front" => true
      },
      "search" => %{"text" => query},
      "order" => [%{"column" => "auction_end_time", "direction" => "desc"}]
    }

    body =
      Jason.encode!(%{
        "operationName" => "get_lots_search",
        "query" => @search_query,
        "variables" => variables
      })

    with {:ok, resp_body} <- http_post.(endpoint, body),
         {:ok, decoded} <- Jason.decode(resp_body),
         lots when is_list(lots) <- get_in(decoded, ["data", "lots", "lots"]) do
      hits =
        Enum.map(lots, fn lot ->
          lot_id = Map.get(lot, "auction_lot_id")
          public_url = Map.get(lot, "public_url")

          source_url =
            cond do
              is_binary(public_url) and public_url != "" ->
                if String.starts_with?(public_url, "http"),
                  do: public_url,
                  else: origin <> public_url

              true ->
                auction_id = get_in(lot, ["auction", "auction_id"]) || "0"
                "#{origin}/auctions/#{auction_id}/lot/#{lot_id}"
            end

          %{
            "external_id" => to_string(lot_id),
            "source_url" => source_url,
            "title" => Map.get(lot, "title"),
            "raw" => compact_lot(lot)
          }
        end)

      {:ok, hits}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:ok, []}
      _ -> {:error, :invalid_search_json}
    end
  end

  @impl true
  def fetch_detail(url_or_id, opts) do
    http_post = Keyword.get(opts, :http_post, &default_http_post/2)

    {origin, lot_id} =
      case parse_lot_url(url_or_id) do
        {:ok, %{origin: origin, lot_id: lot_id}} -> {origin, lot_id}
        :error -> {Keyword.get(opts, :origin, "https://live.royalauctiongroup.com"), url_or_id}
      end

    endpoint = "#{String.trim_trailing(origin, "/")}/api"

    body =
      Jason.encode!(%{
        "operationName" => "get_lot",
        "query" => @lot_query,
        "variables" => %{"auction_lot_id" => to_string(lot_id)}
      })

    with {:ok, resp_body} <- http_post.(endpoint, body),
         {:ok, decoded} <- Jason.decode(resp_body),
         lot when is_map(lot) <- get_in(decoded, ["data", "lot"]) do
      {:ok, attrs_from_lot(lot)}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :lot_not_found}
      _ -> {:error, :invalid_lot_json}
    end
  end

  def parse_lot_url(url) when is_binary(url) do
    case Regex.named_captures(@lot_ui, String.trim(url)) do
      %{"origin" => origin, "auction_id" => auction_id, "lot_id" => lot_id} ->
        {:ok, %{origin: origin, auction_id: auction_id, lot_id: lot_id}}

      _ ->
        :error
    end
  end

  def parse_lot_url(_), do: :error

  def list_past_auctions(%AuctionSource{base_url: base_url}, opts \\ []) do
    http_post = Keyword.get(opts, :http_post, &default_http_post/2)
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    origin = String.trim_trailing(base_url, "/")
    endpoint = "#{origin}/api"

    body =
      Jason.encode!(%{
        "operationName" => "get_past_auctions",
        "query" => @past_auctions_query,
        "variables" => %{
          "pagination" => %{"page" => page, "pageSize" => page_size},
          "filter" => %{"auction_status" => [300]}
        }
      })

    with {:ok, resp_body} <- http_post.(endpoint, body),
         {:ok, decoded} <- Jason.decode(resp_body),
         auctions when is_list(auctions) <- get_in(decoded, ["data", "auctions", "auctions"]) do
      {:ok, auctions}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:ok, []}
      _ -> {:error, :invalid_auctions_json}
    end
  end

  def attrs_from_lot(lot) when is_map(lot) do
    lot = stringify_keys(lot)
    title = lot["title"] || ""
    description = lot["description_plain"] || ""
    status = lot["auction_lot_status"]
    price_type = if status in [200, "200"], do: "sale", else: "listing"

    amount =
      case lot["winning_bid_amount"] || lot["starting_bid"] do
        n when is_number(n) -> round(n * 100)
        _ -> nil
      end

    # Make/model/year come from the short lot title only — description text blows past varchar(255).
    labeled = parse_year_make_model(title)
    body = Enum.join([title, description], " ")

    %{
      "make" => labeled["make"],
      "model" => labeled["model"],
      "year" => labeled["year"],
      "miles" => parse_miles(body),
      "price_cents" => amount,
      "price_type" => price_type,
      "currency" => "USD",
      "notes" =>
        [title, lot["lot_number"] && "Lot #{lot["lot_number"]}", get_in(lot, ["auction", "title"])]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" — ")
        |> blank_to_nil(),
      "vin" => extract_vin(body)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  defp parse_year_make_model(text) do
    year =
      case Regex.run(~r/\b(19|20)\d{2}\b/, text) do
        [y | _] -> String.to_integer(y)
        _ -> nil
      end

    make_model =
      case Regex.run(~r/\b(?:19|20)\d{2}\s+([A-Za-z0-9\-]+)\s+(.+)$/u, text) do
        [_, make, model] ->
          {make, model |> clean_model_tail() |> truncate_field(255)}

        _ ->
          {nil, nil}
      end

    {make, model} = make_model

    %{"year" => year, "make" => make, "model" => model}
  end

  # Drop trailing auction junk if a long title somehow includes it.
  defp clean_model_tail(model) when is_binary(model) do
    model
    |> String.replace(
      ~r/\s+(?:VIN\s*#?|Odom(?:eter)?(?:\s*Reads)?|Miles|Mileage|Pwd\b|Powered\b).*$/i,
      ""
    )
    |> String.trim()
    |> blank_to_nil()
  end

  defp clean_model_tail(_), do: nil

  defp truncate_field(nil, _), do: nil
  defp truncate_field(value, max) when is_binary(value) and byte_size(value) <= max, do: value

  defp truncate_field(value, max) when is_binary(value) do
    value |> String.slice(0, max) |> String.trim()
  end

  defp truncate_field(value, _), do: value

  # Explicit unknown odometer (N/A, exempt, etc.) → 0 so digest can import as a market price.
  defp parse_miles(text) when is_binary(text) do
    cond do
      Regex.match?(
        ~r/(?:Miles|Mileage|Odom(?:eter)?(?:\s*Reads)?|title\s+odom(?:eter)?\s+reads)[:\s]+(?:N\/?A|n\/?a|NA|Exempt|Unknown|Not\s+Available)\b/i,
        text
      ) ->
        0

      true ->
        case Regex.run(~r/(?:Miles|Mileage|Odometer|Odom(?:\s*Reads)?)[:\s]+([\d,]+)/i, text) do
          [_, m] ->
            case Integer.parse(String.replace(m, ",", "")) do
              {n, _} -> n
              :error -> nil
            end

          _ ->
            nil
        end
    end
  end

  defp parse_miles(_), do: nil

  defp extract_vin(text) when is_binary(text) do
    case Regex.run(~r/\b([A-HJ-NPR-Z0-9]{17})\b/i, text) do
      [_, vin] -> String.upcase(vin)
      _ -> nil
    end
  end

  defp extract_vin(_), do: nil

  defp compact_lot(lot) when is_map(lot) do
    Map.take(lot, [
      "auction_lot_id",
      "lot_number",
      "title",
      "public_url",
      "auction_lot_status",
      "winning_bid_amount",
      "starting_bid",
      "auction"
    ])
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_nested(v)}
      {k, v} when is_binary(k) -> {k, stringify_nested(v)}
      {k, v} -> {to_string(k), stringify_nested(v)}
    end)
  end

  defp stringify_nested(v) when is_map(v), do: stringify_keys(v)
  defp stringify_nested(v), do: v

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp default_http_post(url, body) do
    headers = [
      {"Accept", "application/json"},
      {"Content-Type", "application/json"},
      {"User-Agent", "MechanicsPricingBot/1.0"}
    ]

    case Finch.build(:post, url, headers, body)
         |> Finch.request(Mechanics.Finch, receive_timeout: 15_000) do
      {:ok, %{status: status, body: resp}} when status in 200..299 -> {:ok, resp}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end
end
