defmodule Mechanics.Pricing.BidWrangler do
  @moduledoc """
  BidWrangler auction item helpers for market-price URL import.

  UI item pages (`/ui/auctions/:auction_id/:item_id`) are JS shells. Import uses
  `{origin}/api/items/:item_id` only — never the multi-MB `/api/auctions/:id` catalog.
  """

  @ui_item_path ~r{\A(?<origin>https?://[^/]+)/ui/auctions/(?<auction_id>\d+)/(?<item_id>\d+)/?\z}i

  @doc """
  Parse a BidWrangler UI item URL into origin, auction_id, and item_id.
  """
  def parse_item_ui_url(url) when is_binary(url) do
    case Regex.named_captures(@ui_item_path, String.trim(url)) do
      %{"origin" => origin, "auction_id" => auction_id, "item_id" => item_id} ->
        {:ok, %{origin: origin, auction_id: auction_id, item_id: item_id}}

      _ ->
        :error
    end
  end

  def parse_item_ui_url(_), do: :error

  @doc """
  Return `{origin}/api/items/:item_id` for a UI item URL, or nil if not matched.
  """
  def item_api_url(url) when is_binary(url) do
    case parse_item_ui_url(url) do
      {:ok, %{origin: origin, item_id: item_id}} -> "#{origin}/api/items/#{item_id}"
      :error -> nil
    end
  end

  def item_api_url(_), do: nil

  @doc """
  Deterministically map a BidWrangler item JSON object to market-price attrs (string keys).
  """
  def attrs_from_item(item) when is_map(item) do
    item = stringify_keys(item)
    description = description_text(item)
    labeled = parse_labeled_fields(description)

    price_type = if item["status"] == "sold", do: "sale", else: "listing"
    price_cents = price_cents_from_item(item, price_type)

    %{
      "make" => blank_to_nil(labeled["make"]),
      "model" => blank_to_nil(labeled["model"]),
      "year" => labeled["year"],
      "miles" => labeled["miles"],
      "vin" => blank_to_nil(item["vin"]) || blank_to_nil(labeled["vin"]),
      "zipcode" => first_zip(description) || first_zip(item["location_str"]),
      "price_cents" => price_cents,
      "currency" => blank_to_nil(item["currency_name"]) || "USD",
      "price_type" => price_type,
      "notes" => notes_from_item(item)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Map.new()
  end

  @doc """
  Compact plain-text summary for LLM fallback (no images / schedules / large blobs).
  """
  def compact_summary(item) when is_map(item) do
    item = stringify_keys(item)
    amount = bid_amount_dollars(item)
    description = description_text(item)

    lines =
      [
        optional_line("Name", item["name"]),
        optional_line("VIN", item["vin"]),
        optional_line("Status", item["status"]),
        optional_line("Currency", item["currency_name"] || "USD"),
        optional_line("Lot", item["simple_id"] || item["lot_identifier"]),
        optional_line("Auction", item["auction_name"]),
        optional_line("Location", item["location_str"]),
        optional_line("Bid/sale amount (dollars)", amount && to_string(amount)),
        optional_line("Listing price (dollars)", item["listing_price"] && to_string(item["listing_price"]))
      ]
      |> Enum.reject(&is_nil/1)

    (lines ++ ["Description:", description])
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join("\n")
    |> String.slice(0, 8_000)
  end

  defp optional_line(_label, nil), do: nil
  defp optional_line(_label, ""), do: nil
  defp optional_line(label, value), do: "#{label}: #{value}"

  @doc """
  Whether extract attrs have the fields needed to skip the LLM (source_url added later).
  """
  def complete_extract_attrs?(attrs) when is_map(attrs) do
    required = ["make", "model", "year", "miles", "price_cents", "price_type"]

    Enum.all?(required, fn key ->
      value = Map.get(attrs, key)
      not is_nil(value) and value != ""
    end)
  end

  defp price_cents_from_item(item, "sale") do
    case get_in(item, ["api_bidding_state", "closing_bid", "amount"]) ||
           get_in(item, ["api_bidding_state", "high", "amount"]) do
      amount when is_number(amount) -> dollars_to_cents(amount)
      _ -> nil
    end
  end

  defp price_cents_from_item(item, _price_type) do
    cond do
      is_number(item["listing_price"]) ->
        dollars_to_cents(item["listing_price"])

      is_number(get_in(item, ["api_bidding_state", "high", "amount"])) ->
        dollars_to_cents(get_in(item, ["api_bidding_state", "high", "amount"]))

      true ->
        nil
    end
  end

  defp bid_amount_dollars(item) do
    get_in(item, ["api_bidding_state", "closing_bid", "amount"]) ||
      get_in(item, ["api_bidding_state", "high", "amount"])
  end

  defp dollars_to_cents(amount) when is_integer(amount), do: amount * 100
  defp dollars_to_cents(amount) when is_float(amount), do: round(amount * 100)

  defp description_text(item) do
    item["description_without_html"] || item["simple_description"] || ""
  end

  defp notes_from_item(item) do
    [
      item["name"],
      item["simple_id"] || item["lot_identifier"],
      item["auction_name"]
    ]
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" — ")
    |> blank_to_nil()
  end

  defp parse_labeled_fields(text) when is_binary(text) do
    %{
      "year" => parse_int_label(text, "Year"),
      "make" => parse_string_label(text, "Make"),
      "model" => parse_string_label(text, "Model"),
      "miles" => parse_int_label(text, "Mileage") || parse_int_label(text, "Miles"),
      "vin" => parse_string_label(text, "VIN #") || parse_string_label(text, "VIN")
    }
  end

  defp parse_string_label(text, label) do
    pattern =
      ~r/#{Regex.escape(label)}\s*:\s*(.+?)(?=\s+(?:Year|Make|Model|Mileage|Miles|VIN\s*#?|Vehicle|Body|Engine|Fuel|Horsepower|Transmission|Features)\b|$)/i

    case Regex.run(pattern, text) do
      [_, value] -> value |> String.trim() |> blank_to_nil()
      _ -> nil
    end
  end

  defp parse_int_label(text, label) do
    case parse_string_label(text, label) do
      nil ->
        nil

      value ->
        if Regex.match?(~r/\A(?:N\/?A|n\/?a|NA|Exempt|Unknown|Not\s+Available)\z/i, String.trim(value)) do
          0
        else
          digits = String.replace(value, ~r/[^\d]/, "")

          case Integer.parse(digits) do
            {n, _} -> n
            :error -> nil
          end
        end
    end
  end

  defp first_zip(nil), do: nil

  defp first_zip(text) when is_binary(text) do
    case Regex.run(~r/\b(\d{5})(?:-\d{4})?\b/, text) do
      [_, zip] -> zip
      _ -> nil
    end
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
end
