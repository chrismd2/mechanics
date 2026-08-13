defmodule Mechanics.Pricing.Workers.CrawlPastAuctionsWorker do
  @moduledoc """
  Periodically lists past Royal auctions for enabled sources and records crawl time.
  Does not dump full lot catalogs; optional bounded search enqueue stays light.

  Args (optional):
  - `source_id` — crawl only that auction source (must be enabled Royal).
  """

  use Oban.Worker, queue: :crawl, max_attempts: 3

  require Logger

  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Pricing.Sources.Royal, as: RoyalSource

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    sources =
      case Map.get(args, "source_id") do
        nil ->
          ListingSearch.list_auction_sources(enabled: true)
          |> Enum.filter(&(&1.kind == "royal"))

        source_id ->
          case ListingSearch.get_auction_source(source_id) do
            %{kind: "royal", enabled: true} = source -> [source]
            _ -> []
          end
      end

    reports = Enum.map(sources, &crawl_source/1)
    ok_count = Enum.count(reports, &match?({:ok, _}, &1))
    err_count = length(reports) - ok_count

    Logger.info("Royal past-auction crawl finished: #{ok_count} ok, #{err_count} errors")

    if err_count > 0 and ok_count == 0 and reports != [] do
      {:error, :all_crawls_failed}
    else
      :ok
    end
  end

  defp crawl_source(source) do
    case RoyalSource.list_past_auctions(source, page: 1, page_size: 25) do
      {:ok, auctions} ->
        auction_ids =
          auctions
          |> Enum.map(&to_string(Map.get(&1, "auction_id")))
          |> Enum.take(50)

        report = %{
          "at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          "auction_count" => length(auctions),
          "auction_ids" => auction_ids,
          "status" => "ok"
        }

        Logger.info(
          "Royal past-auction crawl for #{source.base_url}: #{length(auctions)} auctions"
        )

        ListingSearch.update_auction_source(source, %{
          last_crawled_at: DateTime.utc_now() |> DateTime.truncate(:second),
          config:
            Map.merge(source.config || %{}, %{
              "last_past_auction_ids" => auction_ids,
              "last_crawl_report" => report
            })
        })

        {:ok, report}

      {:error, reason} ->
        report = %{
          "at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          "status" => "error",
          "error" => inspect(reason)
        }

        Logger.warning(
          "Royal past-auction crawl failed for #{source.base_url}: #{inspect(reason)}"
        )

        ListingSearch.update_auction_source(source, %{
          config: Map.merge(source.config || %{}, %{"last_crawl_report" => report})
        })

        {:error, reason}
    end
  end
end
