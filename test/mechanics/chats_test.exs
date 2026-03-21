defmodule Mechanics.ChatsTest do
  use Mechanics.DataCase, async: true

  import Ecto.Changeset

  alias Mechanics.Accounts
  alias Mechanics.Accounts.User
  alias Mechanics.Chats
  alias Mechanics.Chats.Chat
  alias Mechanics.Chats.Message
  alias Mechanics.Listings
  alias Mechanics.Profiles
  alias Mechanics.Repo

  defp uuid_binary_id?(id) do
    match?({:ok, _}, Ecto.UUID.cast(id))
  end

  defp mechanic_and_customer do
    suffix = System.unique_integer([:positive])

    {:ok, mechanic} =
      Accounts.create_user(%{
        "email" => "mechanic-#{suffix}@example.com",
        "name" => "Pat Mechanic",
        "roles" => ["mechanic"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    {:ok, customer} =
      Accounts.create_user(%{
        "email" => "customer-#{suffix}@example.com",
        "name" => "Chris Customer",
        "roles" => ["customer"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    %{mechanic: mechanic, customer: customer}
  end

  describe "private message chats (mechanic + customer, no listing)" do
    test "participants are the mechanic-role and customer-role users; listing_id is nil; ids are UUIDs" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()

      assert {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)

      assert chat.listing_id == nil
      assert chat.mechanic_user_id == mechanic.id
      assert chat.customer_user_id == customer.id

      assert uuid_binary_id?(chat.id)
      assert uuid_binary_id?(chat.mechanic_user_id)
      assert uuid_binary_id?(chat.customer_user_id)
    end

    test "recipient sees title \"PM with {other user}\"; customer gets mechanic profile detail rows" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)

      assert Chats.chat_header_for_viewer(chat, mechanic) == %{
               title: "PM with Chris Customer",
               details: []
             }

      assert Chats.chat_header_for_viewer(chat, customer) == %{
               title: "PM with Pat Mechanic",
               details: []
             }

      {:ok, _} =
        Profiles.create_profile(%{
          "headline" => "Pat's mobile shop",
          "bio" => "Certified.",
          "city" => "Tucson",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      assert Chats.chat_header_for_viewer(chat, customer) == %{
               title: "PM with Pat Mechanic",
               details: [
                 %{label: "Name", value: "Pat Mechanic"},
                 %{label: "Headline", value: "Pat's mobile shop"},
                 %{label: "Bio", value: "Certified."},
                 %{label: "Location", value: "Tucson, AZ"}
               ]
             }

      assert Chats.card_title_for_viewer(chat, customer) ==
               "PM with Pat Mechanic · Pat's mobile shop"
    end

    test "customer can send a message without a listing id on the chat" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
      assert chat.listing_id == nil

      assert {:ok, %Message{} = msg} =
               Chats.create_message(chat.id, customer, %{body: "Are you free Tuesday?"})

      assert msg.body == "Are you free Tuesday?"
      assert uuid_binary_id?(msg.id)
      assert msg.sender_user_id == customer.id
    end
  end

  describe "role loss revokes access" do
    test "mechanic who loses the mechanic role cannot read the chat" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)

      assert {:ok, _} = Chats.fetch_chat(chat.id, mechanic)

      mechanic
      |> change(%{roles: ["customer"]})
      |> Repo.update!()

      refreshed_mechanic = Repo.get!(User, mechanic.id)
      assert {:error, :forbidden} = Chats.fetch_chat(chat.id, refreshed_mechanic)
    end

    test "customer who loses the customer role cannot read the chat" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)

      assert {:ok, _} = Chats.fetch_chat(chat.id, customer)

      customer
      |> change(%{roles: ["mechanic"]})
      |> Repo.update!()

      refreshed = Repo.get!(User, customer.id)
      assert {:error, :forbidden} = Chats.fetch_chat(chat.id, refreshed)
    end
  end

  describe "chat CRUD" do
    test "create, read, update, and delete chats the user may access" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()

      assert {:ok, chat} =
               Chats.create_chat(%{
                 mechanic_user_id: mechanic.id,
                 customer_user_id: customer.id,
                 listing_id: nil,
                 topic: "intro"
               })

      assert {:ok, fetched} = Chats.fetch_chat(chat.id, customer)
      assert fetched.topic == "intro"

      assert {:ok, updated} = Chats.update_chat(chat, %{topic: "follow-up"}, customer)
      assert updated.topic == "follow-up"

      assert {:ok, _} = Chats.delete_chat(updated, mechanic)
      assert Repo.get(Chat, chat.id) == nil
    end
  end

  describe "message CRUD" do
    test "create, list, update, and delete messages in a chat" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)

      assert {:ok, msg} = Chats.create_message(chat.id, customer, %{body: "First line"})
      assert {:ok, listed} = Chats.list_messages(chat.id, mechanic)
      assert [%Message{id: id}] = listed
      assert id == msg.id

      assert {:ok, edited} =
               Chats.update_message(msg, %{body: "First line (edited)"}, customer)

      assert edited.body == "First line (edited)"

      assert {:ok, _} = Chats.delete_message(edited, customer)
      assert {:ok, []} = Chats.list_messages(chat.id, mechanic)
    end

    test "non-sender cannot update or delete another user's message" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()
      {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
      {:ok, msg} = Chats.create_message(chat.id, customer, %{body: "Customer note"})

      assert {:error, :forbidden} = Chats.update_message(msg, %{body: "Hacked"}, mechanic)
      assert {:error, :forbidden} = Chats.delete_message(msg, mechanic)
    end
  end

  describe "listing chats" do
    test "chat_header_for_viewer splits job, pay, people, and description by viewer; ids are UUIDs" do
      %{mechanic: mechanic, customer: customer} = mechanic_and_customer()

      {:ok, listing} =
        Listings.create_listing(%{
          "title" => "Winter tire swap",
          "description" => "Need tires swapped on a sedan.",
          "price_cents" => 8_000,
          "currency" => "USD",
          "customer_id" => customer.id,
          "is_public" => true
        })

      assert uuid_binary_id?(listing.id)

      {:ok, profile} =
        Profiles.create_profile(%{
          "headline" => "Pat's mobile shop",
          "bio" => "Certified.",
          "city" => "Tucson",
          "state" => "AZ",
          "is_public" => true,
          "user_id" => mechanic.id
        })

      assert uuid_binary_id?(profile.id)

      assert {:ok, chat} = Chats.get_or_create_listing_chat(mechanic, listing.id)
      assert chat.listing_id == listing.id

      assert Chats.chat_header_for_viewer(chat, mechanic) == %{
               title: "Winter tire swap",
               details: [
                 %{label: "Pay", value: "$80.00 USD"},
                 %{label: "Posted by", value: "Chris Customer"},
                 %{label: "Description", value: "Need tires swapped on a sedan."}
               ]
             }

      assert Chats.chat_header_for_viewer(chat, customer) == %{
               title: "Pat Mechanic",
               details: [
                 %{label: "Name", value: "Pat Mechanic"},
                 %{label: "Headline", value: "Pat's mobile shop"},
                 %{label: "Bio", value: "Certified."},
                 %{label: "Location", value: "Tucson, AZ"},
                 %{label: "Job", value: "Winter tire swap"},
                 %{label: "Description", value: "Need tires swapped on a sedan."}
               ]
             }

      assert Chats.card_title_for_viewer(chat, customer) ==
               "Pat Mechanic · Pat's mobile shop — Winter tire swap"
    end
  end
end
