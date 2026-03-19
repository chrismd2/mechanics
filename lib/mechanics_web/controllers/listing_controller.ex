defmodule MechanicsWeb.ListingController do
  use MechanicsWeb, :controller

  def new(conn, _params) do
    render(conn, :new)
  end
end
