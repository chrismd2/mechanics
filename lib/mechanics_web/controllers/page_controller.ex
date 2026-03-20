defmodule MechanicsWeb.PageController do
  use MechanicsWeb, :controller

  alias Mechanics.Listings
  alias Mechanics.Profiles

  def home(conn, _params) do
    conn
    |> assign(:mechanics, Profiles.list_mechanic_profiles())
    |> assign(:listings, Listings.list_public_listings())
    |> render(:home)
  end
end
