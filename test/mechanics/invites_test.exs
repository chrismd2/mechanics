defmodule Mechanics.InvitesTest do
  use Mechanics.DataCase, async: true

  alias Mechanics.Accounts
  alias Mechanics.Chats
  alias Mechanics.Invites
  alias Mechanics.Listings

  defp mechanic_and_customer do
    suffix = System.unique_integer([:positive])

    {:ok, mechanic} =
      Accounts.create_user(%{
        "email" => "mechanic-invite-#{suffix}@example.com",
        "name" => "Pat Mechanic",
        "roles" => ["mechanic"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    {:ok, customer} =
      Accounts.create_user(%{
        "email" => "customer-invite-#{suffix}@example.com",
        "name" => "Chris Customer",
        "roles" => ["customer"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    %{mechanic: mechanic, customer: customer}
  end

  test "conversation invite can be created by a participant and accepted by the other participant" do
    %{mechanic: mechanic, customer: customer} = mechanic_and_customer()
    assert {:ok, chat} = Chats.get_or_create_private_pm(customer, mechanic)
    assert {:ok, invite} = Invites.create_conversation_invite(customer, chat.id)
    assert invite.subject_type == "conversation"
    assert invite.chat_id == chat.id

    assert {:ok, opened} = Invites.accept(invite, mechanic)
    assert opened.id == chat.id
  end

  test "profile invite opens a private PM for a customer accepter" do
    %{mechanic: mechanic, customer: customer} = mechanic_and_customer()
    assert {:ok, invite} = Invites.create_profile_invite(customer, mechanic.id)
    assert invite.subject_type == "profile"

    assert {:ok, chat} = Invites.accept(invite, customer)
    assert chat.listing_id == nil
    assert chat.mechanic_user_id == mechanic.id
    assert chat.customer_user_id == customer.id
  end

  test "listing invite opens listing chat for a mechanic accepter" do
    %{mechanic: mechanic, customer: customer} = mechanic_and_customer()

    assert {:ok, listing} =
             Listings.create_listing(%{
               "title" => "Brake job",
               "description" => "Front pads",
               "price_cents" => 12_000,
               "currency" => "USD",
               "is_public" => true,
               "customer_id" => customer.id
             })

    assert {:ok, invite} = Invites.create_listing_invite(customer, listing.id)
    assert {:ok, chat} = Invites.accept(invite, mechanic)
    assert chat.listing_id == listing.id
    assert chat.mechanic_user_id == mechanic.id
  end
end
