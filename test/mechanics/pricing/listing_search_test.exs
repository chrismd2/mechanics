defmodule Mechanics.Pricing.ListingSearchTest do
  use Mechanics.DataCase, async: false

  import Ecto.Query

  alias Mechanics.Accounts
  alias Mechanics.Pricing
  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Repo

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
    user = pricing_user!()

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
               http_get: http_get,
               user_id: user.id
             )

    assert candidate.source_url == "https://bid.example.com/ui/auctions/7/99"
    assert candidate.title == "2018 Ford F450"
    assert candidate.status == "new"
  end

  test "new search candidate enqueues staggered digest; re-search does not" do
    user = pricing_user!()

    {:ok, source} =
      ListingSearch.create_auction_source(%{
        "kind" => "bidwrangler",
        "base_url" => "https://bid.stagger-#{System.unique_integer([:positive])}.test",
        "label" => "Stagger Bid"
      })

    http_get = fn _url ->
      {:ok,
       Jason.encode!(%{
         "items" => [
           %{"id" => 1, "auction_id" => 10, "name" => "2018 Ford F450", "status" => "sold"},
           %{"id" => 2, "auction_id" => 10, "name" => "2019 Ford F450", "status" => "sold"}
         ]
       })}
    end

    assert {:ok, [c1, c2]} =
             ListingSearch.search("ford f450",
               sources: [source],
               http_get: http_get,
               user_id: user.id
             )

    digest_jobs =
      Oban.Job
      |> where([j], j.worker == "Mechanics.Pricing.Workers.DigestCandidateWorker")
      |> where([j], fragment("?->>'auction_source_id' = ?", j.args, ^to_string(source.id)))
      |> order_by([j], asc: j.scheduled_at)
      |> Repo.all()

    assert length(digest_jobs) == 2
    [j1, j2] = digest_jobs
    assert DateTime.diff(j2.scheduled_at, j1.scheduled_at, :second) >= 30
    assert Enum.map(digest_jobs, & &1.args["candidate_id"]) |> Enum.sort() ==
             Enum.sort([to_string(c1.id), to_string(c2.id)])

    # BidWrangler auction_id must not enqueue Royal lot-crawl
    lot_jobs =
      Oban.Job
      |> where([j], j.worker == "Mechanics.Pricing.Workers.CrawlAuctionLotsWorker")
      |> Repo.all()

    assert lot_jobs == []

    assert {:ok, _} =
             ListingSearch.search("ford f450",
               sources: [source],
               http_get: http_get,
               user_id: user.id
             )

    digest_after =
      Oban.Job
      |> where([j], j.worker == "Mechanics.Pricing.Workers.DigestCandidateWorker")
      |> where([j], fragment("?->>'auction_source_id' = ?", j.args, ^to_string(source.id)))
      |> Repo.all()

    assert length(digest_after) == 2
  end

  test "royal search hit with auction_id enqueues unique lot-crawl job" do
    user = pricing_user!()

    {:ok, source} =
      ListingSearch.create_auction_source(%{
        "kind" => "royal",
        "base_url" => "https://live.royal-#{System.unique_integer([:positive])}.test",
        "label" => "Royal Test",
        "enabled" => true
      })

    http_post = fn _url, body ->
      assert String.contains?(body, "get_lots_search")

      {:ok,
       Jason.encode!(%{
         "data" => %{
           "lots" => %{
             "total" => 1,
             "lots" => [
               %{
                 "auction_lot_id" => "28748",
                 "title" => "2002 International 4300",
                 "auction_lot_status" => 200,
                 "auction" => %{"auction_id" => 6305, "title" => "Tampa"}
               }
             ]
           }
         }
       })}
    end

    assert {:ok, [_candidate]} =
             ListingSearch.search("International 4300",
               sources: [source],
               http_post: http_post,
               user_id: user.id
             )

    lot_jobs =
      Oban.Job
      |> where([j], j.worker == "Mechanics.Pricing.Workers.CrawlAuctionLotsWorker")
      |> where([j], fragment("?->>'auction_id' = ?", j.args, ^"6305"))
      |> Repo.all()

    assert length(lot_jobs) == 1
    assert hd(lot_jobs).args["query"] == "International 4300"
    assert hd(lot_jobs).args["auction_source_id"] == to_string(source.id)

    assert {:ok, _} =
             ListingSearch.search("International 4300",
               sources: [source],
               http_post: http_post,
               user_id: user.id
             )

    lot_after =
      Oban.Job
      |> where([j], j.worker == "Mechanics.Pricing.Workers.CrawlAuctionLotsWorker")
      |> where([j], fragment("?->>'auction_id' = ?", j.args, ^"6305"))
      |> Repo.all()

    assert length(lot_after) == 1
  end

  test "paginate_oban_jobs returns newest-first pages" do
    for i <- 1..7 do
      assert {:ok, _} =
               %{"n" => i}
               |> Mechanics.Pricing.Workers.CrawlPastAuctionsWorker.new()
               |> Oban.insert()
    end

    page1 = ListingSearch.paginate_oban_jobs(page: 1, page_size: 5, queue: "crawl")
    assert length(page1.entries) == 5
    assert page1.page == 1
    assert page1.page_size == 5
    assert page1.total_count >= 7
    assert page1.total_pages >= 2

    page2 = ListingSearch.paginate_oban_jobs(page: 2, page_size: 5, queue: "crawl")
    assert page2.entries != []
    page1_ids = MapSet.new(page1.entries, & &1.id)
    refute Enum.any?(page2.entries, &MapSet.member?(page1_ids, &1.id))
    assert hd(page1.entries).id > hd(page2.entries).id

    clamped = ListingSearch.paginate_oban_jobs(page: 0, page_size: 5, queue: "crawl")
    assert clamped.page == 1
  end
end
