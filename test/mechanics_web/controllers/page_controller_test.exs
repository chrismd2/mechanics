defmodule MechanicsWeb.PageControllerTest do
  use MechanicsWeb.ConnCase

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
      empty_message = Floki.find(parsed, "p")
      empty_state = Enum.any?(empty_message, &(Floki.text(&1) =~ "No mechanics have signed up yet"))
      mechanics_list = Floki.find(parsed, ".grid div:first-child ul li")
      has_mechanics = mechanics_list != []

      assert empty_state != has_mechanics
    end

    test "Checking for mechanics for hire section with a new mechanic who doesn't have a public profile", %{conn: conn} do
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
    end

    test "Checking for mechanics for hire section with a new mechanic who has a public profile", %{conn: conn} do
      # Add a mechanic user through registration process
      valid_params = %{
        "email" => "mechanic1@example.com",
        "name" => "Test Mechanic",
        "roles" => ["mechanic"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123",
        "wants_listing" => "true"
      }
      _register_conn =
        build_conn()
        |> post(~p"/register", %{"user" => valid_params})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      mechanics_list = Floki.find(parsed, ".grid div:first-child ul li")

      assert mechanics_list != []
    end

    test "Checking for jobs available section", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Jobs available"
    end

    test "shows jobs available section with empty state when no customers", %{conn: conn} do
      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      assert html =~ "No customers have signed up yet"
      grid_divs = Floki.find(parsed, ".grid > div")
      jobs_section = Enum.at(grid_divs, 1)
      jobs_list = Floki.find(jobs_section, "ul li")
      assert jobs_list == [], "expected no customers in jobs available when none have signed up"
    end

    test "lists no customers in jobs available when customer has signed up and wants listing", %{conn: conn} do
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

      assert jobs_list == [], "expected no customers in jobs available when none want a listing"
      assert html =~ "customer1@example.com"
    end

    test "lists customers in jobs available when customer has signed up and wants listing", %{conn: conn} do
      customer_params = %{
        "email" => "customer1@example.com",
        "name" => "Test Customer",
        "roles" => ["customer"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123",
        "wants_listing" => "true"
      }

      build_conn()
      |> post(~p"/register", %{"user" => customer_params})

      conn = get(conn, ~p"/")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      grid_divs = Floki.find(parsed, ".grid > div")
      jobs_section = Enum.at(grid_divs, 1)
      jobs_list = Floki.find(jobs_section, "ul li")

      assert length(jobs_list) >= 1,
             "expected at least one customer in jobs available section after customer signs up"
      assert html =~ "customer1@example.com"
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
