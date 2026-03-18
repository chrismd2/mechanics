defmodule Mechanics.ListingsTest do
  use Mechanics.DataCase, async: true

  alias Mechanics.Listings
  alias Mechanics.Accounts

  @customer_attrs %{
    "email" => "customer@example.com",
    "name" => "Test Customer",
    "password" => "secret123",
    "password_confirmation" => "secret123",
    "roles" => ["customer"]
  }

  @valid_attrs %{
    "title" => "Oil change",
    "description" => "Standard oil change service",
    "price_cents" => 5_000,
    "currency" => "USD",
    "customer_id" => "123e4567-e89b-12d3-a456-426614174000" # this assumes a customer exists with this id
  }

  @update_attrs %{
    "title" => "Premium oil change",
    "description" => "Synthetic oil + filter",
    "price_cents" => 7_500,
    "currency" => "USD",
    "customer_id" => "23e4567-e89b-12d3-a456-426614174000" # this assumes a customer exists with this id
  }

  @invalid_attrs %{
    "title" => nil,
    "description" => nil,
    "price_cents" => nil,
    "currency" => nil,
    "customer_id" => nil
  }

  describe "listings" do
    setup do
      {:ok, customer} = Accounts.create_user(@customer_attrs)
      %{customer: customer}
    end

    test "list_listings/0 returns listings ordered by inserted_at descending", %{customer: customer} do
      first_inserted_at = DateTime.utc_now()
      second_inserted_at = DateTime.add(first_inserted_at, 1, :second)

      first =
        insert_listing!(%{
          title: @valid_attrs["title"],
          description: @valid_attrs["description"],
          price_cents: @valid_attrs["price_cents"],
          currency: @valid_attrs["currency"],
          customer_id: customer.id,
          inserted_at: first_inserted_at,
          updated_at: first_inserted_at
        })

      second =
        insert_listing!(%{
          title: "Tire rotation",
          description: @valid_attrs["description"],
          price_cents: @valid_attrs["price_cents"],
          currency: @valid_attrs["currency"],
          customer_id: customer.id,
          inserted_at: second_inserted_at,
          updated_at: second_inserted_at
        })

      listings = Listings.list_listings()

      assert length(listings) == 2
      assert hd(listings).id == second.id
      assert Enum.at(listings, 1).id == first.id
    end

    test "get_listing!/1 returns the listing with given id", %{customer: customer} do
      attrs = Map.put(@valid_attrs, "customer_id", customer.id)
      {:ok, listing} = Listings.create_listing(attrs)
      assert Listings.get_listing!(listing.id).id == listing.id
    end

    test "create_listing/1 with valid data creates a listing", %{customer: customer} do
      attrs = Map.put(@valid_attrs, "customer_id", customer.id)
      assert {:ok, listing} = Listings.create_listing(attrs)
      assert listing.title == @valid_attrs["title"]
    end

    test "create_listing/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Listings.create_listing(@invalid_attrs)
    end

    test "update_listing/2 with valid data updates the listing", %{customer: customer} do
      attrs = Map.put(@valid_attrs, "customer_id", customer.id)
      {:ok, listing} = Listings.create_listing(attrs)
      assert {:ok, listing} = Listings.update_listing(listing, @update_attrs)
      assert listing.title == @update_attrs["title"]
    end

    test "update_listing/2 with invalid data returns error changeset", %{customer: customer} do
      attrs = Map.put(@valid_attrs, "customer_id", customer.id)
      {:ok, listing} = Listings.create_listing(attrs)
      assert {:error, %Ecto.Changeset{}} = Listings.update_listing(listing, @invalid_attrs)
      assert listing.id == Listings.get_listing!(listing.id).id
    end

    test "delete_listing/1 deletes the listing", %{customer: customer} do
      attrs = Map.put(@valid_attrs, "customer_id", customer.id)
      {:ok, listing} = Listings.create_listing(attrs)
      assert {:ok, _listing} = Listings.delete_listing(listing)
      assert_raise Ecto.NoResultsError, fn -> Listings.get_listing!(listing.id) end
    end

    test "change_listing/1 returns a listing changeset", %{customer: customer} do
      attrs = Map.put(@valid_attrs, "customer_id", customer.id)
      {:ok, listing} = Listings.create_listing(attrs)
      assert %Ecto.Changeset{} = Listings.change_listing(listing)
    end

    test "list_listings_by/1 filters by customer_id, title, and exact fields", %{customer: customer} do
      {:ok, other_customer} =
        Accounts.create_user(%{
          @customer_attrs
          | "email" => "other-customer@example.com",
            "name" => "Other Customer"
        })

      first_inserted_at = DateTime.utc_now()
      second_inserted_at = DateTime.add(first_inserted_at, 1, :second)

      first_match =
        insert_listing!(%{
          title: "Oil Change Basic",
          description: @valid_attrs["description"],
          price_cents: @valid_attrs["price_cents"],
          currency: "USD",
          customer_id: customer.id,
          inserted_at: first_inserted_at,
          updated_at: first_inserted_at
        })

      second_match =
        insert_listing!(%{
          title: "OIL Change Premium",
          description: @valid_attrs["description"],
          price_cents: @valid_attrs["price_cents"],
          currency: "USD",
          customer_id: customer.id,
          inserted_at: second_inserted_at,
          updated_at: second_inserted_at
        })

      _wrong_currency =
        insert_listing!(%{
          title: "Oil Change Euro",
          description: @valid_attrs["description"],
          price_cents: @valid_attrs["price_cents"],
          currency: "EUR",
          customer_id: customer.id
        })

      _wrong_customer =
        insert_listing!(%{
          title: "Oil Change Other Customer",
          description: @valid_attrs["description"],
          price_cents: @valid_attrs["price_cents"],
          currency: "USD",
          customer_id: other_customer.id
        })

      _wrong_title =
        insert_listing!(%{
          title: "Brake Repair",
          description: @valid_attrs["description"],
          price_cents: @valid_attrs["price_cents"],
          currency: "USD",
          customer_id: customer.id
        })

      listings =
        Listings.list_listings_by(%{
          customer_id: customer.id,
          title: "oil change",
          currency: "USD"
        })

      assert Enum.map(listings, & &1.id) == [second_match.id, first_match.id]
    end
  end
end
