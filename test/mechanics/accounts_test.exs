defmodule Mechanics.AccountsTest do
  use Mechanics.DataCase, async: true

  alias Mechanics.Accounts

  @valid_attrs %{
    "email" => "user@example.com",
    "name" => "Test User",
    "password" => "secret123",
    "password_confirmation" => "secret123",
    "roles" => ["mechanic"]
  }

  describe "database roles" do
    test "a user can be both mechanic and customer" do
      {:ok, both} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "both@example.com",
            "roles" => ["mechanic", "customer"]
        })

      mechanics = Accounts.list_mechanics()
      customers = Accounts.list_customers()

      assert Enum.any?(mechanics, &(&1.id == both.id))
      assert Enum.any?(customers, &(&1.id == both.id))

      assert "mechanic" in both.roles
      assert "customer" in both.roles
    end

    test "list_mechanics returns only users with role mechanic" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "m1@example.com",
            "roles" => ["mechanic"]
        })

      {:ok, _customer} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "c1@example.com",
            "roles" => ["customer"]
        })

      mechanics = Accounts.list_mechanics()

      assert length(mechanics) == 1
      assert hd(mechanics).id == mechanic.id
      assert "mechanic" in hd(mechanics).roles
    end

    test "list_customers returns only users with role customer" do
      {:ok, _mechanic} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "m2@example.com",
            "roles" => ["mechanic"]
        })

      {:ok, customer} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "c2@example.com",
            "roles" => ["customer"]
        })

      customers = Accounts.list_customers()

      assert length(customers) == 1
      assert hd(customers).id == customer.id
      assert "customer" in hd(customers).roles
    end

    test "list_mechanics orders by inserted_at descending" do
      {:ok, first} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "old@example.com",
            "roles" => ["mechanic"]
        })

      # ensure second is inserted later
      Process.sleep(10)

      {:ok, second} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "new@example.com",
            "roles" => ["mechanic"]
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
            "roles" => ["customer"]
        })

      Process.sleep(10)

      {:ok, second} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "newc@example.com",
            "roles" => ["customer"]
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
