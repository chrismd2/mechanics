defmodule MechanicsWeb.Admin.AuctionSourcesController do
  use MechanicsWeb, :controller

  def index(conn, _params) do
    redirect(conn, to: ~p"/admin?tab=sources")
  end
end
