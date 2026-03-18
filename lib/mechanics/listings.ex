defmodule Mechanics.Listings do
  @moduledoc """
  The Listings context.
  """

  import Ecto.Query, warn: false

  alias Mechanics.Repo
  alias Mechanics.Listings.Listing

  def list_listings do
    Repo.all(from l in Listing, order_by: [desc: l.inserted_at, desc: l.id])
  end

  def get_listing!(id), do: Repo.get!(Listing, id)

  def create_listing(attrs \\ %{}) do
    %Listing{}
    |> Listing.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_listing(%Listing{} = listing, attrs) do
    listing
    |> Listing.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_listing(%Listing{} = listing) do
    Repo.delete(listing)
  end

  def change_listing(%Listing{} = listing, attrs \\ %{}) do
    Listing.update_changeset(listing, attrs)
  end

  @doc """
  Returns a list of listings filtered by the given params.
  Example params: %{customer_id: ..., title: ...}
  """
  def list_listings_by(params) when is_map(params) do
    query =
      Listing
      |> where(^Enum.reduce(params, dynamic(true), fn
        {:customer_id, val}, dynamic -> dynamic([l], ^dynamic and l.customer_id == ^val)
        {:title, val}, dynamic -> dynamic([l], ^dynamic and ilike(l.title, ^"%#{val}%"))
        {key, val}, dynamic -> dynamic([l], ^dynamic and field(l, ^key) == ^val)
      end))

    Repo.all(from l in query, order_by: [desc: l.inserted_at, desc: l.id])
  end
end
