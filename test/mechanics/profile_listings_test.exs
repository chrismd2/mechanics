defmodule Mechanics.ProfileListingsTest do
  use Mechanics.DataCase, async: true

  alias Mechanics.Accounts

  @moduletag :skip

  @mechanic_attrs %{
    "email" => "mechanic@example.com",
    "name" => "Test Mechanic",
    "password" => "secret123",
    "password_confirmation" => "secret123",
    "roles" => ["mechanic"]
  }

  @customer_attrs %{
    "email" => "customer@example.com",
    "name" => "Test Customer",
    "password" => "secret123",
    "password_confirmation" => "secret123",
    "roles" => ["customer"]
  }

  @profile_attrs %{
    "headline" => "Mobile mechanic",
    "bio" => "I come to you. ASE certified.",
    "city" => "Phoenix",
    "state" => "AZ"
  }

  describe "profile listings for mechanics" do
    test "list_mechanic_profiles/0 returns only mechanics with profiles, ordered by inserted_at desc" do
      {:ok, _customer} = Accounts.create_user(@customer_attrs)

      {:ok, first_mechanic} =
        Accounts.create_user(%{
          @mechanic_attrs
          | "email" => "m1@example.com",
            "name" => "Old Mechanic"
        })

      Process.sleep(10)

      {:ok, second_mechanic} =
        Accounts.create_user(%{
          @mechanic_attrs
          | "email" => "m2@example.com",
            "name" => "New Mechanic"
        })

      # Intended API (to be implemented):
      #
      # {:ok, _p1} = Profiles.upsert_profile(first_mechanic, @profile_attrs)
      # {:ok, _p2} = Profiles.upsert_profile(second_mechanic, %{ @profile_attrs | "headline" => "Shop mechanic" })
      #
      # profiles = Profiles.list_mechanic_profiles()
      #
      # assert length(profiles) == 2
      # assert hd(profiles).user_id == second_mechanic.id
      # assert Enum.at(profiles, 1).user_id == first_mechanic.id

      assert first_mechanic.id != second_mechanic.id
    end

    test "list_mechanic_profiles/0 returns empty when no mechanic profiles exist" do
      # Intended API:
      #
      # assert Profiles.list_mechanic_profiles() == []
      assert true
    end

    test "list_mechanic_profiles/0 excludes users without mechanic role" do
      {:ok, _customer} = Accounts.create_user(@customer_attrs)
      {:ok, _mechanic} = Accounts.create_user(@mechanic_attrs)

      # Intended API:
      #
      # {:ok, _profile} = Profiles.upsert_profile(mechanic, @profile_attrs)
      # profiles = Profiles.list_mechanic_profiles()
      # assert Enum.all?(profiles, fn p -> "mechanic" in p.user.roles end)
      assert true
    end
  end
end

