defmodule MechanicsWeb.PageController do
  use MechanicsWeb, :controller

  alias Mechanics.Accounts

  def home(conn, _params) do
    conn
    |> assign(:mechanics, Accounts.list_mechanics())
    |> assign(:customers, Accounts.list_customers())
    |> render(:home)
  end
end
