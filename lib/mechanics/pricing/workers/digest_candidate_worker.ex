defmodule Mechanics.Pricing.Workers.DigestCandidateWorker do
  @moduledoc """
  Fetches listing detail for a candidate and imports into vehicle_market_prices when complete.
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

  require Logger

  alias Mechanics.Accounts
  alias Mechanics.Accounts.User
  alias Mechanics.Pricing
  alias Mechanics.Pricing.ListingSearch

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"candidate_id" => candidate_id} = args}) do
    candidate = ListingSearch.get_candidate!(candidate_id)

    with {:ok, %User{} = user} <- resolve_user(args) do
      case Pricing.import_market_price_from_url(user, candidate.source_url) do
        {:ok, :created, record} ->
          ListingSearch.mark_candidate_imported(candidate, record.id)
          :ok

        {:ok, :already_exists, record} ->
          ListingSearch.mark_candidate_imported(candidate, record.id)
          :ok

        {:needs_form, attrs} ->
          Logger.warning(
            "Digest needs form for #{candidate.source_url}: #{inspect(Map.take(attrs, ["make", "model", "year", "miles", "price_cents"]))}"
          )

          ListingSearch.mark_candidate_failed(candidate)
          :ok

        {:error, reason} ->
          Logger.warning("Digest failed for #{candidate.source_url}: #{inspect(reason)}")
          ListingSearch.mark_candidate_failed(candidate)
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
end
