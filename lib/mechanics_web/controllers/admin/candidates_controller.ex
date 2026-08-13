defmodule MechanicsWeb.Admin.CandidatesController do
  use MechanicsWeb, :controller

  alias Mechanics.Pricing.ListingSearch

  def index(conn, params) do
    query =
      %{"tab" => "candidates"}
      |> maybe_put("status", params["status"])
      |> URI.encode_query()

    redirect(conn, to: "/admin?#{query}")
  end

  def show(conn, %{"id" => id}) do
    case admin_user(conn) do
      {:ok, _user} ->
        candidate = ListingSearch.get_candidate!(id)

        conn
        |> assign(:wide_layout, true)
        |> render(:show, candidate: candidate)

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  defp admin_user(conn) do
    current_user = conn.assigns[:current_user]

    if current_user && "admin" in (current_user.roles || []) do
      {:ok, current_user}
    else
      :error
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
