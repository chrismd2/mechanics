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
    test "owner can create a listing invite and see the share link on account", %{conn: conn} do
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
        |> post(~p"/listings/#{listing.id}/invites", %{
          "return_to" => "/account?tab=listings"
        })

      redirect = redirected_to(conn)
      assert redirect =~ ~r{^/account\?}
      assert redirect =~ "tab=listings"
      assert redirect =~ "invite_listing_id=#{listing.id}"
      assert redirect =~ "invite_token="
      refute Phoenix.Flash.get(conn.assigns.flash, :info)

      assert [%Invite{subject_type: "listing", listing_id: listing_id, chat_id: nil, token: token}] =
               invites_for_listing(listing.id)

      assert listing_id == listing.id

      html =
        conn
        |> get(redirect)
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, ~s(#account-listing-invite-url-#{listing.id})) != []
      assert Floki.find(parsed, ~s(#account-listing-invite-qr-#{listing.id} svg)) != []
      assert Floki.find(parsed, ~s(#account-listing-invite-qr-#{listing.id}-modal[hidden])) != []
      assert Floki.find(parsed, ~s(#account-listing-invite-qr-#{listing.id}-large svg)) != []

      [input] = Floki.find(parsed, ~s(#account-listing-invite-url-#{listing.id}))
      [value] = Floki.attribute(input, "value")
      assert value == "https://www.example.com/invites/#{token}"
    end

    test "owner create from edit stays on edit and shows the share link", %{conn: conn} do
      customer = create_customer()

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Edit invite stay",
          "description" => "Stay on edit",
          "price_cents" => 3_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      return_to = "/listings/#{listing.id}/edit"

      conn =
        conn
        |> login(customer)
        |> post(~p"/listings/#{listing.id}/invites", %{"return_to" => return_to})

      redirect = redirected_to(conn)
      assert redirect =~ ~r{^/listings/#{listing.id}/edit\?}
      assert redirect =~ "invite_token="

      assert [%Invite{token: token}] = invites_for_listing(listing.id)

      html =
        conn
        |> get(redirect)
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, ~s(#listing-invite-url-#{listing.id})) != []
      assert Floki.find(parsed, ~s(#listing-invite-qr-#{listing.id} svg)) != []
      assert Floki.find(parsed, ~s(#listing-invite-qr-#{listing.id}-modal[hidden])) != []
      assert Floki.find(parsed, ~s(#listing-invite-qr-#{listing.id}-large svg)) != []

      [input] = Floki.find(parsed, ~s(#listing-invite-url-#{listing.id}))
      [value] = Floki.attribute(input, "value")
      assert value == "https://www.example.com/invites/#{token}"
    end

    test "share link uses the public request host, not endpoint localhost", %{conn: conn} do
      customer = create_customer()

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Public host invite",
          "description" => "Host header",
          "price_cents" => 2_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      conn =
        conn
        |> Map.put(:host, "mechanics.electricquestlog.xyz")
        |> login(customer)
        |> post(~p"/listings/#{listing.id}/invites", %{
          "return_to" => "/account?tab=listings"
        })

      redirect = redirected_to(conn)
      assert [%Invite{token: token}] = invites_for_listing(listing.id)

      html =
        conn
        |> Map.put(:host, "mechanics.electricquestlog.xyz")
        |> get(redirect)
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      [input] = Floki.find(parsed, ~s(#account-listing-invite-url-#{listing.id}))
      [value] = Floki.attribute(input, "value")
      assert value == "https://mechanics.electricquestlog.xyz/invites/#{token}"
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

      assert redirected_to(conn) == ~p"/account?tab=listings"
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
      assert Floki.find(parsed, ~s(#listing-invite-url-#{listing.id})) == []
    end
  end

  describe "POST /chats/:chat_id/invites" do
    test "participant sees share link and QR on the chat page", %{conn: conn} do
      customer = create_customer()

      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "invite-mech-#{System.unique_integer([:positive])}@example.com",
          "name" => "Invite Mechanic",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      assert {:ok, chat} = Mechanics.Chats.get_or_create_private_pm(customer, mechanic)

      conn =
        conn
        |> login(customer)
        |> post(~p"/chats/#{chat.id}/invites")

      redirect = redirected_to(conn)
      assert redirect =~ ~r{^/chats/#{chat.id}\?}
      assert redirect =~ "invite_token="
      refute Phoenix.Flash.get(conn.assigns.flash, :info)

      assert [%Invite{subject_type: "conversation", token: token}] =
               Repo.all(from i in Invite, where: i.chat_id == ^chat.id)

      html =
        conn
        |> get(redirect)
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "#chat-invite-url") != []
      assert Floki.find(parsed, "#chat-invite-qr svg") != []
      assert Floki.find(parsed, "#chat-invite-qr-modal[hidden]") != []
      assert Floki.find(parsed, "#chat-invite-qr-large svg") != []

      [input] = Floki.find(parsed, "#chat-invite-url")
      [value] = Floki.attribute(input, "value")
      assert value == "https://www.example.com/invites/#{token}"
    end
  end
end
