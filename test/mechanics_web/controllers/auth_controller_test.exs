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

    test "has visible eye button to unhide password", %{conn: conn} do
      conn = get(conn, ~p"/register")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      buttons = Floki.find(parsed, "button, [role='button']")
      has_visibility_toggle =
        Enum.any?(buttons, fn el ->
          label =
            (Floki.attribute(el, "aria-label") |> List.first()) ||
              (Floki.attribute(el, "title") |> List.first()) || ""

          label_lower = String.downcase(label)
          String.contains?(label_lower, "password") and
            (String.contains?(label_lower, "show") or String.contains?(label_lower, "hide") or
               String.contains?(label_lower, "toggle") or String.contains?(label_lower, "visibility"))
        end)

      assert has_visibility_toggle,
             "expected a visible eye button (e.g. aria-label or title 'Show password') to unhide password on registration page"
    end
  end

  describe "POST /register (registration form submission)" do
    @valid_params %{
      "email" => "newuser@example.com",
      "name" => "Jane Doe",
      "roles" => ["customer", "mechanic"],
      "password" => "secret123",
      "password_confirmation" => "secret123",
      "wants_listing" => "false"
    }

    test "creates mechanic, sets session, and redirects to home with success flash when wants_listing is false", %{conn: conn} do
      conn =
        conn
        |> post(~p"/register", %{"user" => @valid_params})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) == "Account created successfully!"
      user_id = get_session(conn, :current_user_id)
      assert user_id

      user = Mechanics.Accounts.get_user!(user_id)
      assert is_list(user.roles)
      assert user.roles == ["customer", "mechanic"]
    end

    test "creates customer, sets session, and redirects to home with success flash when wants_listing is false", %{conn: conn} do
      params = Map.put(@valid_params, "roles", ["customer"])

      conn =
        conn
        |> post(~p"/register", %{"user" => params})

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) == "Account created successfully!"
      user_id = get_session(conn, :current_user_id)
      assert user_id

      user = Mechanics.Accounts.get_user!(user_id)
      assert is_list(user.roles)
      assert user.roles == ["customer"]
    end

    test "creates mechanic, sets session, and redirects to home with success flash when wants_listing is true", %{conn: conn} do
      conn =
        conn
        |> post(~p"/register", %{"user" => @valid_params |> Map.put("wants_listing", "true")})

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) == "Account created successfully!"
      user_id = get_session(conn, :current_user_id)
      assert user_id

      user = Mechanics.Accounts.get_user!(user_id)
      assert is_list(user.roles)
      assert user.roles == ["customer", "mechanic"]
    end

    test "creates customer, sets session, and redirects to create listings with success flash when wants_listing is true", %{conn: conn} do
      params = Map.put(@valid_params, "roles", ["customer"])
      |> Map.put("wants_listing", "true")

      conn =
        conn
        |> post(~p"/register", %{"user" => params})

      assert redirected_to(conn) == ~p"/listings/new"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) == "Account created successfully!"
      user_id = get_session(conn, :current_user_id)
      assert user_id

      user = Mechanics.Accounts.get_user!(user_id)
      assert is_list(user.roles)
      assert user.roles == ["customer"]
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

      assert redirected_to(conn)
    end

    test "re-renders form with errors when required fields are missing", %{conn: conn} do
      conn =
        conn
        |> post(~p"/register", %{"user" => %{}})

      assert html_response(conn, 200) =~ "Sign up"
    end
  end

  describe "GET /login (sign-in page)" do
    test "returns 200 and shows Sign in heading", %{conn: conn} do
      conn = get(conn, ~p"/login")
      assert html_response(conn, 200) =~ "Sign in"
    end

    test "shows sign-in form with email and password fields", %{conn: conn} do
      conn = get(conn, ~p"/login")
      html = html_response(conn, 200)
      assert html =~ "Email"
      assert html =~ "Password"
      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "input#session_email") != []
      assert Floki.find(parsed, "input#session_password") != []
    end

    test "has form that posts to /login", %{conn: conn} do
      conn = get(conn, ~p"/login")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      form = Floki.find(parsed, "form[action=\"/login\"]")
      assert form != []
      assert Floki.attribute(form, "method") |> List.first() =~ "post"
    end

    test "shows reset password link", %{conn: conn} do
      conn = get(conn, ~p"/login")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      links = Floki.find(parsed, "a[href=\"/password/reset\"]")
      assert links != [], "expected a link to /password/reset (Forgot password?)"
      assert html =~ "Forgot password?"
    end

    test "shows Sign up link for new users", %{conn: conn} do
      conn = get(conn, ~p"/login")
      html = html_response(conn, 200)
      assert html =~ "Don't have an account?"
      parsed = Floki.parse_document!(html)
      links = Floki.find(parsed, "a[href*=\"register\"]")
      assert links != []
    end

    test "has visible eye button to unhide password", %{conn: conn} do
      conn = get(conn, ~p"/login")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      buttons = Floki.find(parsed, "button, [role='button']")
      has_visibility_toggle =
        Enum.any?(buttons, fn el ->
          label =
            (Floki.attribute(el, "aria-label") |> List.first()) ||
              (Floki.attribute(el, "title") |> List.first()) || ""

          label_lower = String.downcase(label)
          String.contains?(label_lower, "password") and
            (String.contains?(label_lower, "show") or String.contains?(label_lower, "hide") or
               String.contains?(label_lower, "toggle") or String.contains?(label_lower, "visibility"))
        end)

      assert has_visibility_toggle,
             "expected a visible eye button (e.g. aria-label or title 'Show password') to unhide password on login page"
    end
  end

  describe "POST /login (sign in)" do
    @login_email "signinuser@example.com"
    @login_password "secret123"

    setup do
      {:ok, _user} =
        Mechanics.Accounts.create_user(%{
          "email" => @login_email,
          "name" => "Sign In User",
          "roles" => ["customer"],
          "password" => @login_password,
          "password_confirmation" => @login_password
        })

      :ok
    end

    test "with valid credentials sets session and redirects to home", %{conn: conn} do
      conn =
        conn
        |> post(~p"/login", %{"session" => %{"email" => @login_email, "password" => @login_password}})

      assert html_response(conn, 302) =~ "redirected"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) == "Welcome back!"
      assert get_session(conn, :current_user_id)
    end

    test "with invalid password re-renders sign-in with error", %{conn: conn} do
      conn =
        conn
        |> post(~p"/login", %{"session" => %{"email" => @login_email, "password" => "wrongpass"}})

      assert html_response(conn, 200) =~ "Sign in"
      assert html_response(conn, 200) =~ "Invalid email or password"
      refute get_session(conn, :current_user_id)
    end

    test "with unknown email re-renders sign-in with error", %{conn: conn} do
      conn =
        conn
        |> post(~p"/login", %{"session" => %{"email" => "unknown@example.com", "password" => "any"}})

      assert html_response(conn, 200) =~ "Sign in"
      assert html_response(conn, 200) =~ "Invalid email or password"
      refute get_session(conn, :current_user_id)
    end

    test "after 5 failed attempts shows lockout message and does not authenticate", %{conn: conn} do
      Mechanics.LoginAttempts.clear_all()
      locked_email = "lockout@example.com"

      # 5 failed attempts
      for _ <- 1..5 do
        post(conn, ~p"/login", %{"session" => %{"email" => locked_email, "password" => "wrong"}})
      end

      # 6th attempt gets lockout message
      conn =
        conn
        |> post(~p"/login", %{"session" => %{"email" => locked_email, "password" => "wrong"}})

      assert html_response(conn, 200) =~ "Sign in"
      assert html_response(conn, 200) =~ "Too many failed attempts"
      refute get_session(conn, :current_user_id)
    end
  end
end
