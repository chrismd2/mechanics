defmodule Mechanics.Pricing.Workers.CrawlAuctionLotsWorkerTest do
  use Mechanics.DataCase, async: false

  import Ecto.Query

  alias Mechanics.Accounts
  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Pricing.Workers.CrawlAuctionLotsWorker
  alias Mechanics.Repo

  defp pricing_user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        "email" => "lot-crawl-#{suffix}@example.com",
        "name" => "Lot Crawl",
        "roles" => ["customer", "pricing_user"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user
  end

  test "cancels for non-royal sources" do
    user = pricing_user!()

    {:ok, source} =
      ListingSearch.create_auction_source(%{
        "kind" => "bidwrangler",
        "base_url" => "https://bid.lot-#{System.unique_integer([:positive])}.test",
        "label" => "BW"
      })

    assert {:cancel, :not_royal} =
             CrawlAuctionLotsWorker.perform(%Oban.Job{
               args: %{
                 "auction_source_id" => source.id,
                 "auction_id" => "1",
                 "query" => "ford",
                 "user_id" => user.id,
                 "page" => 1
               }
             })
  end

  test "searches auction with filter and chains next page when full" do
    user = pricing_user!()

    {:ok, source} =
      ListingSearch.create_auction_source(%{
        "kind" => "royal",
        "base_url" => "https://live.lot-#{System.unique_integer([:positive])}.test",
        "label" => "Royal Lot",
        "enabled" => true
      })

    page_size = 25

    lots =
      Enum.map(1..page_size, fn i ->
        %{
          "auction_lot_id" => to_string(10_000 + i),
          "title" => "2002 International 4300 ##{i}",
          "auction_lot_status" => 200,
          "auction" => %{"auction_id" => 6305, "title" => "Tampa"}
        }
      end)

    http_post = fn _url, body ->
      {:ok, decoded} = Jason.decode(body)
      filter = get_in(decoded, ["variables", "filter"]) || %{}
      assert to_string(Map.get(filter, "auction_id")) == "6305"
      assert get_in(decoded, ["variables", "search", "text"]) == "International 4300"
      assert get_in(decoded, ["variables", "pagination", "page"]) == 1

      {:ok, Jason.encode!(%{"data" => %{"lots" => %{"total" => page_size, "lots" => lots}}})}
    end

    job = %Oban.Job{
      id: System.unique_integer([:positive]),
      args: %{
        "auction_source_id" => source.id,
        "auction_id" => "6305",
        "query" => "International 4300",
        "user_id" => user.id,
        "page" => 1
      },
      meta: %{}
    }

    assert :ok = CrawlAuctionLotsWorker.run(job, http_post: http_post)

    candidates = ListingSearch.list_candidates(query: "International 4300", limit: 100)
    assert length(candidates) == page_size

    page2 =
      Oban.Job
      |> where([j], j.worker == "Mechanics.Pricing.Workers.CrawlAuctionLotsWorker")
      |> where([j], fragment("(?->>'page')::int = 2", j.args))
      |> where([j], fragment("?->>'auction_id' = ?", j.args, ^"6305"))
      |> Repo.all()

    assert length(page2) == 1
  end
end
