defmodule MechanicsWeb.PageController do
  use MechanicsWeb, :controller

  alias Mechanics.Chats.Notifications
  alias Mechanics.Listings
  alias Mechanics.Profiles

  def home(conn, _params) do
    mechanics = Profiles.list_mechanic_profiles()
    listings = Listings.list_public_listings()
    user = conn.assigns[:current_user]

    mechanic_card_bells = mechanic_card_bells_map(user, mechanics)
    listing_owner_card_bells = listing_owner_card_bells_map(user, listings)
    listing_mechanic_card_bells = listing_mechanic_card_bells_map(user, listings)

    conn
    |> assign(:mechanics, mechanics)
    |> assign(:listings, listings)
    |> assign(:mechanic_card_bells, mechanic_card_bells)
    |> assign(:listing_owner_card_bells, listing_owner_card_bells)
    |> assign(:listing_mechanic_card_bells, listing_mechanic_card_bells)
    |> render(:home)
  end

  defp mechanic_card_bells_map(user, mechanics) do
    if user && "customer" in user.roles do
      Map.new(mechanics, fn p ->
        {p.user_id, Notifications.customer_mechanic_pm_card_peers(user, p.user_id)}
      end)
    else
      %{}
    end
  end

  defp listing_owner_card_bells_map(user, listings) do
    if user && "customer" in user.roles do
      Map.new(listings, fn l ->
        v =
          if l.customer_id == user.id do
            Notifications.listing_owner_card_peers(user, l.id)
          else
            %{total_unread: 0, peers: []}
          end

        {l.id, v}
      end)
    else
      %{}
    end
  end

  defp listing_mechanic_card_bells_map(user, listings) do
    if user && "mechanic" in user.roles do
      Map.new(listings, fn l ->
        v =
          if l.customer_id != user.id do
            Notifications.listing_mechanic_card_peers(user, l.id)
          else
            %{total_unread: 0, peers: []}
          end

        {l.id, v}
      end)
    else
      %{}
    end
  end
end
