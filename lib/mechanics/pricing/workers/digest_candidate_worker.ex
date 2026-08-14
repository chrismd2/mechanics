defmodule Mechanics.Pricing.Workers.DigestCandidateWorker do
  @moduledoc """
  Fetches listing detail for a candidate and imports into vehicle_market_prices when complete.
  Writes outcome into job `meta["results"]` for the admin job detail page.
  """

  use Oban.Worker,
    queue: :digest,
    max_attempts: 3,
    unique: [
      period: :infinity,
      fields: [:args, :worker],
      keys: [:candidate_id],
      states: :incomplete
    ]

  import Ecto.Query, only: [from: 2]

  require Logger

  alias Mechanics.Accounts
  alias Mechanics.Accounts.User
  alias Mechanics.Pricing
  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"candidate_id" => candidate_id} = args} = job) do
    candidate = ListingSearch.get_candidate!(candidate_id)

    with {:ok, %User{} = user} <- resolve_user(args) do
      case Pricing.import_market_price_from_url(user, candidate.source_url) do
        {:ok, :created, record} ->
          ListingSearch.mark_candidate_imported(candidate, record.id)

          persist_outcome(job, %{
            "kind" => "digest",
            "status" => "imported",
            "outcome" => "created",
            "candidate_id" => to_string(candidate.id),
            "title" => candidate.title,
            "source_url" => candidate.source_url,
            "query" => candidate.query,
            "vehicle_market_price_id" => to_string(record.id),
            "make" => record.make,
            "model" => record.model,
            "year" => record.year,
            "miles" => record.miles,
            "price_cents" => record.price_cents,
            "price_type" => record.price_type
          })

          :ok

        {:ok, :already_exists, record} ->
          ListingSearch.mark_candidate_imported(candidate, record.id)

          persist_outcome(job, %{
            "kind" => "digest",
            "status" => "imported",
            "outcome" => "already_exists",
            "candidate_id" => to_string(candidate.id),
            "title" => candidate.title,
            "source_url" => candidate.source_url,
            "query" => candidate.query,
            "vehicle_market_price_id" => to_string(record.id),
            "make" => record.make,
            "model" => record.model,
            "year" => record.year,
            "miles" => record.miles,
            "price_cents" => record.price_cents,
            "price_type" => record.price_type
          })

          :ok

        {:needs_form, attrs} ->
          snapshot =
            Map.take(attrs, ["make", "model", "year", "miles", "price_cents", "price_type", "source_url"])

          Logger.warning(
            "Digest needs form for #{candidate.source_url}: #{inspect(snapshot)}"
          )

          ListingSearch.mark_candidate_failed(candidate)

          persist_outcome(job, %{
            "kind" => "digest",
            "status" => "failed",
            "outcome" => "needs_form",
            "candidate_id" => to_string(candidate.id),
            "title" => candidate.title,
            "source_url" => candidate.source_url,
            "query" => candidate.query,
            "error" => "Import incomplete — needs form fields",
            "attrs" => snapshot
          })

          :ok

        {:error, reason} ->
          Logger.warning("Digest failed for #{candidate.source_url}: #{inspect(reason)}")
          ListingSearch.mark_candidate_failed(candidate)

          persist_outcome(job, %{
            "kind" => "digest",
            "status" => "failed",
            "outcome" => "error",
            "candidate_id" => to_string(candidate.id),
            "title" => candidate.title,
            "source_url" => candidate.source_url,
            "query" => candidate.query,
            "error" => inspect(reason)
          })

          {:error, reason}
      end
    end
  end

  defp resolve_user(%{"user_id" => user_id}) when is_binary(user_id) do
    case Accounts.get_user(user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:cancel, :user_not_found}
    end
  end

  defp resolve_user(_), do: {:cancel, :missing_user_id}

  defp persist_outcome(%Oban.Job{id: nil}, _report), do: :ok

  defp persist_outcome(%Oban.Job{id: id, meta: meta}, report) do
    meta = Map.merge(meta || %{}, %{"results" => [report]})

    {count, _} =
      from(j in Oban.Job, where: j.id == ^id)
      |> Repo.update_all(set: [meta: meta])

    if count != 1 do
      Logger.warning("DigestCandidateWorker meta update affected #{count} rows for job #{id}")
    end

    :ok
  end
end
