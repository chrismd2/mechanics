defmodule MechanicsWeb.ListingController do
  use MechanicsWeb, :controller

  alias Mechanics.Listings
  alias Mechanics.Disclaimers
  alias Mechanics.Repo

  def new(conn, _params) do
    current_user = conn.assigns[:current_user]

    if current_user && "customer" in current_user.roles do
      changeset = Listings.change_listing(%Mechanics.Listings.Listing{})
      render(conn, :show, listing: nil, changeset: changeset, warranty_acknowledged: false)
    else
      redirect(conn, to: ~p"/")
    end
  end

  def create(conn, %{"listing" => listing_params}) do
    current_user = conn.assigns[:current_user]

    unless current_user && "customer" in current_user.roles do
      redirect(conn, to: ~p"/")
    else
      warranty_accepted? =
        listing_params["warranty_disclaimer_accepted"] in ["true", "on", "1"]

      attrs =
        listing_params
        |> Map.put("customer_id", current_user.id)

      if warranty_accepted? do
        result =
          Repo.transaction(fn ->
            case Listings.create_listing(Map.drop(attrs, ["warranty_disclaimer_accepted"])) do
              {:ok, %Mechanics.Listings.Listing{} = listing} ->
                with {:ok, _agreement} <- Disclaimers.log_user_agreement(current_user.id, :warranty) do
                  listing
                else
                  {:error, _} = err -> Repo.rollback(err)
                end

              {:error, %Ecto.Changeset{} = changeset} ->
                Repo.rollback(changeset)
            end
          end)

        case result do
          {:ok, _listing} ->
            conn
            |> put_flash(:info, "Listing created successfully.")
            |> redirect(to: ~p"/")

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, :show, listing: nil, changeset: changeset, warranty_acknowledged: false)

          {:error, _other} ->
            # Log failures are unexpected; fall back to a generic error rendering.
            changeset = Listings.change_listing(%Mechanics.Listings.Listing{}, attrs)
            render(conn, :show, listing: nil, changeset: changeset, warranty_acknowledged: false)
        end
      else
        changeset = Listings.change_listing(%Mechanics.Listings.Listing{}, attrs)
        render(conn, :show, listing: nil, changeset: changeset, warranty_acknowledged: false)
      end
    end
  end

  def edit(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    with true <- current_user && "customer" in current_user.roles,
         %Mechanics.Listings.Listing{} = listing <- Listings.get_listing!(id),
         true <- listing.customer_id == current_user.id do
      changeset = Listings.change_listing(listing)
      render(conn, :show, listing: listing, changeset: changeset, warranty_acknowledged: false)
    else
      _ ->
        redirect(conn, to: ~p"/")
    end
  end

  def update(conn, %{"id" => id, "listing" => listing_params}) do
    current_user = conn.assigns[:current_user]

    with true <- current_user && "customer" in current_user.roles,
         %Mechanics.Listings.Listing{} = listing <- Listings.get_listing!(id),
         true <- listing.customer_id == current_user.id do
      warranty_accepted? =
        listing_params["warranty_disclaimer_accepted"] in ["true", "on", "1"]

      attrs = Map.put(listing_params, "customer_id", current_user.id)

      if warranty_accepted? do
        result =
          Repo.transaction(fn ->
            case Listings.update_listing(listing, Map.drop(attrs, ["warranty_disclaimer_accepted"])) do
              {:ok, %Mechanics.Listings.Listing{} = updated_listing} ->
                with {:ok, _agreement} <- Disclaimers.log_user_agreement(current_user.id, :warranty) do
                  updated_listing
                else
                  {:error, _} = err -> Repo.rollback(err)
                end

              {:error, %Ecto.Changeset{} = changeset} ->
                Repo.rollback(changeset)
            end
          end)

        case result do
          {:ok, _listing} ->
            conn
            |> put_flash(:info, "Listing updated successfully.")
            |> redirect(to: ~p"/")

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, :show, listing: listing, changeset: changeset, warranty_acknowledged: false)

          {:error, _other} ->
            render(conn, :show, listing: listing, changeset: Listings.change_listing(listing, attrs), warranty_acknowledged: false)
        end
      else
        changeset = Listings.change_listing(listing, attrs)
        render(conn, :show, listing: listing, changeset: changeset, warranty_acknowledged: false)
      end
    else
      _ ->
        redirect(conn, to: ~p"/")
    end
  end
end
