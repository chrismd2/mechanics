defmodule MechanicsWeb.PageControllerTest do
  use MechanicsWeb.ConnCase

  alias Mechanics.Accounts
  alias Mechanics.Listings
  alias Mechanics.Profiles

  describe "GET / shows a home page with core functionality of this page" do
    test "Checking for tagline ", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Connecting mechanics with customers to complete jobs"
    end

    test "Checking for mechanics for hire section", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "Mechanics for hire"
      parsed = Floki.parse_document!(html)
      plus_link = Floki.find(parsed, ~s(a[href="/profile"]))
      assert plus_link != []
      assert Enum.any?(plus_link, &(Floki.text(&1) =~ "+"))

      empty_message = Floki.find(parsed, "p")
      empty_state = Enum.any?(empty_message, &(Floki.text(&1) =~ "No public mechanic profiles are available yet"))
      mechanics_list = Floki.find(parsed, ".grid div:first-child ul li")
      has_mechanics = mechanics_list != []

      assert empty_state != has_mechanics
    end

    test "shows no mechanics for hire when a mechanic has no public profile", %{conn: conn} do
      # Add a mechanic user through registration process
      valid_params = %{
        "email" => "mechanic1@example.com",
        "name" => "Test Mechanic",
        "roles" => ["mechanic"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123",
        "wants_listing" => "false"
      }
      _register_conn =
        build_conn()
        |> post(~p"/register", %{"user" => valid_params})

      # Request homepage again to update mechanics list with the new mechanic
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      mechanics_list = Floki.find(parsed, ".grid div:first-child ul li")

      assert mechanics_list == []
      assert html =~ "No public mechanic profiles are available yet"
    end

    test "lists public mechanic profiles in mechanics for hire", %{conn: conn} do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "mechanic1@example.com",
          "name" => "Test Mechanic",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, _profile} =
        Profiles.create_profile(%{
          "headline" => "Mobile brake specialist",
          "bio" => "I travel to you for brake and rotor work.",
          "city" => "Phoenix",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      mechanics_list = Floki.find(parsed, ".grid div:first-child ul li")

      assert mechanics_list != []
      assert html =~ "Mobile brake specialist"
      assert html =~ "I travel to you for brake and rotor work."
      assert html =~ "Phoenix, AZ"
    end

    test "Checking for jobs available section", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      assert html =~ "Jobs available"
      parsed = Floki.parse_document!(html)

      plus_link = Floki.find(parsed, ~s(a[href="/listings/new"]))
      assert plus_link != []
      assert Enum.any?(plus_link, &(Floki.text(&1) =~ "+"))
    end

    test "shows jobs available section with empty state when no listings", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      assert html =~ "No job listings have been posted yet"
      grid_divs = Floki.find(parsed, ".grid > div")
      jobs_section = Enum.at(grid_divs, 1)
      jobs_list = Floki.find(jobs_section, "ul li")
      assert jobs_list == [], "expected no listings in jobs available when none have been posted"
    end

    test "shows no listings in jobs available when a customer has signed up but not posted one", %{conn: conn} do
      customer_params = %{
        "email" => "customer1@example.com",
        "name" => "Test Customer",
        "roles" => ["customer"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123",
        "wants_listing" => "false"
      }

      build_conn()
      |> post(~p"/register", %{"user" => customer_params})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      grid_divs = Floki.find(parsed, ".grid > div")
      jobs_section = Enum.at(grid_divs, 1)
      jobs_list = Floki.find(jobs_section, "ul li")

      assert jobs_list == [], "expected no listings in jobs available when no listing has been posted"
      assert html =~ "No job listings have been posted yet"
    end

    test "lists job listings in jobs available when a customer posts one", %{conn: conn} do
      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "customer1@example.com",
          "name" => "Test Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, _listing} =
        Listings.create_listing(%{
          "title" => "Brake pad replacement",
          "description" => "Need front brake pads replaced this week",
          "price_cents" => 12_500,
          "currency" => "USD",
          "customer_id" => customer.id
        })

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      grid_divs = Floki.find(parsed, ".grid > div")
      jobs_section = Enum.at(grid_divs, 1)
      jobs_list = Floki.find(jobs_section, "ul li")

      assert length(jobs_list) >= 1,
             "expected at least one listing in jobs available section after a listing is posted"

      assert html =~ "Brake pad replacement"
      assert html =~ "Need front brake pads replaced this week"
      assert html =~ "12500 USD"
    end

    test "shows Sign up link", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      links = Floki.find(parsed, "a[href*=\"register\"]")
      assert links != []
      sign_up_link = Enum.find(links, &(Floki.text(&1) =~ "Sign up"))
      assert sign_up_link != nil
    end


    test "Checking for sign in links", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      links = Floki.find(parsed, "a[href*=\"login\"]")
      assert links != []
      sign_in_link = Enum.find(links, &(Floki.text(&1) =~ "Sign in"))
      assert sign_in_link != nil
    end
  end
end
