defmodule MechanicsWeb.AdminControllerTest do
  use MechanicsWeb.ConnCase, async: false

  alias Mechanics.Accounts
  alias Mechanics.Pricing
  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Repo

  defp create_admin(conn) do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        "email" => "admin-hub-#{suffix}@example.com",
        "name" => "Admin",
        "roles" => ["customer", "admin"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user = user |> Ecto.Changeset.change(email_verified: true) |> Repo.update!()
    conn = init_test_session(conn, %{current_user_id: user.id})
    {:ok, conn: conn, user: user}
  end

  test "redirects home without admin", %{conn: conn} do
    conn = get(conn, ~p"/admin")
    assert redirected_to(conn) == ~p"/"
  end

  test "shows admin panels and creates a source", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)

    conn = get(conn, ~p"/admin")
    html = html_response(conn, 200)
    assert html =~ "Admin"
    assert html =~ "admin-panel-sources"
    assert html =~ "admin-panel-jobs"
    assert html =~ "admin-panel-candidates"

    conn =
      post(conn, ~p"/admin/auction-sources", %{
        "auction_source" => %{
          "kind" => "royal",
          "base_url" => "https://live.royalauctiongroup.com",
          "label" => "Royal"
        }
      })

    assert redirected_to(conn) == "/admin?tab=sources"
    assert [%{label: "Royal"}] = ListingSearch.list_auction_sources()
  end

  test "legacy paths redirect to admin tabs", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)

    conn = get(conn, ~p"/admin/auction-sources")
    assert redirected_to(conn) == "/admin?tab=sources"

    conn = get(conn, ~p"/admin/jobs")
    assert redirected_to(conn) == "/admin?tab=jobs"

    conn = get(conn, ~p"/admin/candidates")
    assert redirected_to(conn) == "/admin?tab=candidates"
  end

  test "enqueues crawl from jobs panel", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)

    conn = post(conn, ~p"/admin/jobs/crawl", %{})
    assert redirected_to(conn) =~ "/admin/jobs/"
    assert [%{queue: "crawl"}] = ListingSearch.list_oban_jobs(queue: "crawl", limit: 5)

    conn = get(conn, ~p"/admin?tab=jobs")
    assert html_response(conn, 200) =~ "Oban Jobs"
    assert html_response(conn, 200) =~ "CrawlPastAuctionsWorker"
  end

  test "listing search uses search_vehicle_market_prices and shows local comps", %{conn: conn} do
    {:ok, conn: conn, user: user} = create_admin(conn)

    {:ok, market_price} =
      Pricing.create_market_price(user, %{
        "make" => "Ford",
        "model" => "F-150",
        "year" => 2018,
        "miles" => 100_000,
        "price_cents" => 2_500_000,
        "price_type" => "listing",
        "source_url" => "https://example.com/f150-#{System.unique_integer([:positive])}"
      })

    conn =
      post(conn, ~p"/admin/jobs/search", %{
        "vehicle" => %{
          "make" => "Ford",
          "model" => "F-150",
          "year" => "2018",
          "miles" => "100000",
          "zipcode" => "90210"
        }
      })

    html = html_response(conn, 200)
    assert html =~ "admin-panel-jobs"
    assert html =~ ~s(value="Ford")
    assert html =~ "Listing search"
    refute html =~ "Trial listing search"
    assert html =~ "search_vehicle_market_prices"
    assert html =~ "Results ("
    assert html =~ "local"
    assert html =~ to_string(market_price.id)
  end

  test "paginates Oban jobs on the jobs panel", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)

    for i <- 1..26 do
      assert {:ok, _} =
               %{"n" => i}
               |> Mechanics.Pricing.Workers.CrawlPastAuctionsWorker.new()
               |> Oban.insert()
    end

    conn = get(conn, ~p"/admin?tab=jobs")
    html = html_response(conn, 200)
    assert html =~ "Page 1"
    assert html =~ "Next"
    assert html =~ "page=2"

    newest_id = ListingSearch.list_oban_jobs(limit: 1) |> hd() |> Map.get(:id)
    assert html =~ "##{newest_id}"

    conn = get(conn, "/admin?tab=jobs&page=2")
    html = html_response(conn, 200)
    assert html =~ "Page 2"
    assert html =~ "Previous"
    refute html =~ "##{newest_id}"

    conn = get(conn, "/admin?tab=jobs&queue=crawl&page=2")
    html = html_response(conn, 200)
    assert html =~ "page=1"
    assert html =~ "queue=crawl"
  end
end
