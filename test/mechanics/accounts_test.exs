defmodule Mechanics.AccountsTest do
  use Mechanics.DataCase, async: true

  alias Mechanics.Accounts

  @valid_attrs %{
    "email" => "user@example.com",
    "name" => "Test User",
    "password" => "secret123",
    "password_confirmation" => "secret123",
    "role" => "mechanic"
  }

  describe "database roles" do
    test "list_mechanics returns only users with role mechanic" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "m1@example.com",
            "role" => "mechanic"
        })

      {:ok, _customer} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "c1@example.com",
            "role" => "customer"
        })

      mechanics = Accounts.list_mechanics()

      assert length(mechanics) == 1
      assert hd(mechanics).id == mechanic.id
      assert hd(mechanics).role == "mechanic"
    end

    test "list_customers returns only users with role customer" do
      {:ok, _mechanic} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "m2@example.com",
            "role" => "mechanic"
        })

      {:ok, customer} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "c2@example.com",
            "role" => "customer"
        })

      customers = Accounts.list_customers()

      assert length(customers) == 1
      assert hd(customers).id == customer.id
      assert hd(customers).role == "customer"
    end

    test "list_mechanics orders by inserted_at descending" do
      {:ok, first} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "old@example.com",
            "role" => "mechanic"
        })

      # ensure second is inserted later
      Process.sleep(10)

      {:ok, second} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "new@example.com",
            "role" => "mechanic"
        })

      mechanics = Accounts.list_mechanics()

      assert length(mechanics) == 2
      assert hd(mechanics).id == second.id
      assert Enum.at(mechanics, 1).id == first.id
    end

    test "list_customers orders by inserted_at descending" do
      {:ok, first} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "oldc@example.com",
            "role" => "customer"
        })

      Process.sleep(10)

      {:ok, second} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "newc@example.com",
            "role" => "customer"
        })

      customers = Accounts.list_customers()

      assert length(customers) == 2
      assert hd(customers).id == second.id
      assert Enum.at(customers, 1).id == first.id
    end

    test "list_mechanics returns empty when no mechanics exist" do
      assert Accounts.list_mechanics() == []
    end

    test "list_customers returns empty when no customers exist" do
      assert Accounts.list_customers() == []
    end
  end
end
