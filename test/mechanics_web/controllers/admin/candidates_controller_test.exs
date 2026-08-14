defmodule MechanicsWeb.Admin.CandidatesControllerTest do
  use MechanicsWeb.ConnCase, async: false

  alias Mechanics.Accounts
  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Repo

  defp create_admin(conn) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        "email" => "admin-cand-#{suffix}@example.com",
        "name" => "Admin",
        "roles" => ["customer", "admin"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user = user |> Ecto.Changeset.change(email_verified: true) |> Repo.update!()
    conn = init_test_session(conn, %{current_user_id: user.id})
    {:ok, conn: conn, user: user}
  end

  defp create_candidate! do
    {:ok, candidate} =
      ListingSearch.upsert_candidate(%{
        "source_url" => "https://example.com/lot/#{System.unique_integer([:positive])}",
        "title" => "2018 Ford F-150",
        "query" => "Ford F-150",
        "status" => "new",
        "raw" => %{"title" => "2018 Ford F-150"}
      })

    candidate
  end

  test "shows candidate and digests from admin hub actions", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)
    candidate = create_candidate!()

    conn = get(conn, ~p"/admin/candidates/#{candidate.id}")
    assert html_response(conn, 200) =~ "2018 Ford F-150"

    conn = post(conn, ~p"/admin/candidates/#{candidate.id}/digest", %{})
    assert redirected_to(conn) =~ "/admin/jobs/"
    assert [%{queue: "digest"}] = ListingSearch.list_oban_jobs(queue: "digest", limit: 5)
  end

  test "dismisses candidate back to admin candidates panel", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)
    candidate = create_candidate!()

    conn = post(conn, ~p"/admin/candidates/#{candidate.id}/dismiss", %{})
    assert redirected_to(conn) == "/admin?tab=candidates"
    assert ListingSearch.get_candidate!(candidate.id).status == "dismissed"
  end
end
