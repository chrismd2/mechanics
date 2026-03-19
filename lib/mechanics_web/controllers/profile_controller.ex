defmodule MechanicsWeb.ProfileController do
  use MechanicsWeb, :controller

  def show(conn, _params) do
    render(conn, :show)
  end
end
