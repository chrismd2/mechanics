defmodule MechanicsWeb.PageControllerTest do
  use MechanicsWeb.ConnCase

  describe "GET / shows a home page with core functionality of this page" do
    test "Checking for tagline ", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Connecting mechanics with customers to complete jobs"
    end

    test "Checking for mechanics for hire section", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Mechanics for hire"
    end

    test "Checking for jobs available section", %{conn: conn} do
      conn = get(conn, ~p"/")
      assert html_response(conn, 200) =~ "Jobs available"
    end

    test "Checking for sign up links", %{conn: conn} do
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
