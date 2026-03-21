defmodule MechanicsWeb.ChatControllerTest do
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

  defp csrf_token_from_html(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find("form input[name='_csrf_token']")
    |> Floki.attribute("value")
    |> List.first()
  end

  defp customer_and_mechanic do
    suffix = System.unique_integer([:positive])

    {:ok, mechanic} =
      Accounts.create_user(%{
        "email" => "m-#{suffix}@example.com",
        "name" => "Taylor Mechanic",
        "roles" => ["mechanic"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    {:ok, customer} =
      Accounts.create_user(%{
        "email" => "c-#{suffix}@example.com",
        "name" => "Riley Customer",
        "roles" => ["customer"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    %{mechanic: mechanic, customer: customer}
  end

  describe "GET /chats/open/mechanic/:mechanic_user_id (customer messages mechanic)" do
    test "customer is routed to a new private chat, then idempotently to the same chat" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "mech-open-#{System.unique_integer([:positive])}@example.com",
          "name" => "Open Mechanic",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, _} =
        Profiles.create_profile(%{
          "headline" => "Brake specialist",
          "bio" => "Mobile service.",
          "city" => "Phoenix",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "cust-open-#{System.unique_integer([:positive])}@example.com",
          "name" => "Open Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn = build_conn() |> login(customer)

      conn = get(conn, ~p"/chats/open/mechanic/#{mechanic.id}")
      chat_path = redirected_to(conn)
      assert chat_path =~ "/chats/"

      conn2 = get(build_conn() |> login(customer), ~p"/chats/open/mechanic/#{mechanic.id}")
      assert redirected_to(conn2) == chat_path
    end

    test "logged-in user without the customer role receives an unauthorized message" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "target-#{System.unique_integer([:positive])}@example.com",
          "name" => "Target Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, other_mechanic} =
        Accounts.create_user(%{
          "email" => "caller-#{System.unique_integer([:positive])}@example.com",
          "name" => "Caller",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn =
        build_conn()
        |> login(other_mechanic)
        |> get(~p"/chats/open/mechanic/#{mechanic.id}")

      assert conn.status == 403
      assert conn.resp_body =~ "not authorized"
    end
  end

  describe "GET /chats/open/listing/:listing_id (mechanic contacts customer about listing)" do
    test "mechanic is routed to a new listing chat; title on show relates to listing" do
      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "list-owner-#{System.unique_integer([:positive])}@example.com",
          "name" => "List Owner",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "AC recharge",
          "description" => "R134a",
          "price_cents" => 15_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "list-mech-#{System.unique_integer([:positive])}@example.com",
          "name" => "List Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn = build_conn() |> login(mechanic)
      conn = get(conn, ~p"/chats/open/listing/#{listing.id}")
      chat_path = redirected_to(conn)
      [_, chat_id] = Regex.run(~r{/chats/([^/?]+)}, chat_path)

      conn_show =
        build_conn()
        |> login(mechanic)
        |> get(~p"/chats/#{chat_id}")

      html = html_response(conn_show, 200)
      assert html =~ "Job: AC recharge"
    end

    test "user without the mechanic role cannot open listing chats" do
      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "c2-#{System.unique_integer([:positive])}@example.com",
          "name" => "Cust Two",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, other_customer} =
        Accounts.create_user(%{
          "email" => "c3-#{System.unique_integer([:positive])}@example.com",
          "name" => "Cust Three",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Oil change",
          "description" => "Synthetic",
          "price_cents" => 9_000,
          "currency" => "USD",
          "customer_id" => other_customer.id,
          "is_public" => true
        })

      conn =
        build_conn()
        |> login(customer)
        |> get(~p"/chats/open/listing/#{listing.id}")

      assert conn.status == 403
      assert conn.resp_body =~ "not authorized"
    end
  end

  describe "home page entrypoints" do
    test "customer clicking a public mechanic profile opens PM chat (link target)" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "home-m-#{System.unique_integer([:positive])}@example.com",
          "name" => "Home Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, _} =
        Profiles.create_profile(%{
          "headline" => "Visible mech",
          "bio" => "Bio",
          "city" => "Mesa",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "home-c-#{System.unique_integer([:positive])}@example.com",
          "name" => "Home Customer",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn = build_conn() |> login(customer)
      html = html_response(get(conn, ~p"/"), 200)
      assert html =~ ~s(href="/chats/open/mechanic/#{mechanic.id}")
    end

    test "mechanic clicking another user's public listing opens listing chat (link target)" do
      {:ok, customer} =
        Accounts.create_user(%{
          "email" => "job-poster-#{System.unique_integer([:positive])}@example.com",
          "name" => "Poster",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Battery replacement",
          "description" => "Dead battery",
          "price_cents" => 12_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      {:ok, mechanic} =
        Accounts.create_user(%{
          "email" => "job-mech-#{System.unique_integer([:positive])}@example.com",
          "name" => "Job Mech",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      conn = build_conn() |> login(mechanic)
      html = html_response(get(conn, ~p"/"), 200)
      assert html =~ ~s(href="/chats/open/listing/#{listing.id}")
    end
  end

  describe "GET /chats/:id (conversation UI)" do
    test "shows message list with timestamps, compose textarea, submit button, and sender names when messages exist" do
      %{mechanic: mechanic, customer: customer} = customer_and_mechanic()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
      {:ok, _} = Chats.create_message(chat.id, customer, %{body: "Need brakes soon."})
      {:ok, _} = Chats.create_message(chat.id, mechanic, %{body: "I can Tuesday."})

      conn =
        build_conn()
        |> login(customer)
        |> get(~p"/chats/#{chat.id}")

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Floki.find(parsed, "div#chat_transcript") != []
      assert Floki.find(parsed, "ul#chat_message_list") != []
      assert Floki.find(parsed, "time[datetime]") != []
      assert Floki.find(parsed, "textarea#message_body") != []

      [msg_body] = Floki.find(parsed, "textarea#message_body")
      assert Floki.attribute(msg_body, "name") == ["message[body]"]

      assert Floki.find(parsed, "button#message_submit[type='submit']") != []

      log_text =
        parsed
        |> Floki.find("div#chat_transcript")
        |> hd()
        |> Floki.text()

      assert log_text =~ "Riley Customer"
      assert log_text =~ "Need brakes soon."
      assert log_text =~ "Taylor Mechanic"
      assert log_text =~ "I can Tuesday."
      refute log_text =~ "UTC"

      times = Floki.find(parsed, ".chat-message-row time")
      assert length(times) == 2

      for el <- times do
        assert Floki.attribute(el, "datetime") != []
        assert Floki.attribute(el, "data-local-chat-time") != []
        assert el |> Floki.text() |> String.trim() == "…"
      end
    end

    test "marks old messages for browser local formatting via datetime + data-local-chat-time" do
      %{mechanic: mechanic, customer: customer} = customer_and_mechanic()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
      {:ok, old_msg} = Chats.create_message(chat.id, customer, %{body: "Old thread."})

      old =
        DateTime.utc_now()
        |> DateTime.add(-50 * 3600, :second)
        |> DateTime.truncate(:second)

      from(m in Message, where: m.id == ^old_msg.id)
      |> Repo.update_all(set: [inserted_at: old])

      conn =
        build_conn()
        |> login(customer)
        |> get(~p"/chats/#{chat.id}")

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      [time_el] = Floki.find(parsed, ".chat-message-row time")
      assert Floki.attribute(time_el, "data-local-chat-time") != []

      [dt_attr] = Floki.attribute(time_el, "datetime")
      {:ok, dt, _} = DateTime.from_iso8601(dt_attr)
      assert DateTime.diff(DateTime.utc_now() |> DateTime.truncate(:second), dt, :second) >
               24 * 3600

      assert time_el |> Floki.text() |> String.trim() == "…"
    end

    test "shows empty-state placeholder when there are no messages" do
      %{mechanic: mechanic, customer: customer} = customer_and_mechanic()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)

      conn =
        build_conn()
        |> login(mechanic)
        |> get(~p"/chats/#{chat.id}")

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)
      empty = Floki.find(parsed, "#chat_empty_state") |> Floki.text()
      assert empty =~ "No messages yet"
    end
  end

  describe "POST /chats/:id/messages" do
    test "submitting the form appends the message with the sender's name in the message list" do
      %{mechanic: mechanic, customer: customer} = customer_and_mechanic()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)

      conn = build_conn() |> login(customer)
      conn = get(conn, ~p"/chats/#{chat.id}")
      html = html_response(conn, 200)
      token = csrf_token_from_html(html)

      conn =
        post(conn, ~p"/chats/#{chat.id}/messages", %{
          "_csrf_token" => token,
          "message" => %{"body" => "Posted from the form."}
        })

      assert redirected_to(conn) == ~p"/chats/#{chat.id}"

      html_after =
        build_conn()
        |> login(customer)
        |> get(~p"/chats/#{chat.id}")
        |> html_response(200)

      parsed = Floki.parse_document!(html_after)
      log_text = parsed |> Floki.find("div#chat_transcript") |> hd() |> Floki.text()
      assert log_text =~ "Riley Customer"
      assert log_text =~ "Posted from the form."
    end
  end
end
