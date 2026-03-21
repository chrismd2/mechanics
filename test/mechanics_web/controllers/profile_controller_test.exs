defmodule MechanicsWeb.ProfileControllerTest do
  use MechanicsWeb.ConnCase

  alias Mechanics.Accounts
  alias Mechanics.Profiles

  defp create_mechanic_user(conn) do
    {:ok, mechanic} =
      Accounts.create_user(%{
        "email" => "mechanic@example.com",
        "name" => "Test Mechanic",
        "roles" => ["mechanic"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    conn = init_test_session(conn, %{current_user_id: mechanic.id})
    {:ok, conn: conn, mechanic: mechanic}
  end

  describe "GET /profile" do
    test "shows create heading when the mechanic has no existing profile", %{conn: conn} do
      {:ok, conn: conn, mechanic: _mechanic} = create_mechanic_user(conn)

      conn = get(conn, ~p"/profile")
      html = html_response(conn, 200)
      assert html =~ "Create your mechanic profile"

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "form[action='/profile'][method='post']") != []

      assert Floki.find(parsed, "input#profile_headline[name='profile[headline]']") != []
      assert Floki.find(parsed, "textarea#profile_bio[name='profile[bio]']") != []
      assert Floki.find(parsed, "input#profile_city[name='profile[city]']") != []
      assert Floki.find(parsed, "input#profile_state[name='profile[state]']") != []
      assert Floki.find(parsed, "input#profile_is_public[type='checkbox'][name='profile[is_public]']") != []
    end

    test "shows edit heading when the mechanic has an existing profile", %{conn: conn} do
      {:ok, conn: conn, mechanic: mechanic} = create_mechanic_user(conn)

      {:ok, _profile} =
        Profiles.create_profile(%{
          "headline" => "Old mechanic",
          "bio" => "Old bio.",
          "city" => "Mesa",
          "state" => "AZ",
          "is_public" => false,
          "user_id" => mechanic.id
        })

      conn = get(conn, ~p"/profile")
      html = html_response(conn, 200)
      assert html =~ "Edit your mechanic profile"

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "form[action='/profile'][method='post']") != []
      assert Floki.find(parsed, "input#profile_headline[name='profile[headline]']") != []
      assert Floki.find(parsed, "textarea#profile_bio[name='profile[bio]']") != []
      assert Floki.find(parsed, "input#profile_city[name='profile[city]']") != []
      assert Floki.find(parsed, "input#profile_state[name='profile[state]']") != []
      assert Floki.find(parsed, "input#profile_is_public[type='checkbox'][name='profile[is_public]']") != []
    end

    test "liability disclaimer checkbox disables the submit button", %{conn: conn} do
      {:ok, conn: conn, mechanic: _mechanic} = create_mechanic_user(conn)
      conn = get(conn, ~p"/profile")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      liability_checkbox = Floki.find(parsed, "input#profile_liability_disclaimer[type='checkbox']")
      assert liability_checkbox != []

      assert Regex.match?(
               ~r/<button[^>]*id="profile_submit"[^>]*\sdisabled(?:\s|=|>)/,
               html
             )
    end

    test "auto-populates the form with the latest mechanic profile data", %{conn: conn} do
      {:ok, conn: conn, mechanic: mechanic} = create_mechanic_user(conn)

      {:ok, old_profile} =
        Profiles.create_profile(%{
          "headline" => "Old mechanic",
          "bio" => "Old bio.",
          "city" => "Mesa",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      {:ok, _updated_profile} =
        Profiles.update_profile(old_profile, %{
          "headline" => "Mobile brake specialist",
          "bio" => "I travel to you for brake and rotor work.",
          "city" => "Phoenix",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      conn = get(conn, ~p"/profile")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert html =~ ~s(value="Mobile brake specialist")
      assert html =~ "I travel to you for brake and rotor work."
      assert html =~ ~s(value="Phoenix")
      assert html =~ ~s(value="AZ")
      refute html =~ ~s(value="Old mechanic")
      refute html =~ "Old bio."

      public_checkbox = Floki.find(parsed, "input#profile_is_public[type='checkbox'][name='profile[is_public]']")
      assert public_checkbox != []

      assert Enum.any?(public_checkbox, fn {_tag, attrs, _children} ->
               Enum.any?(attrs, fn {k, _v} -> k == "checked" end)
             end)
    end
  end

  describe "POST /profile" do
    test "submitting with liability accepted redirects to home", %{conn: conn} do
      {:ok, conn: conn, mechanic: mechanic} = create_mechanic_user(conn)

      # Ensure the CSRF token is initialized on the conn.
      conn = get(conn, ~p"/profile")

      conn =
        post(conn, ~p"/profile", %{
          "profile" => %{
            "headline" => "Mobile brake specialist",
            "bio" => "I travel to you for brake and rotor work.",
            "city" => "Phoenix",
            "state" => "AZ",
            "is_public" => "true",
            "liability_disclaimer_accepted" => "true",
            "user_id" => mechanic.id
          }
        })

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to account when return_to is /account", %{conn: conn} do
      {:ok, conn: conn, mechanic: mechanic} = create_mechanic_user(conn)

      conn = get(conn, ~p"/profile")

      conn =
        post(conn, ~p"/profile", %{
          "profile" => %{
            "headline" => "Mobile brake specialist",
            "bio" => "I travel to you for brake and rotor work.",
            "city" => "Phoenix",
            "state" => "AZ",
            "is_public" => "true",
            "liability_disclaimer_accepted" => "true",
            "return_to" => "/account",
            "user_id" => mechanic.id
          }
        })

      assert redirected_to(conn) == ~p"/account"
    end
  end
end
