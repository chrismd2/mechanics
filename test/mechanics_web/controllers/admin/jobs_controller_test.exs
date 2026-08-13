defmodule MechanicsWeb.Admin.JobsControllerTest do
  use MechanicsWeb.ConnCase, async: false

  alias Mechanics.Accounts
  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Repo

  defp create_admin(conn) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        "email" => "admin-jobs-#{suffix}@example.com",
        "name" => "Admin",
        "roles" => ["customer", "admin"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user = user |> Ecto.Changeset.change(email_verified: true) |> Repo.update!()
    conn = init_test_session(conn, %{current_user_id: user.id})
    {:ok, conn: conn, user: user}
  end

  test "shows job detail", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)
    {:ok, job} = ListingSearch.enqueue_crawl()

    conn = get(conn, ~p"/admin/jobs/#{job.id}")
    assert html_response(conn, 200) =~ "Job ##{job.id}"
    assert html_response(conn, 200) =~ "CrawlPastAuctionsWorker"
  end
end
