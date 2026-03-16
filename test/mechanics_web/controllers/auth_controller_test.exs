defmodule MechanicsWeb.AuthControllerTest do
  use MechanicsWeb.ConnCase

  describe "GET /register shows the registration page (new_registration)" do
    test "returns 200 and shows Sign up heading", %{conn: conn} do
      conn = get(conn, ~p"/register")
      assert html_response(conn, 200) =~ "Sign up"
    end

    test "shows registration form with email, password, and role fields", %{conn: conn} do
      conn = get(conn, ~p"/register")
      html = html_response(conn, 200)
      assert html =~ "Email"
      assert html =~ "Name"
      refute html =~ "Name (optional)"
      assert html =~ "Password"
      assert html =~ "Confirm password"
      assert html =~ "I am a"
      assert html =~ "Mechanic looking for work"
      assert html =~ "Customer looking for a mechanic"
      assert html =~ "And I would like to make a listing"

      parsed = Floki.parse_document!(html)
      form = Floki.find(parsed, "form[action=\"/register\"]") |> List.first()
      labels_with_listing_text =
        Floki.find(form, "label")
        |> Enum.filter(fn label -> Floki.text(label) =~ "And I would like to make a listing" end)
      assert length(labels_with_listing_text) >= 1,
             "expected to find a label containing 'And I would like to make a listing'"
      listing_label = hd(labels_with_listing_text)
      checkbox = Floki.find(listing_label, "input[type=\"checkbox\"]")
      assert checkbox != [],
             "expected 'And I would like to make a listing' to be next to a checkbox"
    end

    test "has form that posts to /register", %{conn: conn} do
      conn = get(conn, ~p"/register")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      form = Floki.find(parsed, "form[action=\"/register\"]")
      assert form != []
      assert Floki.attribute(form, "method") |> List.first() =~ "post"
    end

    test "shows Sign in link for existing users", %{conn: conn} do
      conn = get(conn, ~p"/register")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      links = Floki.find(parsed, "a[href*=\"login\"]")
      assert links != []
      assert html =~ "Already have an account?"
    end
  end

  describe "POST /register (registration form submission)" do
    @valid_params %{
      "email" => "newuser@example.com",
      "name" => "Jane Doe",
      "role" => "mechanic",
      "password" => "secret123",
      "password_confirmation" => "secret123",
      "wants_listing" => "false"
    }

    test "creates mechanic, sets session, and redirects to profile with success flash", %{conn: conn} do
      conn =
        conn
        |> post(~p"/register", %{"user" => @valid_params})

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) == "Account created successfully!"
      assert get_session(conn, :current_user_id)
    end

    test "creates customer, sets session, and redirects to create listings with success flash", %{conn: conn} do
      params = Map.put(@valid_params, "role", "customer")

      conn =
        conn
        |> post(~p"/register", %{"user" => params})

      assert redirected_to(conn) == ~p"/listings/new"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) == "Account created successfully!"
      assert get_session(conn, :current_user_id)
    end

    test "re-renders form with errors when name is missing", %{conn: conn} do
      params = Map.delete(@valid_params, "name")

      conn =
        conn
        |> post(~p"/register", %{"user" => params})

      assert html_response(conn, 200) =~ "Sign up"
    end

    test "re-renders form with errors when email is invalid", %{conn: conn} do
      params = Map.put(@valid_params, "email", "not-an-email")

      conn =
        conn
        |> post(~p"/register", %{"user" => params})

      assert html_response(conn, 200) =~ "Sign up"
      assert html_response(conn, 200) =~ "not-an-email"
    end

    test "re-renders form with errors when password is too short", %{conn: conn} do
      params =
        @valid_params
        |> Map.put("password", "short")
        |> Map.put("password_confirmation", "short")

      conn =
        conn
        |> post(~p"/register", %{"user" => params})

      assert html_response(conn, 200) =~ "Sign up"
    end

    test "re-renders form with errors when password and confirmation do not match", %{conn: conn} do
      params =
        @valid_params
        |> Map.put("password_confirmation", "different123")

      conn =
        conn
        |> post(~p"/register", %{"user" => params})

      assert html_response(conn, 200) =~ "Sign up"
    end

    test "re-renders form with errors when wants_listing is missing", %{conn: conn} do
      params = Map.delete(@valid_params, "wants_listing")

      conn =
        conn
        |> post(~p"/register", %{"user" => params})

      assert html_response(conn, 200) =~ "Sign up"
    end

    test "re-renders form with errors when required fields are missing", %{conn: conn} do
      conn =
        conn
        |> post(~p"/register", %{"user" => %{}})

      assert html_response(conn, 200) =~ "Sign up"
    end
  end
end
