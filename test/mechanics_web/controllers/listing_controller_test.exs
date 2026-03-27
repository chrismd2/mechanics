defmodule MechanicsWeb.ListingControllerTest do
  use MechanicsWeb.ConnCase

  alias Mechanics.Accounts
  alias Mechanics.Listings
  alias Mechanics.Repo

  defp create_customer(conn) do
    suffix = System.unique_integer([:positive])
    email = "customer-listing-#{suffix}@example.com"

    {:ok, customer} =
      Accounts.create_user(%{
        "email" => email,
        "name" => "Listing Customer",
        "roles" => ["customer"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    customer =
      customer
      |> Ecto.Changeset.change(email_verified: true)
      |> Repo.update!()

    conn = init_test_session(conn, %{current_user_id: customer.id})
    {:ok, conn: conn, customer: customer}
  end

  describe "GET /listings/new" do
    test "returns the listing creation page (customer only)", %{conn: conn} do
      {:ok, conn: conn, customer: _customer} = create_customer(conn)

      conn = get(conn, ~p"/listings/new")
      html = html_response(conn, 200)

      assert html =~ "Create a new job listing"

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "form[action='/listings'][method='post']") != []

      assert Floki.find(parsed, "input#listing_title[name='listing[title]']") != []
      assert Floki.find(parsed, "textarea#listing_description[name='listing[description]']") != []
      assert Floki.find(parsed, "input#listing_price_cents[name='listing[price_cents]']") != []
      assert Floki.find(parsed, "input#listing_currency[name='listing[currency]']") != []
      assert Floki.find(parsed, "input#listing_is_public[type='checkbox'][name='listing[is_public]']") != []
      assert Floki.find(parsed, "input#listing_warranty_disclaimer[type='checkbox'][name='listing[warranty_disclaimer_accepted]']") != []

      assert Regex.match?(~r/<button[^>]*id="listing_submit"[^>]*\sdisabled(?:\s|=|>)/, html)
    end

    test "redirects home when not a customer", %{conn: conn} do
      {:ok, _user} =
        Accounts.create_user(%{
          "email" => "not-a-customer@example.com",
          "name" => "Not a Customer",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn = get(conn, ~p"/listings/new")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /listings" do
    test "creates a public listing and redirects to home", %{conn: conn} do
      {:ok, conn: conn, customer: customer} = create_customer(conn)

      conn = get(conn, ~p"/listings/new")

      conn =
        post(conn, ~p"/listings", %{
          "listing" => %{
            "title" => "Brake pad replacement",
            "description" => "Need front brake pads replaced this week.",
            "price_cents" => 12_500,
            "currency" => "USD",
            "is_public" => "true",
            "warranty_disclaimer_accepted" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/"

      html = html_response(get(conn, ~p"/"), 200)
      assert html =~ "Brake pad replacement"
      assert html =~ "12500 USD"

      # Owner can edit from the homepage.
      listing =
        Enum.find(Listings.list_public_listings(), fn l ->
          l.title == "Brake pad replacement" && l.customer_id == customer.id
        end)

      assert listing != nil

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "a[href='/listings/#{listing.id}/edit']") != []
    end

    test "creates a private listing that does not show on the home page", %{conn: conn} do
      {:ok, conn: conn, customer: _customer} = create_customer(conn)

      conn = get(conn, ~p"/listings/new")

      conn =
        post(conn, ~p"/listings", %{
          "listing" => %{
            "title" => "Hidden listing",
            "description" => "Should not appear on the home page.",
            "price_cents" => 1_000,
            "currency" => "USD",
            "is_public" => "false",
            "warranty_disclaimer_accepted" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/"

      html = html_response(get(conn, ~p"/"), 200)
      refute html =~ "Hidden listing"
    end
  end

  describe "GET /listings/:id/edit" do
    test "owner can view the edit page", %{conn: conn} do
      {:ok, conn: conn, customer: customer} = create_customer(conn)

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Tire rotation",
          "description" => "Rotate tires.",
          "price_cents" => 25_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      conn = get(conn, ~p"/listings/#{listing.id}/edit")
      html = html_response(conn, 200)
      assert html =~ "Edit your job listing"

      assert html =~ ~s(value="Tire rotation")
      assert html =~ "Rotate tires."

      parsed = Floki.parse_document!(html)
      listing_checkbox = Floki.find(parsed, "input#listing_is_public[type='checkbox']")
      assert listing_checkbox != []

      warranty_checkbox =
        Floki.find(parsed, "input#listing_warranty_disclaimer[type='checkbox'][name='listing[warranty_disclaimer_accepted]']")

      assert warranty_checkbox != []
      assert Regex.match?(~r/<button[^>]*id="listing_submit"[^>]*\sdisabled(?:\s|=|>)/, html)
    end

    test "non-owner gets redirected home", %{conn: conn} do
      {:ok, conn: conn, customer: customer} = create_customer(conn)

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Private work",
          "description" => "Owner-only edit.",
          "price_cents" => 99_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      {:ok, other_customer} =
        Accounts.create_user(%{
          "email" => "other-customer-#{System.unique_integer([:positive])}@example.com",
          "name" => "Other Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn = init_test_session(conn, %{current_user_id: other_customer.id})

      conn = get(conn, ~p"/listings/#{listing.id}/edit")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /listings/:id" do
    test "owner can update a listing and toggling is_public affects home page visibility", %{conn: conn} do
      {:ok, conn: conn, customer: customer} = create_customer(conn)

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Public listing",
          "description" => "Visible on home.",
          "price_cents" => 20_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      conn = get(conn, ~p"/listings/#{listing.id}/edit")

      conn =
        post(conn, ~p"/listings/#{listing.id}", %{
          "listing" => %{
            "title" => "Now private listing",
            "description" => "Should disappear from home.",
            "price_cents" => 20_000,
            "currency" => "USD",
            "is_public" => "false",
            "warranty_disclaimer_accepted" => "true"
          }
        })

      assert redirected_to(conn) == ~p"/"

      html = html_response(get(conn, ~p"/"), 200)
      refute html =~ "Now private listing"
      refute html =~ "Public listing"
    end
  end
end
