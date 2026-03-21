defmodule MechanicsWeb.ChatNotificationsTest do
  use MechanicsWeb.ConnCase

  import Ecto.Query

  alias Mechanics.Accounts
  alias Mechanics.Chats
  alias Mechanics.Chats.Message
  alias Mechanics.Listings
  alias Mechanics.Profiles
  alias Mechanics.Repo

  defp login(conn, user) do
    init_test_session(conn, %{current_user_id: user.id})
  end

  describe "header bell next to Welcome" do
    test "shows bell, unread badge, and dropdown with chat title plus latest message preview when user has unread" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "hdr-m-#{System.unique_integer([:positive])}@example.com",
          "name" => "Header Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, _} =
        Profiles.create_profile(%{
          "headline" => "Hdr Mech Co",
          "bio" => "Bio",
          "city" => "Tucson",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "hdr-c-#{System.unique_integer([:positive])}@example.com",
          "name" => "Header Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
      {:ok, _} = Chats.create_message(chat.id, mechanic, %{body: "Unread ping from mechanic."})

      html =
        build_conn()
        |> login(customer)
        |> get(~p"/")
        |> html_response(200)

      assert html =~ ~s(id="header-welcome")
      assert html =~ "Welcome,"
      assert html =~ "Header Customer"

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, ~s(details#header-chat-notifications)) != []

      badge = Floki.find(parsed, ~s(#header-notification-unread-badge))
      assert badge != []
      assert Floki.text(hd(badge)) =~ "1"

      list = Floki.find(parsed, ~s(ul#header-notification-list))
      assert list != []

      rows = Floki.find(parsed, ".header-notification-row")
      assert length(rows) >= 1

      assert Floki.find(parsed, ".header-notification-row time[datetime]") != []
      assert Floki.find(parsed, ".header-notification-row time[data-local-chat-time]") != []

      row_text = rows |> hd() |> Floki.text()
      assert row_text =~ "PM with Header Mech"
      assert row_text =~ "Name"
      assert row_text =~ "Header Mech"
      assert row_text =~ "Headline"
      assert row_text =~ "Hdr Mech Co"
      assert row_text =~ "Bio"
      assert row_text =~ "Location"
      assert row_text =~ "Tucson"
      assert row_text =~ "Unread ping from mechanic."
      refute row_text =~ "UTC"

      previews = Floki.find(parsed, ".header-notification-preview")
      assert previews != []
      assert Floki.text(hd(previews)) =~ "Unread ping"
    end

    test "after opening the chat, home page no longer shows unread badge on header bell" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "rd-m-#{System.unique_integer([:positive])}@example.com",
          "name" => "Read Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, _} =
        Profiles.create_profile(%{
          "headline" => "Read Co",
          "bio" => "Bio",
          "city" => "Tucson",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "rd-c-#{System.unique_integer([:positive])}@example.com",
          "name" => "Read Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
      {:ok, _} = Chats.create_message(chat.id, mechanic, %{body: "Please read me."})

      conn = build_conn() |> login(customer)

      html_before = html_response(get(conn, ~p"/"), 200)
      assert html_before =~ "header-notification-unread-badge"

      _ = get(conn, ~p"/chats/#{chat.id}")

      html_after =
        build_conn()
        |> login(customer)
        |> get(~p"/")
        |> html_response(200)

      refute html_after =~ "header-notification-unread-badge"
    end

    test "badge shows total unread messages and drops by the amount cleared when one thread is read" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "dec-m-#{System.unique_integer([:positive])}@example.com",
          "name" => "Dec Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, c1} =
        Accounts.create_user(%{
          "email" => "dec-1-#{System.unique_integer([:positive])}@example.com",
          "name" => "Dec One",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, c2} =
        Accounts.create_user(%{
          "email" => "dec-2-#{System.unique_integer([:positive])}@example.com",
          "name" => "Dec Two",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, ch1} = Chats.get_or_create_private_pm(c1, mechanic)
      {:ok, ch2} = Chats.get_or_create_private_pm(c2, mechanic)
      {:ok, _} = Chats.create_message(ch1.id, c1, %{body: "m1"})
      {:ok, _} = Chats.create_message(ch1.id, c1, %{body: "m2"})
      {:ok, _} = Chats.create_message(ch2.id, c2, %{body: "m3"})

      conn = build_conn() |> login(mechanic)

      html_three = html_response(get(conn, ~p"/"), 200)
      parsed_three = Floki.parse_document!(html_three)
      badge_three = Floki.find(parsed_three, ~s(#header-notification-unread-badge))
      assert Floki.text(hd(badge_three)) =~ "3"

      _ = get(conn, ~p"/chats/#{ch1.id}")

      html_one =
        build_conn()
        |> login(mechanic)
        |> get(~p"/")
        |> html_response(200)

      parsed_one = Floki.parse_document!(html_one)
      badge_one = Floki.find(parsed_one, ~s(#header-notification-unread-badge))
      assert Floki.text(hd(badge_one)) =~ "1"
    end
  end

  describe "mechanic profile card bell (customer)" do
    test "shows bell with unread count next to the mechanic card when that mechanic sent messages" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "card-m-#{System.unique_integer([:positive])}@example.com",
          "name" => "Card Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, _} =
        Profiles.create_profile(%{
          "headline" => "Card Mech Headline",
          "bio" => "Bio",
          "city" => "Flagstaff",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "card-c-#{System.unique_integer([:positive])}@example.com",
          "name" => "Card Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
      {:ok, _} = Chats.create_message(chat.id, mechanic, %{body: "One"})
      {:ok, _} = Chats.create_message(chat.id, mechanic, %{body: "Two"})

      html =
        build_conn()
        |> login(customer)
        |> get(~p"/")
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      bell = Floki.find(parsed, ~s([data-test="mechanic-card-notification-bell"]))
      assert bell != []

      assert Floki.attribute(hd(bell), "id") == ["mechanic-card-notification-bell-#{mechanic.id}"]

      count_el =
        Floki.find(parsed, ~s([data-test="mechanic-card-notification-bell-count"]))
      assert Floki.text(hd(count_el)) =~ "2"

      peer_rows = Floki.find(parsed, ".card-notification-peer-row")
      assert length(peer_rows) == 1
      assert Floki.text(hd(peer_rows)) =~ "Card Mech"
      assert Floki.text(hd(peer_rows)) =~ "2 unread"
    end
  end

  describe "listing owner card bell (multiple mechanics)" do
    test "shows total unread messages and lists each mechanic in the bell panel" do
      {:ok, owner} =
        Accounts.create_user(%{
          "email" => "lo-own-#{System.unique_integer([:positive])}@example.com",
          "name" => "Job Owner",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Brake work",
          "description" => "Pads",
          "price_cents" => 18_000,
          "currency" => "USD",
          "customer_id" => owner.id,
          "is_public" => true
        })

      {:ok, mech_a} =
        Accounts.create_user(%{
          "email" => "lo-a-#{System.unique_integer([:positive])}@example.com",
          "name" => "Owner Mech A",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, mech_b} =
        Accounts.create_user(%{
          "email" => "lo-b-#{System.unique_integer([:positive])}@example.com",
          "name" => "Owner Mech B",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, ca} = Chats.get_or_create_listing_chat(mech_a, listing.id)
      {:ok, cb} = Chats.get_or_create_listing_chat(mech_b, listing.id)
      {:ok, _} = Chats.create_message(ca.id, mech_a, %{body: "A here"})
      {:ok, _} = Chats.create_message(ca.id, mech_a, %{body: "A again"})
      {:ok, _} = Chats.create_message(cb.id, mech_b, %{body: "B here"})

      html =
        build_conn()
        |> login(owner)
        |> get(~p"/")
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      bell = Floki.find(parsed, "#listing-owner-notification-bell-#{listing.id}")
      assert bell != []

      count_el = Floki.find(parsed, ~s([data-test="listing-owner-notification-bell-count"]))
      assert Floki.text(hd(count_el)) =~ "3"

      peer_rows = Floki.find(parsed, "#listing-owner-notification-bell-#{listing.id}-peer-list .card-notification-peer-row")
      assert length(peer_rows) == 2
      peer_text = peer_rows |> Enum.map(&Floki.text/1) |> Enum.join(" ")
      assert peer_text =~ "Owner Mech A"
      assert peer_text =~ "Owner Mech B"
      assert peer_text =~ "2 unread"
      assert peer_text =~ "1 unread"
    end
  end

  describe "mechanic inbox (multiple customers in private chats)" do
    test "header shows two unread conversations with titles and previews; mechanic_pm_next opens oldest chat first" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "mc-m-#{System.unique_integer([:positive])}@example.com",
          "name" => "Shared Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, _} =
        Profiles.create_profile(%{
          "headline" => "Shared Mech Shop",
          "bio" => "Mobile",
          "city" => "Tempe",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      {:ok, customer_a} =
        Accounts.create_user(%{
          "email" => "mc-a-#{System.unique_integer([:positive])}@example.com",
          "name" => "Aaron Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, customer_b} =
        Accounts.create_user(%{
          "email" => "mc-b-#{System.unique_integer([:positive])}@example.com",
          "name" => "Zora Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, chat_a} = Chats.get_or_create_private_pm(customer_a, mechanic)
      {:ok, chat_b} = Chats.get_or_create_private_pm(customer_b, mechanic)
      {:ok, _} = Chats.create_message(chat_a.id, customer_a, %{body: "Aaron needs a quote."})
      {:ok, _} = Chats.create_message(chat_b.id, customer_b, %{body: "Zora checking availability."})

      # Same-second message timestamps would tie FIFO on UUID order; force Aaron's thread first.
      older =
        DateTime.utc_now()
        |> DateTime.add(-2 * 3600, :second)
        |> DateTime.truncate(:second)

      from(m in Message, where: m.chat_id == ^chat_a.id)
      |> Repo.update_all(set: [inserted_at: older])

      html =
        build_conn()
        |> login(mechanic)
        |> get(~p"/")
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, ~s(details#header-chat-notifications)) != []

      badge = Floki.find(parsed, ~s(#header-notification-unread-badge))
      assert badge != []
      assert Floki.text(hd(badge)) =~ "2"

      rows = Floki.find(parsed, ".header-notification-row")
      assert length(rows) == 2

      combined = rows |> Enum.map(&Floki.text/1) |> Enum.join(" ")
      assert combined =~ "PM with Aaron Customer"
      assert combined =~ "PM with Zora Customer"
      assert combined =~ "Aaron needs a quote."
      assert combined =~ "Zora checking availability."

      conn = build_conn() |> login(mechanic)
      conn = get(conn, ~p"/chats/open/mechanic_pm_next")
      assert redirected_to(conn) == ~p"/chats/#{chat_a.id}"
    end
  end

  describe "listing card bell (mechanic)" do
    test "shows bell with unread count when the customer replied" do
      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "lm-c-#{System.unique_integer([:positive])}@example.com",
          "name" => "List Cust",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Tire rotation",
          "description" => "Rotate",
          "price_cents" => 5_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "lm-m-#{System.unique_integer([:positive])}@example.com",
          "name" => "List Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, chat} = Chats.get_or_create_listing_chat(mechanic, listing.id)
      {:ok, _} = Chats.create_message(chat.id, customer, %{body: "Thanks for reaching out!"})

      html =
        build_conn()
        |> login(mechanic)
        |> get(~p"/")
        |> html_response(200)

      parsed = Floki.parse_document!(html)
      bell = Floki.find(parsed, ~s([data-test="listing-mechanic-notification-bell"]))
      assert bell != []

      count_el =
        Floki.find(parsed, ~s([data-test="listing-mechanic-notification-bell-count"]))
      assert Floki.text(hd(count_el)) =~ "1"

      peer_rows =
        Floki.find(
          parsed,
          "#listing-mechanic-notification-bell-#{listing.id}-peer-list .card-notification-peer-row"
        )

      assert length(peer_rows) == 1
      assert Floki.text(hd(peer_rows)) =~ "List Cust"
    end
  end
end
