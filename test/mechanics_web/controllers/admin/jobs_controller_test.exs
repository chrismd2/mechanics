defmodule MechanicsWeb.Admin.JobsControllerTest do
  use MechanicsWeb.ConnCase, async: false

  import Ecto.Query

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

  test "lists crawl results from job meta", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)
    {:ok, job} = ListingSearch.enqueue_crawl()

    meta =
      Map.merge(job.meta || %{}, %{
        "results" => [
          %{
            "label" => "Royal",
            "base_url" => "https://live.royalauctiongroup.com",
            "status" => "ok",
            "auction_count" => 1,
            "auctions" => [
              %{
                "auction_id" => "6329",
                "title" => "December Auction",
                "auction_status" => 300,
                "end_time" => "2024-12-15T01:00:00Z"
              }
            ]
          }
        ]
      })

    {_count, _} =
      from(j in Oban.Job, where: j.id == ^job.id)
      |> Repo.update_all(set: [meta: meta])

    conn = get(conn, ~p"/admin/jobs/#{job.id}")
    html = html_response(conn, 200)
    assert html =~ "Results"
    assert html =~ "December Auction"
    assert html =~ "6329"
  end

  test "lists crawl results from auction source when job meta is empty", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)

    {:ok, source} =
      ListingSearch.create_auction_source(%{
        "kind" => "royal",
        "base_url" => "https://live.example-royal-#{System.unique_integer([:positive])}.test",
        "label" => "Fallback Royal",
        "enabled" => true
      })

    now = DateTime.utc_now()
    crawled_at = DateTime.truncate(now, :second)

    {:ok, _source} =
      ListingSearch.update_auction_source(source, %{
        last_crawled_at: crawled_at,
        config: %{
          "last_crawl_report" => %{
            "status" => "ok",
            "auction_count" => 1,
            "auction_ids" => ["9999"],
            "at" => DateTime.to_iso8601(crawled_at)
          },
          "last_crawl_auctions" => [
            %{
              "auction_id" => "9999",
              "title" => "Fallback Auction Title",
              "auction_status" => 300,
              "end_time" => "2024-01-01T00:00:00Z"
            }
          ]
        }
      })

    {:ok, job} =
      %Oban.Job{}
      |> Ecto.Changeset.change(%{
        state: "completed",
        queue: "crawl",
        worker: "Mechanics.Pricing.Workers.CrawlPastAuctionsWorker",
        args: %{},
        meta: %{},
        attempted_at: now,
        completed_at: now,
        scheduled_at: now
      })
      |> Repo.insert()

    conn = get(conn, ~p"/admin/jobs/#{job.id}")
    html = html_response(conn, 200)
    assert html =~ "Results"
    assert html =~ "Fallback Auction Title"
    assert html =~ "9999"
  end

  test "retries a discarded job", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)

    now = DateTime.utc_now()

    {:ok, job} =
      %Oban.Job{}
      |> Ecto.Changeset.change(%{
        state: "discarded",
        queue: "digest",
        worker: "Mechanics.Pricing.Workers.DigestCandidateWorker",
        args: %{"candidate_id" => Ecto.UUID.generate(), "user_id" => Ecto.UUID.generate()},
        meta: %{},
        attempt: 3,
        max_attempts: 3,
        attempted_at: now,
        discarded_at: now,
        scheduled_at: now
      })
      |> Repo.insert()

    conn = post(conn, ~p"/admin/jobs/#{job.id}/retry")
    assert redirected_to(conn) == "/admin/jobs/#{job.id}"

    refreshed = Repo.get!(Oban.Job, job.id)
    assert refreshed.state == "available"
    assert is_nil(refreshed.discarded_at)
  end

  test "runs a scheduled job now", %{conn: conn} do
    {:ok, conn: conn, user: _user} = create_admin(conn)

    future = DateTime.utc_now() |> DateTime.add(3600, :second)

    {:ok, job} =
      %Oban.Job{}
      |> Ecto.Changeset.change(%{
        state: "scheduled",
        queue: "digest",
        worker: "Mechanics.Pricing.Workers.DigestCandidateWorker",
        args: %{"candidate_id" => Ecto.UUID.generate(), "user_id" => Ecto.UUID.generate()},
        meta: %{},
        scheduled_at: future
      })
      |> Repo.insert()

    conn = post(conn, ~p"/admin/jobs/#{job.id}/run-now")
    assert redirected_to(conn) == "/admin/jobs/#{job.id}"

    refreshed = Repo.get!(Oban.Job, job.id)
    assert refreshed.state == "available"
    assert DateTime.compare(refreshed.scheduled_at, future) == :lt
  end
end
