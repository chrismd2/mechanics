defmodule Mechanics.Chats.Notifications do
  @moduledoc """
  Read/unread state and **message-count** summaries for chat participants.

  Presentation layers (`MechanicsWeb.NotificationBellComponents`, header layout) stay thin;
  this module owns counts, peer resolution, and FIFO “next chat” helpers (single responsibility).
  Card-specific shapes (`*_card_peers/2`) isolate home-page context from header `header_feed/1`.
  """

  import Ecto.Query, warn: false

  alias Mechanics.Accounts.User
  alias Mechanics.Chats
  alias Mechanics.Chats.Chat
  alias Mechanics.Chats.Message
  alias Mechanics.Chats.ReadState
  alias Mechanics.Listings.Listing
  alias Mechanics.Repo

  def mark_chat_read(chat_id, %User{} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(ReadState, user_id: user.id, chat_id: chat_id) do
      nil ->
        %ReadState{}
        |> ReadState.upsert_changeset(%{
          "user_id" => user.id,
          "chat_id" => chat_id,
          "last_read_at" => now
        })
        |> Repo.insert()

      %ReadState{} = row ->
        row
        |> Ecto.Changeset.change(%{last_read_at: now})
        |> Repo.update()
    end
  end

  def last_read_at(chat_id, user_id) do
    case Repo.get_by(ReadState, user_id: user_id, chat_id: chat_id) do
      %ReadState{last_read_at: at} -> at
      nil -> nil
    end
  end

  def unread_incoming_count(chat_id, user_id) do
    last_at = last_read_at(chat_id, user_id)

    q =
      from m in Message,
        where: m.chat_id == ^chat_id,
        where: m.sender_user_id != ^user_id

    q =
      if last_at do
        from m in q, where: m.inserted_at > ^last_at
      else
        q
      end

    Repo.aggregate(q, :count, :id)
  end

  @doc """
  For header dropdown or account conversation cards: chats the user can access, each with title,
  latest message preview, and unread incoming count.

  Pass `compact: true` for account cards: **one-line** `title` via `Chats.card_title_for_viewer/2` and
  empty `details`. Default `compact: false` keeps `chat_header_for_viewer/2` title + detail rows
  (header bell).
  """
  def header_feed(%User{} = user, opts \\ []) do
    compact = Keyword.get(opts, :compact, false)
    chats = Chats.list_chats_for_user(user)

    items =
      chats
      |> Enum.map(fn chat ->
        meta = latest_message_meta(chat.id)
        unread = unread_incoming_count(chat.id, user.id)

        {title, details} =
          if compact do
            {Chats.card_title_for_viewer(chat, user), []}
          else
            header = Chats.chat_header_for_viewer(chat, user)
            {header.title, header.details}
          end

        %{
          chat_id: chat.id,
          title: title,
          details: details,
          preview: (meta && meta.body) || "",
          last_message_at: meta && meta.at,
          unread_count: unread
        }
      end)
      |> Enum.sort_by(fn i ->
        {if(i.unread_count > 0, do: 0, else: 1), i.title}
      end)

    conv_unread = Enum.count(items, &(&1.unread_count > 0))
    total_msgs = Enum.sum(Enum.map(items, & &1.unread_count))

    %{
      items: items,
      conversations_with_unread: conv_unread,
      total_unread_messages: total_msgs
    }
  end

  defp latest_message_meta(chat_id) do
    from(m in Message,
      where: m.chat_id == ^chat_id,
      order_by: [desc: m.inserted_at, desc: m.id],
      limit: 1,
      select: %{body: m.body, at: m.inserted_at}
    )
    |> Repo.one()
  end

  defp pm_chat_id(customer_id, mechanic_id) do
    from(c in Chat,
      where:
        is_nil(c.listing_id) and c.customer_user_id == ^customer_id and
          c.mechanic_user_id == ^mechanic_id,
      select: c.id,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  For a listing owner: total unread **messages** across mechanics' threads, and a peer list
  (one row per mechanic with unread) for the card bell dropdown.
  """
  def listing_owner_card_peers(%User{} = owner, listing_id) when is_binary(listing_id) do
    q =
      from c in Chat,
        where: c.listing_id == ^listing_id and c.customer_user_id == ^owner.id,
        order_by: [asc: c.inserted_at, asc: c.id]

    chats = Repo.all(q)

    peers =
      Enum.map(chats, fn c ->
        uc = unread_incoming_count(c.id, owner.id)
        mu = Repo.get(User, c.mechanic_user_id)
        meta = latest_message_meta(c.id)

        %{
          chat_id: c.id,
          user_id: c.mechanic_user_id,
          display_name: (mu && mu.name) || "Mechanic",
          unread_count: uc,
          last_message_at: meta && meta.at
        }
      end)
      |> Enum.filter(&(&1.unread_count > 0))

    total = Enum.sum(Enum.map(peers, & &1.unread_count))
    %{total_unread: total, peers: peers}
  end

  @doc """
  Customer viewing a mechanic profile card: unread message count and peer row (the mechanic).
  """
  def customer_mechanic_pm_card_peers(%User{} = customer, mechanic_user_id)
      when is_binary(mechanic_user_id) do
    case pm_chat_id(customer.id, mechanic_user_id) do
      nil ->
        %{total_unread: 0, peers: []}

      chat_id ->
        n = unread_incoming_count(chat_id, customer.id)
        mu = Repo.get(User, mechanic_user_id)
        name = (mu && mu.name) || "Mechanic"
        meta = latest_message_meta(chat_id)

        peers =
          if n > 0 do
            [
              %{
                chat_id: chat_id,
                user_id: mechanic_user_id,
                display_name: name,
                unread_count: n,
                last_message_at: meta && meta.at
              }
            ]
          else
            []
          end

        %{total_unread: n, peers: peers}
    end
  end

  @doc """
  Mechanic viewing another user's listing card: unread from the listing customer.
  """
  def listing_mechanic_card_peers(%User{} = mechanic, listing_id)
      when is_binary(listing_id) do
    case listing_chat_for_mechanic(mechanic.id, listing_id) do
      nil ->
        %{total_unread: 0, peers: []}

      chat_id ->
        n = unread_incoming_count(chat_id, mechanic.id)

        peers =
          if n > 0 do
            listing = Repo.get(Listing, listing_id)
            cust = listing && Repo.get(User, listing.customer_id)
            name = (cust && cust.name) || "Customer"
            meta = latest_message_meta(chat_id)

            [
              %{
                chat_id: chat_id,
                user_id: cust && cust.id,
                display_name: name,
                unread_count: n,
                last_message_at: meta && meta.at
              }
            ]
          else
            []
          end

        %{total_unread: n, peers: peers}
    end
  end

  defp listing_chat_for_mechanic(mechanic_id, listing_id) do
    from(c in Chat,
      where: c.listing_id == ^listing_id and c.mechanic_user_id == ^mechanic_id,
      select: c.id,
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  First listing chat for the owner that still has unread incoming messages.

  Order is FIFO by **first message** time in the thread, then **chat** `inserted_at` (thread opened),
  then `chat.id`. That avoids depending on random UUID order when timestamps fall in the same second.
  """
  def first_unread_listing_chat_id_for_owner(listing_id, %User{} = owner) do
    first_at_sq = first_message_time_per_chat_subquery()

    q =
      from c in Chat,
        left_join: fa in subquery(first_at_sq),
        on: fa.chat_id == c.id,
        where: c.listing_id == ^listing_id and c.customer_user_id == ^owner.id,
        order_by: [
          asc: fragment("COALESCE(?, ?)", fa.first_at, c.inserted_at),
          asc: c.inserted_at,
          asc: c.id
        ]

    chats = Repo.all(q)

    case Enum.find(chats, fn c -> unread_incoming_count(c.id, owner.id) > 0 end) do
      %Chat{id: id} -> {:ok, id}
      nil -> {:error, :no_unread}
    end
  end

  @doc """
  First private-message (non-listing) chat for the mechanic that has unread incoming
  customer messages.

  Order is FIFO by **first message** time in the thread, then **chat** `inserted_at`, then `chat.id`.
  """
  def first_unread_private_pm_chat_id_for_mechanic(%User{} = mechanic) do
    if "mechanic" not in mechanic.roles do
      {:error, :forbidden}
    else
      first_at_sq = first_message_time_per_chat_subquery()

      q =
        from c in Chat,
          left_join: fa in subquery(first_at_sq),
          on: fa.chat_id == c.id,
          where: is_nil(c.listing_id) and c.mechanic_user_id == ^mechanic.id,
          order_by: [
            asc: fragment("COALESCE(?, ?)", fa.first_at, c.inserted_at),
            asc: c.inserted_at,
            asc: c.id
          ]

      chats = Repo.all(q)

      case Enum.find(chats, fn c -> unread_incoming_count(c.id, mechanic.id) > 0 end) do
        %Chat{id: id} -> {:ok, id}
        nil -> {:error, :no_unread}
      end
    end
  end

  defp first_message_time_per_chat_subquery do
    from m in Message,
      group_by: m.chat_id,
      select: %{chat_id: m.chat_id, first_at: min(m.inserted_at)}
  end
end
