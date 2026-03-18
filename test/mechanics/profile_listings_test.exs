defmodule Mechanics.ProfileListingsTest do
  use Mechanics.DataCase, async: true

  alias Mechanics.Accounts
  alias Mechanics.Profiles

  @mechanic_attrs %{
    "email" => "mechanic@example.com",
    "name" => "Test Mechanic",
    "password" => "secret123",
    "password_confirmation" => "secret123",
    "roles" => ["mechanic"]
  }

  @profile_attrs %{
    "headline" => "Mobile mechanic",
    "bio" => "I come to you. ASE certified.",
    "city" => "Phoenix",
    "state" => "AZ"
  }

  describe "profile listings for mechanics" do
    test "list_mechanic_profiles/0 returns only mechanics with profiles, ordered by inserted_at desc" do
      first_mechanic_inserted_at = DateTime.utc_now()
      second_mechanic_inserted_at = DateTime.add(first_mechanic_inserted_at, 1, :second)

      first_mechanic =
        insert_user!(%{
          email: "m1@example.com",
          name: "Old Mechanic",
          roles: ["mechanic"],
          inserted_at: first_mechanic_inserted_at,
          updated_at: first_mechanic_inserted_at
        })

      second_mechanic =
        insert_user!(%{
          email: "m2@example.com",
          name: "New Mechanic",
          roles: ["mechanic"],
          inserted_at: second_mechanic_inserted_at,
          updated_at: second_mechanic_inserted_at
        })

      first_profile_inserted_at = DateTime.add(second_mechanic_inserted_at, 1, :second)
      second_profile_inserted_at = DateTime.add(first_profile_inserted_at, 1, :second)

      insert_profile!(%{
        headline: @profile_attrs["headline"],
        bio: @profile_attrs["bio"],
        city: @profile_attrs["city"],
        state: @profile_attrs["state"],
        user_id: first_mechanic.id,
        is_public: true,
        inserted_at: first_profile_inserted_at,
        updated_at: first_profile_inserted_at
      })

      insert_profile!(%{
        headline: "Shop mechanic",
        bio: @profile_attrs["bio"],
        city: @profile_attrs["city"],
        state: @profile_attrs["state"],
        user_id: second_mechanic.id,
        is_public: true,
        inserted_at: second_profile_inserted_at,
        updated_at: second_profile_inserted_at
      })

      profiles = Profiles.list_mechanic_profiles()

      assert length(profiles) == 2
      assert hd(profiles).user_id == second_mechanic.id
      assert Enum.at(profiles, 1).user_id == first_mechanic.id
    end

    test "list_mechanic_profiles/0 returns empty when no mechanic profiles exist" do
      assert Profiles.list_mechanic_profiles() == []
    end

    test "list_mechanic_profiles/0 excludes users without mechanic role" do
      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "customer@example.com",
          "name" => "Test Customer",
          "password" => "secret123",
          "password_confirmation" => "secret123",
          "roles" => ["customer"]
        })

      {:ok, mechanic} = Accounts.create_user(@mechanic_attrs)

      assert customer.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok
      assert mechanic.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok

      {:ok, _customer_profile} =
        Profiles.create_profile(
          Map.merge(@profile_attrs, %{
            "user_id" => customer.id,
            "headline" => "Customer profile",
            "is_public" => true
          })
        )

      {:ok, _mechanic_profile} =
        Profiles.create_profile(
          Map.merge(@profile_attrs, %{
            "user_id" => mechanic.id,
            "headline" => "Mechanic profile",
            "is_public" => true
          })
        )

      profiles = Profiles.list_mechanic_profiles()

      assert length(profiles) == 1
      assert hd(profiles).user_id == mechanic.id
    end

    test "list_mechanic_profiles/0 excludes mechanic profiles that are not public" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          @mechanic_attrs
          | "email" => "private@example.com",
            "name" => "Private Mechanic"
        })

      assert mechanic.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok

      {:ok, _profile} =
        Profiles.create_profile(
          Map.merge(@profile_attrs, %{
            "user_id" => mechanic.id,
            "is_public" => false
          })
        )

      assert Profiles.list_mechanic_profiles() == []
    end
  end
end

