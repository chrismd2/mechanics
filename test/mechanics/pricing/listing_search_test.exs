defmodule Mechanics.Pricing.ListingSearchTest do
  use Mechanics.DataCase, async: false

  alias Mechanics.Accounts
  alias Mechanics.Pricing
  alias Mechanics.Pricing.ListingSearch

  defp pricing_user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        "email" => "listing-search-#{suffix}@example.com",
        "name" => "Listing Search",
        "roles" => ["customer", "pricing_user"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user
  end

  test "creates and lists auction sources" do
    assert {:ok, source} =
             ListingSearch.create_auction_source(%{
               "kind" => "bidwrangler",
               "base_url" => "https://bid.example.com/",
               "label" => "Example Bid"
             })

    assert source.base_url == "https://bid.example.com"
    assert [%{id: id}] = ListingSearch.list_auction_sources(enabled: true)
    assert id == source.id
  end

  test "suggest_auction_sources returns origins not already stored" do
    user = pricing_user!()

    {:ok, _} =
      Pricing.create_market_price(user, %{
        "make" => "Ford",
        "model" => "F450",
        "year" => 2015,
        "miles" => 100_000,
        "price_cents" => 2_000_000,
        "price_type" => "listing",
        "source_url" => "https://bid.powellauctions.com/ui/auctions/1/2"
      })

    suggestions = ListingSearch.suggest_auction_sources()
    assert Enum.any?(suggestions, &(&1.base_url == "https://bid.powellauctions.com"))

    {:ok, _} =
      ListingSearch.create_auction_source(%{
        "kind" => "bidwrangler",
        "base_url" => "https://bid.powellauctions.com",
        "label" => "Powell"
      })

    suggestions = ListingSearch.suggest_auction_sources()
    refute Enum.any?(suggestions, &(&1.base_url == "https://bid.powellauctions.com"))
  end

  test "search upserts candidates from adapters" do
    {:ok, source} =
      ListingSearch.create_auction_source(%{
        "kind" => "bidwrangler",
        "base_url" => "https://bid.example.com",
        "label" => "Example"
      })

    http_get = fn url ->
      assert String.contains?(url, "/api/items/search?query=ford")
      refute String.contains?(url, "/api/auctions/")

      {:ok,
       Jason.encode!(%{
         "total" => 1,
         "page" => 1,
         "per_page" => 50,
         "items" => [
           %{
             "id" => 99,
             "auction_id" => 7,
             "name" => "2018 Ford F450",
             "status" => "sold"
           }
         ]
       })}
    end

    assert {:ok, [candidate]} =
             ListingSearch.search("ford f450",
               sources: [source],
               http_get: http_get
             )

    assert candidate.source_url == "https://bid.example.com/ui/auctions/7/99"
    assert candidate.title == "2018 Ford F450"
    assert candidate.status == "new"
  end
end
