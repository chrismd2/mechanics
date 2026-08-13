defmodule Mechanics.Pricing.Workers.CrawlPastAuctionsWorker do
  @moduledoc """
  Periodically lists past Royal auctions for enabled sources and records crawl time.
  Does not dump full lot catalogs; optional bounded search enqueue stays light.

  Args (optional):
  - `source_id` — crawl only that auction source (must be enabled Royal).

  On each attempt, writes `meta["results"]` on the Oban job (per-source auction lists)
  so `/admin/jobs/:id` can display what was found.
  """

  use Oban.Worker, queue: :crawl, max_attempts: 3

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Mechanics.Repo
  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Pricing.Sources.Royal, as: RoyalSource

  @impl Oban.Worker
  def perform(%Oban.Job{args: args} = job) do
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

    reports = Enum.map(sources, &crawl_source(&1, job.id))
    persist_job_results(job, reports)

    ok_count = Enum.count(reports, &(&1["status"] == "ok"))
    err_count = length(reports) - ok_count

    Logger.info("Royal past-auction crawl finished: #{ok_count} ok, #{err_count} errors")

    if err_count > 0 and ok_count == 0 and reports != [] do
      {:error, :all_crawls_failed}
    else
      :ok
    end
  end

  defp crawl_source(source, job_id) do
    base = %{
      "source_id" => source.id,
      "label" => source.label,
      "base_url" => source.base_url,
      "at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }

    case RoyalSource.list_past_auctions(source, page: 1, page_size: 25) do
      {:ok, auctions} ->
        auction_rows = Enum.map(auctions, &compact_auction/1)
        auction_ids = Enum.map(auction_rows, & &1["auction_id"])

        report =
          Map.merge(base, %{
            "status" => "ok",
            "auction_count" => length(auction_rows),
            "auction_ids" => auction_ids,
            "auctions" => auction_rows
          })

        Logger.info(
          "Royal past-auction crawl for #{source.base_url}: #{length(auction_rows)} auctions"
        )

        ListingSearch.update_auction_source(source, %{
          last_crawled_at: DateTime.utc_now() |> DateTime.truncate(:second),
          config:
            Map.merge(source.config || %{}, %{
              "last_past_auction_ids" => auction_ids,
              "last_crawl_report" => Map.drop(report, ["auctions"]),
              "last_crawl_auctions" => auction_rows,
              "last_crawl_job_id" => job_id
            })
        })

        report

      {:error, reason} ->
        report =
          Map.merge(base, %{
            "status" => "error",
            "error" => inspect(reason),
            "auction_count" => 0,
            "auction_ids" => [],
            "auctions" => []
          })

        Logger.warning(
          "Royal past-auction crawl failed for #{source.base_url}: #{inspect(reason)}"
        )

        ListingSearch.update_auction_source(source, %{
          config:
            Map.merge(source.config || %{}, %{
              "last_crawl_report" => Map.drop(report, ["auctions"]),
              "last_crawl_auctions" => [],
              "last_crawl_job_id" => job_id
            })
        })

        report
    end
  end

  defp compact_auction(auction) when is_map(auction) do
    %{
      "auction_id" => to_string(Map.get(auction, "auction_id")),
      "title" => Map.get(auction, "title"),
      "auction_status" => Map.get(auction, "auction_status"),
      "end_time" => Map.get(auction, "end_time") || Map.get(auction, "start_time")
    }
  end

  defp persist_job_results(%Oban.Job{id: id, meta: meta}, reports) do
    new_meta = Map.merge(meta || %{}, %{"results" => reports})

    {count, _} =
      from(j in Oban.Job, where: j.id == ^id)
      |> Repo.update_all(set: [meta: new_meta])

    if count != 1 do
      Logger.warning("Crawl results not saved on oban job #{id} (updated #{count} rows)")
    end

    :ok
  end
end
