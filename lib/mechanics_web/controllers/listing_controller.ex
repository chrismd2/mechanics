defmodule MechanicsWeb.ListingController do
  use MechanicsWeb, :controller

  alias Mechanics.Listings
  alias Mechanics.Disclaimers
  alias Mechanics.Repo
  alias Mechanics.Listings.Listing
  alias MechanicsWeb.Helpers.CurrencyFormatter

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

      {money_attrs, money_error} = normalize_listing_money(listing_params)

      attrs =
        money_attrs
        |> Map.put("customer_id", current_user.id)

      {attrs, forced_private?} = enforce_private_if_unverified(attrs, current_user)

      cond do
        money_error ->
          changeset =
            %Listing{}
            |> Listings.change_listing(attrs)
            |> Ecto.Changeset.add_error(:price_cents, money_error)

          render(conn, :show, listing: nil, changeset: changeset, warranty_acknowledged: false)

        warranty_accepted? ->
        result =
          Repo.transaction(fn ->
            case Listings.create_listing(Map.drop(attrs, ["warranty_disclaimer_accepted", "price"])) do
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
            |> put_flash(
              :info,
              if(forced_private?, do: "Listing created successfully. Verify your email to publish it.", else: "Listing created successfully.")
            )
            |> redirect(to: ~p"/")

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, :show, listing: nil, changeset: changeset, warranty_acknowledged: false)

          {:error, _other} ->
            # Log failures are unexpected; fall back to a generic error rendering.
            changeset = Listings.change_listing(%Mechanics.Listings.Listing{}, attrs)
            render(conn, :show, listing: nil, changeset: changeset, warranty_acknowledged: false)
        end

        true ->
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

      {money_attrs, money_error} = normalize_listing_money(listing_params)
      attrs = Map.put(money_attrs, "customer_id", current_user.id)
      {attrs, forced_private?} = enforce_private_if_unverified(attrs, current_user)

      cond do
        money_error ->
          changeset =
            listing
            |> Listings.change_listing(attrs)
            |> Ecto.Changeset.add_error(:price_cents, money_error)

          render(conn, :show, listing: listing, changeset: changeset, warranty_acknowledged: false)

        warranty_accepted? ->
        result =
          Repo.transaction(fn ->
            case Listings.update_listing(listing, Map.drop(attrs, ["warranty_disclaimer_accepted", "price"])) do
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
            |> put_flash(
              :info,
              if(forced_private?, do: "Listing updated. Verify your email to publish it.", else: "Listing updated successfully.")
            )
            |> redirect(to: ~p"/")

          {:error, %Ecto.Changeset{} = changeset} ->
            render(conn, :show, listing: listing, changeset: changeset, warranty_acknowledged: false)

          {:error, _other} ->
            render(conn, :show, listing: listing, changeset: Listings.change_listing(listing, attrs), warranty_acknowledged: false)
        end

        true ->
          changeset = Listings.change_listing(listing, attrs)
          render(conn, :show, listing: listing, changeset: changeset, warranty_acknowledged: false)
      end
    else
      _ ->
        redirect(conn, to: ~p"/")
    end
  end

  def delete(conn, %{"id" => id}) do
    current_user = conn.assigns[:current_user]

    with true <- current_user && "customer" in current_user.roles,
         %Mechanics.Listings.Listing{} = listing <- Listings.get_listing!(id),
         true <- listing.customer_id == current_user.id,
         {:ok, _deleted_listing} <- Listings.delete_listing(listing) do
      conn
      |> put_flash(:info, "Listing deleted successfully.")
      |> redirect(to: ~p"/")
    else
      _ ->
        conn
        |> put_flash(:error, "You cannot delete that listing.")
        |> redirect(to: ~p"/")
    end
  end

  defp enforce_private_if_unverified(attrs, current_user) do
    wants_public? = attrs["is_public"] in [true, "true", "on", "1"]

    if current_user.email_verified do
      {attrs, false}
    else
      {Map.put(attrs, "is_public", false), wants_public?}
    end
  end

  defp normalize_listing_money(attrs) do
    currency =
      attrs
      |> Map.get("currency", "")
      |> to_string()
      |> String.upcase()

    attrs = Map.put(attrs, "currency", currency)
    price = Map.get(attrs, "price", "")
    valid_currency? = currency in CurrencyFormatter.valid_currency_codes()

    cond do
      not valid_currency? ->
        {Map.delete(attrs, "price_cents"), "Choose a valid currency."}

      true ->
        case CurrencyFormatter.parse_major_to_minor(to_string(price), currency) do
          {:ok, price_cents} ->
            {Map.put(attrs, "price_cents", price_cents), nil}

          {:error, :invalid_amount} ->
            {Map.delete(attrs, "price_cents"), "Enter a valid amount for the selected currency."}
        end
    end
  end
end
