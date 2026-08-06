defmodule MechanicsWeb.InviteControllerTest do
  use MechanicsWeb.ConnCase

  import Ecto.Query

  alias Mechanics.Accounts
  alias Mechanics.Invites.Invite
  alias Mechanics.Listings
  alias Mechanics.Repo

  defp login(conn, user) do
    init_test_session(conn, %{current_user_id: user.id})
  end

  defp create_customer do
    suffix = System.unique_integer([:positive])

    {:ok, customer} =
      Accounts.create_user(%{
        "email" => "invite-owner-#{suffix}@example.com",
        "name" => "Invite Owner",
        "roles" => ["customer"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    customer
  end

  defp invites_for_listing(listing_id) do
    Repo.all(from i in Invite, where: i.listing_id == ^listing_id)
  end

  describe "POST /listings/:listing_id/invites" do
    test "owner can create a listing invite without an existing chat", %{conn: conn} do
      customer = create_customer()

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Need brakes",
          "description" => "Front pads",
          "price_cents" => 12_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => false
        })

      conn =
        conn
        |> login(customer)
        |> post(~p"/listings/#{listing.id}/invites")

      assert redirected_to(conn) == ~p"/account"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Invite link ready:"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "/invites/"

      assert [%Invite{subject_type: "listing", listing_id: listing_id, chat_id: nil}] =
               invites_for_listing(listing.id)

      assert listing_id == listing.id
    end

    test "redirects guests to login", %{conn: conn} do
      customer = create_customer()

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Guest cannot invite",
          "description" => "Needs auth",
          "price_cents" => 5_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      conn = post(conn, ~p"/listings/#{listing.id}/invites")
      assert redirected_to(conn) == ~p"/login"
    end

    test "non-owner cannot invite to a private listing", %{conn: conn} do
      owner = create_customer()
      other = create_customer()

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Private job",
          "description" => "Owner only invite",
          "price_cents" => 7_000,
          "currency" => "USD",
          "customer_id" => owner.id,
          "is_public" => false
        })

      conn =
        conn
        |> login(other)
        |> post(~p"/listings/#{listing.id}/invites")

      assert redirected_to(conn) == ~p"/account"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "cannot invite"
      assert invites_for_listing(listing.id) == []
    end
  end

  describe "GET /listings/:id/edit invite UI" do
    test "owner edit page includes a listing invite button", %{conn: conn} do
      customer = create_customer()

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Edit page invite",
          "description" => "Invite from edit",
          "price_cents" => 4_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      html =
        conn
        |> login(customer)
        |> get(~p"/listings/#{listing.id}/edit")
        |> html_response(200)

      parsed = Floki.parse_document!(html)

      assert Floki.find(
               parsed,
               ~s(form[action="/listings/#{listing.id}/invites"][method="post"])
             ) != []

      assert Floki.find(parsed, ~s(button[id="listing-invite-#{listing.id}"])) != []
    end
  end
end
