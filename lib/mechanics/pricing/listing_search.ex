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
  """
  def enqueue_digest(candidate_id, user_id) do
    %{
      "candidate_id" => to_string(candidate_id),
      "user_id" => to_string(user_id)
    }
    |> Mechanics.Pricing.Workers.DigestCandidateWorker.new()
    |> Oban.insert()
  end

  @doc """
  Search enabled sources (or explicit `:sources` list) and upsert candidates.
  """
  def search(query, opts \\ []) when is_binary(query) do
    query = String.trim(query)

    if query == "" do
      {:error, :blank_query}
    else
      sources =
        Keyword.get_lazy(opts, :sources, fn -> list_auction_sources(enabled: true) end)

      results =
        Enum.flat_map(sources, fn source ->
          case Sources.search(source, query, opts) do
            {:ok, hits} ->
              Enum.map(hits, fn hit ->
                attrs =
                  hit
                  |> Map.put("auction_source_id", source.id)
                  |> Map.put("query", query)
                  |> Map.put_new("status", "new")

                case upsert_candidate(attrs) do
                  {:ok, candidate} -> candidate
                  {:error, _} -> nil
                end
              end)
              |> Enum.reject(&is_nil/1)

            {:error, _} ->
              []
          end
        end)

      {:ok, results}
    end
  end

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
