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
    "state" => "AZ",
    # profiles are tied to a customer (uuid) and a mechanic user (uuid)
    "customer_id" => "123e4567-e89b-12d3-a456-426614174000"
  }

  describe "profile listings for mechanics" do
    test "list_mechanic_profiles/0 returns only mechanics with profiles, ordered by inserted_at desc" do
      {:ok, customer} = Accounts.create_user(@customer_attrs)
      assert customer.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok

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

      assert first_mechanic.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok
      assert second_mechanic.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok

      {:ok, _p1} =
        Profiles.create_profile(
          Map.merge(@profile_attrs, %{
            "user_id" => first_mechanic.id,
            "customer_id" => customer.id,
            "is_public" => true
          })
        )

      {:ok, _p2} =
        Profiles.create_profile(
          Map.merge(@profile_attrs, %{
            "user_id" => second_mechanic.id,
            "customer_id" => customer.id,
            "headline" => "Shop mechanic",
            "is_public" => true
          })
        )

      profiles = Profiles.list_mechanic_profiles()

      assert length(profiles) == 2
      assert hd(profiles).user_id == second_mechanic.id
      assert Enum.at(profiles, 1).user_id == first_mechanic.id
    end

    test "list_mechanic_profiles/0 returns empty when no mechanic profiles exist" do
      assert Profiles.list_mechanic_profiles() == []
    end

    test "list_mechanic_profiles/0 excludes users without mechanic role" do
      {:ok, customer} = Accounts.create_user(@customer_attrs)
      {:ok, mechanic} = Accounts.create_user(@mechanic_attrs)

      assert customer.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok
      assert mechanic.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok

      {:ok, _customer_profile} =
        Profiles.create_profile(
          Map.merge(@profile_attrs, %{
            "user_id" => customer.id,
            "customer_id" => customer.id,
            "headline" => "Customer profile",
            "is_public" => true
          })
        )

      {:ok, _mechanic_profile} =
        Profiles.create_profile(
          Map.merge(@profile_attrs, %{
            "user_id" => mechanic.id,
            "customer_id" => customer.id,
            "headline" => "Mechanic profile",
            "is_public" => true
          })
        )

      profiles = Profiles.list_mechanic_profiles()

      assert length(profiles) == 1
      assert hd(profiles).user_id == mechanic.id
    end

    test "list_mechanic_profiles/0 excludes mechanic profiles that are not public" do
      {:ok, customer} = Accounts.create_user(@customer_attrs)

      {:ok, mechanic} =
        Accounts.create_user(%{
          @mechanic_attrs
          | "email" => "private@example.com",
            "name" => "Private Mechanic"
        })

      assert customer.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok
      assert mechanic.id |> to_string() |> Ecto.UUID.cast() |> elem(0) == :ok

      {:ok, _profile} =
        Profiles.create_profile(
          Map.merge(@profile_attrs, %{
            "user_id" => mechanic.id,
            "customer_id" => customer.id,
            "is_public" => false
          })
        )

      assert Profiles.list_mechanic_profiles() == []
    end
  end
end

