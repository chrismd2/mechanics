defmodule MechanicsWeb.AuthControllerTest do
  use MechanicsWeb.ConnCase
  import Swoosh.TestAssertions

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

  describe "GET /password/reset" do
    test "returns 200 and shows reset password heading", %{conn: conn} do
      conn = get(conn, ~p"/password/reset")

      html = html_response(conn, 200)
      assert html =~ "Reset your password"

      parsed = Floki.parse_document!(html)
      form = Floki.find(parsed, "form[action=\"/password/reset\"]") |> List.first()
      assert form != nil
      assert Floki.attribute(form, "method") |> List.first() =~ "post"

      submit_buttons = Floki.find(form, "button[type=\"submit\"], input[type=\"submit\"]")
      assert submit_buttons != []
    end
  end

  describe "GET /password/reset?token=..." do
    setup :set_swoosh_global

    test "with a valid token renders form to set new password (including eye-ball toggles)", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      email = "token_valid@example.com"

      {:ok, user} =
        Mechanics.Accounts.create_user(%{
          "email" => email,
          "name" => "Token Valid User",
          "roles" => ["customer"],
          "password" => "secret123",
          "password_confirmation" => "secret123"
        })

      assert {:ok, :sent} = Mechanics.Accounts.request_password_reset(user.email, now)
      assert_receive {:email, sent_email}
      assert sent_email.text_body =~ "/password/reset?token="

      [_, token] = Regex.run(~r/token=([^\s]+)/, sent_email.text_body)

      conn = get(conn, "/password/reset?token=#{token}")
      html = html_response(conn, 200)
      assert html =~ "Reset your password"

      parsed = Floki.parse_document!(html)
      form = Floki.find(parsed, "form[action=\"/password/reset/confirm\"]") |> List.first()
      assert form != nil

      assert Floki.find(form, "input#password_reset_password") != []
      assert Floki.find(form, "input#password_reset_password_confirmation") != []

      # From registration: two password toggle buttons (one per password field).
      toggle_buttons = Floki.find(form, "button.password-toggle-btn[aria-label=\"Show password\"]")
      assert length(toggle_buttons) == 2

      assert Floki.find(form, "button[type=\"submit\"]") != []
    end

    test "with an expired token redirects to sign-in", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      email = "token_expired@example.com"

      {:ok, user} =
        Mechanics.Accounts.create_user(%{
          "email" => email,
          "name" => "Token Expired User",
          "roles" => ["customer"],
          "password" => "secret123",
          "password_confirmation" => "secret123"
        })

      assert {:ok, :sent} = Mechanics.Accounts.request_password_reset(user.email, now)
      assert_receive {:email, sent_email}

      [_, token] = Regex.run(~r/token=([^\s]+)/, sent_email.text_body)

      reset_token = Mechanics.Repo.get_by(Mechanics.Accounts.PasswordResetToken, token: token)
      assert reset_token

      Mechanics.Repo.update!(
        Ecto.Changeset.change(reset_token, %{
          expires_at: DateTime.add(now, -1, :hour) |> DateTime.truncate(:second)
        })
      )

      conn = get(conn, "/password/reset?token=#{token}")
      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) ==
               "If you have an account with us, then we'll send you a reset request."
    end

    test "submitting a valid token resets password and consumes the token", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      email = "token_reset@example.com"
      new_password = "newsecret123"

      {:ok, user} =
        Mechanics.Accounts.create_user(%{
          "email" => email,
          "name" => "Token Reset User",
          "roles" => ["customer"],
          "password" => "secret123",
          "password_confirmation" => "secret123"
        })

      assert {:ok, :sent} = Mechanics.Accounts.request_password_reset(user.email, now)
      assert_receive {:email, sent_email}

      [_, token] = Regex.run(~r/token=([^\s]+)/, sent_email.text_body)

      conn =
        post(conn, ~p"/password/reset/confirm", %{
          "password_reset" => %{
            "token" => token,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) == "Password reset successful. You can sign in now."

      assert {:ok, _} = Mechanics.Accounts.authenticate_user(email, new_password)
      assert Mechanics.Repo.get_by(Mechanics.Accounts.PasswordResetToken, token: token) == nil
    end
  end

  describe "POST /password/reset" do
    setup :set_swoosh_global

    test "redirects to sign-in with ambiguous message for unknown email and does not send email", %{
      conn: conn
    } do
      conn =
        post(conn, ~p"/password/reset", %{
          "password_reset" => %{
            "email" => "unknown@example.com"
          }
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) ==
               "If you have an account with us, then we'll send you a reset request."
      refute_email_sent()
    end

    test "redirects to sign-in with ambiguous message and sends reset email when allowed", %{
      conn: conn
    } do
      email = "reset_allowed@example.com"

      {:ok, user} =
        Mechanics.Accounts.create_user(%{
          "email" => email,
          "name" => "Reset Allowed User",
          "roles" => ["customer"],
          "password" => "secret123",
          "password_confirmation" => "secret123"
        })

      conn =
        post(conn, ~p"/password/reset", %{
          "password_reset" => %{
            "email" => user.email
          }
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) ==
               "If you have an account with us, then we'll send you a reset request."

      assert_email_sent(fn sent_email ->
        sent_email.text_body =~ "/password/reset?token="
      end)

      updated = Mechanics.Accounts.get_user_by_email(email)
      assert updated.password_reset_count == 1
      assert updated.password_reset_last_sent_at
    end

    test "redirects to sign-in with ambiguous message and blocks limited resets", %{conn: conn} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      email = "reset_limited@example.com"

      {:ok, user} =
        Mechanics.Accounts.create_user(%{
          "email" => email,
          "name" => "Reset Limited User",
          "roles" => ["customer"],
          "password" => "secret123",
          "password_confirmation" => "secret123"
        })

      last_sent_at = DateTime.add(now, -1, :hour) |> DateTime.truncate(:second)

      Mechanics.Repo.update!(
        Ecto.Changeset.change(user, %{
          password_reset_count: 3,
          password_reset_last_sent_at: last_sent_at
        })
      )

      conn =
        post(conn, ~p"/password/reset", %{
          "password_reset" => %{
            "email" => email
          }
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) ==
               "If you have an account with us, then we'll send you a reset request."
      refute_email_sent()

      updated = Mechanics.Accounts.get_user_by_email(email)
      assert updated.password_reset_count == 3
      assert updated.password_reset_last_sent_at == last_sent_at
    end

    test "redirects to sign-in with ambiguous message and allows reset after 6+ hours", %{
      conn: conn
    } do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      email = "reset_after_window@example.com"

      {:ok, user} =
        Mechanics.Accounts.create_user(%{
          "email" => email,
          "name" => "Reset After Window User",
          "roles" => ["customer"],
          "password" => "secret123",
          "password_confirmation" => "secret123"
        })

      last_sent_at = DateTime.add(now, -7, :hour) |> DateTime.truncate(:second)

      Mechanics.Repo.update!(
        Ecto.Changeset.change(user, %{
          password_reset_count: 3,
          password_reset_last_sent_at: last_sent_at
        })
      )

      conn =
        post(conn, ~p"/password/reset", %{
          "password_reset" => %{
            "email" => email
          }
        })

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns[:flash], :info) ==
               "If you have an account with us, then we'll send you a reset request."

      assert_email_sent(fn sent_email ->
        sent_email.text_body =~ "/password/reset?token="
      end)

      updated = Mechanics.Accounts.get_user_by_email(email)
      assert updated.password_reset_count == 1

      # Controller uses its own `utc_now` (truncated to seconds), so allow the
      # updated timestamp to be within 0-1 seconds of the test's `now`.
      diff = abs(DateTime.diff(updated.password_reset_last_sent_at, now, :second))
      assert diff <= 1
    end
  end

  describe "POST /login (sign in)" do
    @login_email "signinuser@example.com"
    @login_password "secret123"

    setup do
      # Login lockout state is stored in a global ETS table, so clear it per-test
      # to avoid cross-test leakage (and potential parallel execution ordering).
      Mechanics.LoginAttempts.init()
      Mechanics.LoginAttempts.clear_all()

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
      assert html_response(conn, 200) =~ "Please try again later."
      refute get_session(conn, :current_user_id)
    end
  end
end
