defmodule Mechanics.Pricing.Workers.CrawlAuctionLotsWorker do
  @moduledoc """
  Searches lots within a Royal auction for a text query, upserts listing_candidates,
  and chains pages (max 5) with per-source stagger.
  """

  use Oban.Worker,
    queue: :crawl,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:args, :worker],
      keys: [:auction_source_id, :auction_id, :query, :page],
      states: Oban.Job.unique_states(:incomplete) ++ [:completed]
    ]

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Pricing.Sources
  alias Mechanics.Repo

  @max_pages 5
  @page_size 25

  @impl Oban.Worker
  def perform(%Oban.Job{} = job), do: run(job, [])

  @doc false
  def run(%Oban.Job{args: args} = job, opts) when is_list(opts) do
    source_id = Map.get(args, "auction_source_id")
    auction_id = Map.get(args, "auction_id")
    query = Map.get(args, "query") || ""
    user_id = Map.get(args, "user_id")
    page = parse_page(Map.get(args, "page", 1))

    source = ListingSearch.get_auction_source(source_id)

    cond do
      is_nil(source) ->
        {:cancel, :source_not_found}

      source.kind != "royal" ->
        {:cancel, :not_royal}

      true ->
        search_opts =
          Keyword.merge(opts,
            page: page,
            page_size: @page_size,
            auction_id: auction_id
          )

        case Sources.search(source, query, search_opts) do
          {:ok, hits} ->
            candidates = ListingSearch.ingest_hits(source, query, hits, user_id)
            report = %{
              "status" => "ok",
              "page" => page,
              "hit_count" => length(hits),
              "inserted_or_updated" => length(candidates)
            }

            persist_meta(job, report)

            if length(hits) >= @page_size and page < @max_pages do
              ListingSearch.enqueue_lot_crawl(source, auction_id, query, user_id, page: page + 1)
            end

            :ok

          {:error, reason} ->
            Logger.warning("CrawlAuctionLotsWorker failed: #{inspect(reason)}")
            persist_meta(job, %{"status" => "error", "page" => page, "error" => inspect(reason)})
            {:error, reason}
        end
    end
  end

  defp parse_page(page) when is_integer(page) and page > 0, do: page

  defp parse_page(page) when is_binary(page) do
    case Integer.parse(page) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  defp parse_page(_), do: 1

  defp persist_meta(%Oban.Job{id: nil}, _report), do: :ok

  defp persist_meta(%Oban.Job{id: id, meta: meta}, report) do
    meta = Map.merge(meta || %{}, %{"results" => [report]})

    {count, _} =
      from(j in Oban.Job, where: j.id == ^id)
      |> Repo.update_all(set: [meta: meta])

    if count != 1 do
      Logger.warning("CrawlAuctionLotsWorker meta update affected #{count} rows for job #{id}")
    end

    :ok
  end
end
