defmodule MechanicsWeb.AccountControllerTest do
  use MechanicsWeb.ConnCase

  alias Mechanics.Accounts
  alias Mechanics.Accounts.User
  alias Mechanics.Chats
  alias Mechanics.Repo

  defp login(conn, user) do
    init_test_session(conn, %{current_user_id: user.id})
  end

  describe "GET /account" do
    test "redirects visitors to login" do
      conn = get(build_conn(), ~p"/account")
      assert redirected_to(conn) == ~p"/login"
    end

    test "renders notification and settings UI for a signed-in customer" do
      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "acct-cust-#{System.unique_integer([:positive])}@example.com",
          "name" => "Account Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      html =
        build_conn()
        |> login(customer)
        |> get(~p"/account")
        |> html_response(200)

      assert html =~ ~s(id="account-page")
      assert html =~ "Notification center"
      assert html =~ "Account settings"
      assert html =~ "Name and email"
      assert html =~ "Email me a reset link"
      refute html =~ "account_profile_headline"
    end

    test "includes mechanic profile fields when the user is a mechanic" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "acct-mech-#{System.unique_integer([:positive])}@example.com",
          "name" => "Account Mechanic",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      html =
        build_conn()
        |> login(mechanic)
        |> get(~p"/account")
        |> html_response(200)

      assert html =~ ~s(id="account_profile_headline")
      assert html =~ ~s(name="profile[return_to]")
      assert html =~ "/account"
    end

    test "lists conversation cards linking to chats when the user has messages" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "acct-m-#{System.unique_integer([:positive])}@example.com",
          "name" => "Card Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "acct-c2-#{System.unique_integer([:positive])}@example.com",
          "name" => "Card Cust",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
      {:ok, _} = Chats.create_message(chat.id, mechanic, %{body: "Hello from account test."})

      html =
        build_conn()
        |> login(customer)
        |> get(~p"/account")
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "#account-notification-cards") != []

      link = Floki.find(parsed, "#account-notification-cards a[href='/chats/#{chat.id}']")
      assert link != []
      assert Floki.text(hd(link)) =~ "Hello from account test."
    end
  end

  describe "header Welcome link" do
    test "points to the account page" do
      {:ok, user} =
        Accounts.create_user(%{
          "email" => "welcome-#{System.unique_integer([:positive])}@example.com",
          "name" => "Welcome User",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      html =
        build_conn()
        |> login(user)
        |> get(~p"/")
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      [welcome] = Floki.find(parsed, "#header-welcome")
      assert Floki.attribute(welcome, "href") == ["/account"]
    end
  end

  describe "PUT /account" do
    test "updates name and email then redirects back to account" do
      {:ok, user} =
        Accounts.create_user(%{
          "email" => "before-#{System.unique_integer([:positive])}@example.com",
          "name" => "Before Name",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn = build_conn() |> login(user)
      conn = get(conn, ~p"/account")

      conn =
        put(conn, ~p"/account", %{
          "account" => %{
            "name" => "After Name",
            "email" => "after-#{user.id}@example.com"
          }
        })

      assert redirected_to(conn) == ~p"/account"
      updated = Repo.get!(User, user.id)
      assert updated.name == "After Name"
      assert updated.email == "after-#{user.id}@example.com"
    end
  end

  describe "POST /account/password-reset" do
    test "redirects to account with an info flash" do
      {:ok, user} =
        Accounts.create_user(%{
          "email" => "pwreset-#{System.unique_integer([:positive])}@example.com",
          "name" => "Reset User",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn =
        build_conn()
        |> login(user)
        |> post(~p"/account/password-reset", %{})

      assert redirected_to(conn) == ~p"/account"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "reset instructions"
    end
  end
end
