defmodule MechanicsWeb.Admin.AuctionSourcesControllerTest do
  use MechanicsWeb.ConnCase, async: false

  alias Mechanics.Accounts
  alias Mechanics.Repo

  test "legacy auction-sources index redirects to admin panel", %{conn: conn} do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        "email" => "admin-src-#{suffix}@example.com",
        "name" => "Admin",
        "roles" => ["customer", "admin"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user = user |> Ecto.Changeset.change(email_verified: true) |> Repo.update!()
    conn = init_test_session(conn, %{current_user_id: user.id})

    conn = get(conn, ~p"/admin/auction-sources")
    assert redirected_to(conn) == "/admin?tab=sources"
  end
end
