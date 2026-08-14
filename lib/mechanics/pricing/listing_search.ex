defmodule Mechanics.Pricing.ListingSearch do
  @moduledoc """
  Auction sources, listing candidates (review queue), and multi-source search.
  """

  import Ecto.Query, warn: false

  alias Mechanics.Repo
  alias Mechanics.Pricing.AuctionSource
  alias Mechanics.Pricing.ListingCandidate
  alias Mechanics.Pricing.VehicleMarketPrice
  alias Mechanics.Pricing.Sources

  ## Auction sources

  def list_auction_sources(opts \\ []) do
    AuctionSource
    |> maybe_filter_enabled(Keyword.get(opts, :enabled))
    |> order_by([s], asc: s.label, asc: s.id)
    |> Repo.all()
  end

  def get_auction_source!(id), do: Repo.get!(AuctionSource, id)
  def get_auction_source(id), do: Repo.get(AuctionSource, id)

  def get_auction_source_by_base_url(base_url) when is_binary(base_url) do
    normalized = normalize_base_url(base_url)
    Repo.get_by(AuctionSource, base_url: normalized)
  end

  def create_auction_source(attrs) do
    %AuctionSource{}
    |> AuctionSource.changeset(attrs)
    |> Repo.insert()
  end

  def update_auction_source(%AuctionSource{} = source, attrs) do
    source
    |> AuctionSource.changeset(attrs)
    |> Repo.update()
  end

  def change_auction_source(%AuctionSource{} = source, attrs \\ %{}) do
    AuctionSource.changeset(source, attrs)
  end

  @doc """
  Origins from recent market-price source_urls that are not already auction_sources.
  """
  def suggest_auction_sources(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    existing = list_auction_sources() |> MapSet.new(& &1.base_url)

    from(v in VehicleMarketPrice,
      where: not is_nil(v.source_url) and v.source_url != "",
      order_by: [desc: v.inserted_at, desc: v.id],
      limit: 200,
      select: v.source_url
    )
    |> Repo.all()
    |> Enum.map(&origin_from_url/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(existing, &1))
    |> Enum.take(limit)
    |> Enum.map(fn base_url ->
      %{
        base_url: base_url,
        kind: Sources.infer_kind(base_url),
        label: default_label(base_url)
      }
    end)
  end

  ## Candidates

  def list_candidates(opts \\ []) do
    status = Keyword.get(opts, :status)
    query_text = Keyword.get(opts, :query)
    limit = Keyword.get(opts, :limit, 50)

    ListingCandidate
    |> maybe_filter_status(status)
    |> maybe_filter_query(query_text)
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_candidate!(id), do: Repo.get!(ListingCandidate, id)
  def get_candidate(id), do: Repo.get(ListingCandidate, id)

  def upsert_candidate(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)
    source_url = Map.get(attrs, "source_url") || Map.get(attrs, :source_url)

    case Repo.get_by(ListingCandidate, source_url: source_url) do
      nil ->
        %ListingCandidate{}
        |> ListingCandidate.changeset(attrs)
        |> Repo.insert()

      %ListingCandidate{} = existing ->
        existing
        |> ListingCandidate.changeset(Map.put(attrs, "status", existing.status))
        |> Repo.update()
    end
  end

  def dismiss_candidate(%ListingCandidate{} = candidate) do
    candidate
    |> ListingCandidate.changeset(%{status: "dismissed"})
    |> Repo.update()
  end

  def mark_candidate_imported(%ListingCandidate{} = candidate, market_price_id) do
    candidate
    |> ListingCandidate.changeset(%{
      status: "imported",
      vehicle_market_price_id: market_price_id
    })
    |> Repo.update()
  end

  def mark_candidate_failed(%ListingCandidate{} = candidate) do
    candidate
    |> ListingCandidate.changeset(%{status: "failed"})
    |> Repo.update()
  end

  ## Oban jobs (admin inspection)

  @doc """
  Recent Oban jobs, newest first. Optional `:queue` and `:limit`.
  """
  def list_oban_jobs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    queue = Keyword.get(opts, :queue)

    Oban.Job
    |> maybe_filter_queue(queue)
    |> order_by([j], desc: j.id)
    |> limit(^limit)
    |> Repo.all()
  end

  def get_oban_job!(id), do: Repo.get!(Oban.Job, id)

  @doc """
  Results for `/admin/jobs/:id`. Prefers `job.meta["results"]`, then auction sources
  linked by `config.last_crawl_job_id`, then sources crawled near the job timestamp,
  then digest outcome rebuilt from the candidate for DigestCandidateWorker jobs.
  """
  def results_for_oban_job(%Oban.Job{} = job) do
    cond do
      is_list(job.meta["results"]) ->
        job.meta["results"]

      crawl_worker?(job) ->
        case results_from_sources_for_job(job) do
          [] -> nil
          list -> list
        end

      digest_worker?(job) ->
        results_from_digest_job(job)

      true ->
        nil
    end
  end

  defp crawl_worker?(%Oban.Job{worker: worker}) when is_binary(worker) do
    String.ends_with?(worker, "CrawlPastAuctionsWorker")
  end

  defp crawl_worker?(_), do: false

  defp digest_worker?(%Oban.Job{worker: worker}) when is_binary(worker) do
    String.ends_with?(worker, "DigestCandidateWorker")
  end

  defp digest_worker?(_), do: false

  defp results_from_digest_job(%Oban.Job{args: args}) do
    case Map.get(args, "candidate_id") do
      id when is_binary(id) and id != "" ->
        case get_candidate(id) do
          %ListingCandidate{} = candidate ->
            [
              %{
                "kind" => "digest",
                "status" => candidate.status,
                "outcome" => candidate.status,
                "candidate_id" => to_string(candidate.id),
                "title" => candidate.title,
                "source_url" => candidate.source_url,
                "query" => candidate.query,
                "vehicle_market_price_id" =>
                  if(candidate.vehicle_market_price_id,
                    do: to_string(candidate.vehicle_market_price_id),
                    else: nil
                  )
              }
            ]

          nil ->
            [
              %{
                "kind" => "digest",
                "status" => "missing_candidate",
                "outcome" => "missing_candidate",
                "candidate_id" => id,
                "error" => "Candidate not found"
              }
            ]
        end

      _ ->
        nil
    end
  end

  defp results_from_sources_for_job(%Oban.Job{} = job) do
    job_id = to_string(job.id)

    linked =
      list_auction_sources()
      |> Enum.filter(fn source ->
        to_string(get_in(source.config || %{}, ["last_crawl_job_id"])) == job_id
      end)

    sources =
      if linked != [] do
        linked
      else
        list_auction_sources()
        |> Enum.filter(&source_crawled_near_job?(&1, job))
      end

    Enum.map(sources, &source_crawl_result/1)
  end

  defp source_crawled_near_job?(%{last_crawled_at: %DateTime{} = crawled}, job) do
    anchor = job.completed_at || job.discarded_at || job.attempted_at || job.inserted_at

    if match?(%DateTime{}, anchor) do
      abs(DateTime.diff(crawled, DateTime.truncate(anchor, :second), :second)) <= 180
    else
      false
    end
  end

  defp source_crawled_near_job?(_, _), do: false

  defp source_crawl_result(source) do
    config = source.config || %{}
    report = Map.get(config, "last_crawl_report") || %{}
    auctions = Map.get(config, "last_crawl_auctions")

    auctions =
      cond do
        is_list(auctions) ->
          auctions

        is_list(report["auction_ids"]) ->
          Enum.map(report["auction_ids"], fn id ->
            %{"auction_id" => to_string(id), "title" => nil, "auction_status" => nil, "end_time" => nil}
          end)

        true ->
          []
      end

    %{
      "source_id" => source.id,
      "label" => source.label,
      "base_url" => source.base_url,
      "status" => Map.get(report, "status") || "ok",
      "error" => Map.get(report, "error"),
      "at" => Map.get(report, "at"),
      "auction_count" => Map.get(report, "auction_count") || length(auctions),
      "auction_ids" => Map.get(report, "auction_ids") || Enum.map(auctions, & &1["auction_id"]),
      "auctions" => auctions
    }
  end

  @doc """
  Enqueue a past-auction crawl. Optional `source_id` limits to one Royal source.
  """
  def enqueue_crawl(opts \\ []) do
    args =
      case Keyword.get(opts, :source_id) do
        nil -> %{}
        source_id -> %{"source_id" => to_string(source_id)}
      end

    args
    |> Mechanics.Pricing.Workers.CrawlPastAuctionsWorker.new()
    |> Oban.insert()
  end

  @doc """
  Enqueue digest of a listing candidate into vehicle_market_prices.

  Schedules after the latest future digest/crawl job for the candidate's auction source (+30s).
  Pass `auction_source_id:` when known; otherwise loaded from the candidate.
  """
  def enqueue_digest(candidate_id, user_id, opts \\ []) do
    source_id =
      Keyword.get(opts, :auction_source_id) ||
        case get_candidate(candidate_id) do
          %{auction_source_id: id} -> id
          _ -> nil
        end

    args =
      %{
        "candidate_id" => to_string(candidate_id),
        "user_id" => to_string(user_id)
      }
      |> maybe_put_arg("auction_source_id", source_id)

    scheduled_at = next_scheduled_at(source_id)

    args
    |> Mechanics.Pricing.Workers.DigestCandidateWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  @doc """
  Enqueue a Royal auction-scoped lot search (paginated). Unique per source/auction/query/page.
  """
  def enqueue_lot_crawl(source, auction_id, query, user_id, opts \\ [])

  def enqueue_lot_crawl(%AuctionSource{kind: "royal"} = source, auction_id, query, user_id, opts) do
    page = Keyword.get(opts, :page, 1)

    args = %{
      "auction_source_id" => to_string(source.id),
      "auction_id" => to_string(auction_id),
      "query" => to_string(query),
      "user_id" => to_string(user_id),
      "page" => page
    }

    scheduled_at = next_scheduled_at(source.id)

    args
    |> Mechanics.Pricing.Workers.CrawlAuctionLotsWorker.new(scheduled_at: scheduled_at)
    |> Oban.insert()
  end

  def enqueue_lot_crawl(%AuctionSource{}, _auction_id, _query, _user_id, _opts),
    do: {:ok, :skipped_not_royal}

  def enqueue_lot_crawl(_, _, _, _, _), do: {:error, :invalid_source}

  @doc """
  Next `scheduled_at` for jobs tied to an auction source: max future on digest/crawl + 30s, or now.
  """
  def next_scheduled_at(nil), do: DateTime.utc_now() |> DateTime.truncate(:second)

  def next_scheduled_at(source_id) do
    source_id = to_string(source_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    stagger_seconds = 30

    max_at =
      from(j in Oban.Job,
        where: j.queue in ["digest", "crawl"],
        where: j.state in ["available", "scheduled", "executing"],
        where: fragment("?->>'auction_source_id' = ?", j.args, ^source_id),
        select: max(j.scheduled_at)
      )
      |> Repo.one()

    case max_at do
      %DateTime{} = at ->
        next = DateTime.add(at, stagger_seconds, :second)
        if DateTime.compare(next, now) == :lt, do: now, else: next

      _ ->
        now
    end
  end

  @doc """
  Retry a discarded / retryable / cancelled Oban job.
  """
  def retry_oban_job(id) when is_integer(id) do
    case get_oban_job!(id) do
      %Oban.Job{state: state} = job when state in ["discarded", "retryable", "cancelled", "completed"] ->
        Oban.retry_job(job)
        {:ok, get_oban_job!(id)}

      %Oban.Job{state: state} ->
        {:error, {:not_retryable, state}}
    end
  end

  def retry_oban_job(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> retry_oban_job(int)
      :error -> {:error, :invalid_id}
    end
  end

  @doc """
  Promote a scheduled/available/suspended job to run immediately (`available`, `scheduled_at` = now).
  Not for failed/finished jobs — use `retry_oban_job/1` for those.
  """
  def run_oban_job_now(id) when is_integer(id) do
    case get_oban_job!(id) do
      %Oban.Job{state: state} when state in ["discarded", "retryable", "cancelled", "completed", "executing"] ->
        {:error, {:not_runnable_now, state}}

      %Oban.Job{id: job_id} ->
        now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

        {count, _} =
          from(j in Oban.Job,
            where: j.id == ^job_id,
            where: j.state in ["scheduled", "available", "suspended"]
          )
          |> Repo.update_all(set: [state: "available", scheduled_at: now])

        if count == 1 do
          {:ok, get_oban_job!(job_id)}
        else
          {:error, :update_failed}
        end
    end
  end

  def run_oban_job_now(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, _} -> run_oban_job_now(int)
      :error -> {:error, :invalid_id}
    end
  end

  @search_max_pages 5
  @search_page_size 25

  @doc """
  Search enabled sources (or explicit `:sources` list) and upsert candidates.

  Paginates up to #{@search_max_pages} pages per source. Newly inserted candidates enqueue
  staggered digests; Royal hits with `auction_id` also enqueue lot-crawl.
  """
  def search(query, opts \\ []) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      {:error, :blank_query}
    else
      sources =
        Keyword.get_lazy(opts, :sources, fn -> list_auction_sources(enabled: true) end)

      user_id = resolve_digest_user_id(opts)

      results =
        Enum.flat_map(sources, fn source ->
          search_source_pages(source, query, user_id, opts)
        end)

      {:ok, results}
    end
  end

  defp search_source_pages(source, query, user_id, opts) do
    Enum.reduce_while(1..@search_max_pages, [], fn page, acc ->
      page_opts = Keyword.merge(opts, page: page, page_size: @search_page_size)

      case Sources.search(source, query, page_opts) do
        {:ok, hits} ->
          ingested = ingest_hits(source, query, hits, user_id)
          acc = acc ++ ingested

          if length(hits) < @search_page_size do
            {:halt, acc}
          else
            {:cont, acc}
          end

        {:error, _} ->
          {:halt, acc}
      end
    end)
  end

  @doc false
  def ingest_hits(source, query, hits, user_id) when is_list(hits) do
    Enum.flat_map(hits, fn hit ->
      attrs =
        hit
        |> Map.put("auction_source_id", source.id)
        |> Map.put("query", query)
        |> Map.put_new("status", "new")

      case upsert_candidate_action(attrs) do
        {:ok, candidate, :inserted} ->
          maybe_enqueue_after_insert(source, candidate, hit, user_id)
          [candidate]

        {:ok, candidate, :updated} ->
          [candidate]

        {:error, _} ->
          []
      end
    end)
  end

  defp upsert_candidate_action(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)
    source_url = Map.get(attrs, "source_url") || Map.get(attrs, :source_url)

    case Repo.get_by(ListingCandidate, source_url: source_url) do
      nil ->
        case %ListingCandidate{} |> ListingCandidate.changeset(attrs) |> Repo.insert() do
          {:ok, candidate} -> {:ok, candidate, :inserted}
          {:error, changeset} -> {:error, changeset}
        end

      %ListingCandidate{} = existing ->
        case existing
             |> ListingCandidate.changeset(Map.put(attrs, "status", existing.status))
             |> Repo.update() do
          {:ok, candidate} -> {:ok, candidate, :updated}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp maybe_enqueue_after_insert(source, candidate, hit, user_id) do
    if candidate.status == "new" and user_id do
      _ = enqueue_digest(candidate.id, user_id, auction_source_id: source.id)
    end

    auction_id = auction_id_from_hit(hit)

    if source.kind == "royal" and auction_id && user_id do
      _ = enqueue_lot_crawl(source, auction_id, candidate.query || "", user_id, page: 1)
    end

    :ok
  end

  defp auction_id_from_hit(hit) when is_map(hit) do
    raw = Map.get(hit, "raw") || Map.get(hit, :raw) || %{}

    cond do
      id = get_in(raw, ["auction", "auction_id"]) -> id
      id = Map.get(raw, "auction_id") -> id
      true -> nil
    end
    |> case do
      nil -> nil
      id -> to_string(id)
    end
  end

  defp resolve_digest_user_id(opts) do
    case Keyword.get(opts, :user_id) do
      nil -> default_digest_user_id()
      id -> to_string(id)
    end
  end

  defp default_digest_user_id do
    admin =
      from(u in Mechanics.Accounts.User,
        where: "admin" in u.roles,
        limit: 1
      )
      |> Repo.one()

    user =
      admin ||
        from(u in Mechanics.Accounts.User,
          where: "pricing_user" in u.roles,
          limit: 1
        )
        |> Repo.one()

    case user do
      %{id: id} -> to_string(id)
      _ -> nil
    end
  end

  defp maybe_put_arg(map, _key, nil), do: map
  defp maybe_put_arg(map, key, value), do: Map.put(map, key, to_string(value))

  @doc """
  Search enabled auction sources for a vehicle make/model (used by pricing agent tools).
  Returns candidate rows upserted into the review queue.
  """
  def search_for_vehicle(make, model, opts \\ []) do
    query =
      [make, model]
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(" ")

    search(query, opts)
  end

  @candidate_id_prefix "candidate:"

  def candidate_tool_id(%ListingCandidate{id: id}), do: @candidate_id_prefix <> to_string(id)

  def parse_candidate_tool_id(id) when is_binary(id) do
    case String.split(id, @candidate_id_prefix, parts: 2) do
      ["", uuid] when uuid != "" -> {:ok, uuid}
      _ -> :error
    end
  end

  def parse_candidate_tool_id(_), do: :error

  @doc """
  Compact tool rows for pricing agent search results (external auction hits).
  """
  def candidate_to_search_row(%ListingCandidate{} = candidate) do
    price = price_snapshot_from_raw(candidate.raw || %{})

    %{
      id: candidate_tool_id(candidate),
      make: price[:make],
      model: price[:model],
      year: price[:year],
      miles: price[:miles],
      zipcode: price[:zipcode],
      price_type: price[:price_type],
      source: "external",
      source_url: candidate.source_url,
      title: candidate.title
    }
  end

  @doc """
  Price details for candidate tool ids (`candidate:<uuid>`), for get_vehicle_market_price_details.
  """
  def get_candidate_price_details(ids) when is_list(ids) do
    ids
    |> Enum.map(&parse_candidate_tool_id/1)
    |> Enum.flat_map(fn
      {:ok, uuid} ->
        case get_candidate(uuid) do
          %ListingCandidate{} = candidate -> [candidate_detail_row(candidate)]
          nil -> []
        end

      :error ->
        []
    end)
  end

  defp candidate_detail_row(%ListingCandidate{} = candidate) do
    price = price_snapshot_from_raw(candidate.raw || %{})

    %{
      id: candidate_tool_id(candidate),
      price_cents: price[:price_cents],
      currency: price[:currency] || "USD",
      price_type: price[:price_type],
      year: price[:year],
      miles: price[:miles],
      make: price[:make],
      model: price[:model],
      source: "external",
      source_url: candidate.source_url,
      title: candidate.title
    }
  end

  defp price_snapshot_from_raw(raw) when is_map(raw) do
    raw = stringify_keys(raw)

    cond do
      # Royal lot shape
      Map.has_key?(raw, "auction_lot_id") or Map.has_key?(raw, "winning_bid_amount") ->
        status = Map.get(raw, "auction_lot_status")
        amount = Map.get(raw, "winning_bid_amount") || Map.get(raw, "starting_bid")
        title = Map.get(raw, "title") || ""

        %{
          price_cents: dollars_to_cents(amount),
          price_type: if(status in [200, "200"], do: "sale", else: "listing"),
          currency: "USD",
          year: year_from_title(title),
          make: make_from_title(title),
          model: model_from_title(title),
          miles: nil,
          zipcode: nil
        }

      # BidWrangler item shape
      true ->
        status = Map.get(raw, "status")
        amount =
          get_in(raw, ["api_bidding_state", "closing_bid", "amount"]) ||
            get_in(raw, ["api_bidding_state", "high", "amount"]) ||
            Map.get(raw, "listing_price")

        name = Map.get(raw, "name") || ""

        %{
          price_cents: dollars_to_cents(amount),
          price_type: if(status == "sold", do: "sale", else: "listing"),
          currency: Map.get(raw, "currency_name") || "USD",
          year: year_from_title(name),
          make: make_from_title(name),
          model: model_from_title(name),
          miles: nil,
          zipcode: nil
        }
    end
  end

  defp dollars_to_cents(amount) when is_integer(amount), do: amount * 100
  defp dollars_to_cents(amount) when is_float(amount), do: round(amount * 100)
  defp dollars_to_cents(_), do: nil

  defp year_from_title(title) when is_binary(title) do
    case Regex.run(~r/\b((?:19|20)\d{2})\b/, title) do
      [_, y] -> String.to_integer(y)
      _ -> nil
    end
  end

  defp year_from_title(_), do: nil

  defp make_from_title(title) when is_binary(title) do
    case Regex.run(~r/\b(?:19|20)\d{2}\s+([A-Za-z0-9\-]+)/, title) do
      [_, make] -> make
      _ -> nil
    end
  end

  defp make_from_title(_), do: nil

  defp model_from_title(title) when is_binary(title) do
    case Regex.run(~r/\b(?:19|20)\d{2}\s+[A-Za-z0-9\-]+\s+(.+)$/, title) do
      [_, model] -> String.trim(model)
      _ -> nil
    end
  end

  defp model_from_title(_), do: nil

  def normalize_base_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.replace_trailing("/", "")
  end

  def normalize_base_url(_), do: ""

  def origin_from_url(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    if uri.scheme in ["http", "https"] and is_binary(uri.host) and uri.host != "" do
      "#{uri.scheme}://#{uri.host}"
    else
      nil
    end
  end

  def origin_from_url(_), do: nil

  defp default_label(base_url) do
    case URI.parse(base_url) do
      %URI{host: host} when is_binary(host) -> host
      _ -> base_url
    end
  end

  defp maybe_filter_enabled(query, nil), do: query
  defp maybe_filter_enabled(query, true), do: where(query, [s], s.enabled == true)
  defp maybe_filter_enabled(query, false), do: where(query, [s], s.enabled == false)

  defp maybe_filter_queue(query, nil), do: query
  defp maybe_filter_queue(query, queue), do: where(query, [j], j.queue == ^queue)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, status), do: where(query, [c], c.status == ^status)

  defp maybe_filter_query(query, nil), do: query
  defp maybe_filter_query(query, ""), do: query
  defp maybe_filter_query(query, text), do: where(query, [c], c.query == ^text)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
