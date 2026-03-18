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
end
