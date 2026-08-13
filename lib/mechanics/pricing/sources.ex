defmodule Mechanics.Pricing.Sources do
  @moduledoc """
  Multi-source listing search adapters (BidWrangler, Royal, Craigslist stub).
  """

  alias Mechanics.Pricing.AuctionSource
  alias Mechanics.Pricing.Sources.BidWrangler, as: BidWranglerSource
  alias Mechanics.Pricing.Sources.Royal, as: RoyalSource
  alias Mechanics.Pricing.Sources.Craigslist, as: CraigslistSource

  @callback search(AuctionSource.t(), String.t(), keyword()) ::
              {:ok, [map()]} | {:error, term()}

  @callback fetch_detail(String.t(), keyword()) :: {:ok, map()} | {:error, term()}

  def search(%AuctionSource{} = source, query, opts \\ []) when is_binary(query) do
    adapter_for(source.kind).search(source, query, opts)
  end

  def fetch_detail(kind, url_or_id, opts \\ []) when is_binary(kind) and is_binary(url_or_id) do
    adapter_for(kind).fetch_detail(url_or_id, opts)
  end

  def infer_kind(base_url) when is_binary(base_url) do
    host = base_url |> URI.parse() |> Map.get(:host) |> to_string() |> String.downcase()

    cond do
      String.contains?(host, "royalauction") -> "royal"
      String.contains?(host, "craigslist") -> "craigslist"
      String.contains?(host, "bid.") or String.contains?(host, "bidwrangler") -> "bidwrangler"
      true -> "unknown"
    end
  end

  def infer_kind(_), do: "unknown"

  defp adapter_for("bidwrangler"), do: BidWranglerSource
  defp adapter_for("royal"), do: RoyalSource
  defp adapter_for("craigslist"), do: CraigslistSource
  defp adapter_for(_), do: CraigslistSource
end
