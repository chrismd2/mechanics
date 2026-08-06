defmodule Mechanics.Invites do
  @moduledoc """
  Shareable invites that deep-link into a conversation, listing discussion, or
  mechanic profile discussion.
  """

  import Ecto.Query, warn: false

  alias Mechanics.Accounts.User
  alias Mechanics.Chats
  alias Mechanics.Invites.Invite
  alias Mechanics.Listings.Listing
  alias Mechanics.Repo

  @default_ttl_days 14

  @doc """
  Creates an invite for an existing chat the inviter can access.
  """
  def create_conversation_invite(%User{} = inviter, chat_id) when is_binary(chat_id) do
    with {:ok, chat} <- Chats.fetch_chat(chat_id, inviter) do
      insert_invite(%{
        "subject_type" => "conversation",
        "chat_id" => chat.id,
        "inviter_user_id" => inviter.id
      })
    end
  end

  @doc """
  Creates an invite that opens (or creates) a listing discussion for the accepter.
  """
  def create_listing_invite(%User{} = inviter, listing_id) when is_binary(listing_id) do
    case Repo.get(Listing, listing_id) do
      nil ->
        {:error, :not_found}

      %Listing{} = listing ->
        if listing.customer_id == inviter.id or listing.is_public do
          insert_invite(%{
            "subject_type" => "listing",
            "listing_id" => listing.id,
            "inviter_user_id" => inviter.id
          })
        else
          {:error, :forbidden}
        end
    end
  end

  @doc """
  Creates an invite that opens a profile (PM) discussion with a mechanic.
  """
  def create_profile_invite(%User{} = inviter, mechanic_user_id)
      when is_binary(mechanic_user_id) do
    case Repo.get(User, mechanic_user_id) do
      %User{} = mechanic ->
        if "mechanic" in mechanic.roles do
          insert_invite(%{
            "subject_type" => "profile",
            "mechanic_user_id" => mechanic.id,
            "inviter_user_id" => inviter.id
          })
        else
          {:error, :invalid_subject}
        end

      nil ->
        {:error, :not_found}
    end
  end

  def get_by_token(token) when is_binary(token) do
    case Repo.get_by(Invite, token: token) do
      nil -> {:error, :not_found}
      %Invite{} = invite -> {:ok, Repo.preload(invite, [:chat, :listing, :mechanic_user, :inviter_user])}
    end
  end

  @doc """
  Accepts an invite for `accepter`, returning `{:ok, chat}` to open.
  """
  def accept(%Invite{} = invite, %User{} = accepter) do
    cond do
      not is_nil(invite.accepted_at) ->
        {:error, :already_accepted}

      DateTime.compare(DateTime.utc_now() |> DateTime.truncate(:second), invite.expires_at) == :gt ->
        {:error, :expired}

      true ->
        with {:ok, chat} <- open_subject(invite, accepter),
             {:ok, _} <-
               invite
               |> Invite.accept_changeset(%{
                 "accepted_by_user_id" => accepter.id,
                 "accepted_at" => DateTime.utc_now() |> DateTime.truncate(:second)
               })
               |> Repo.update() do
          {:ok, chat}
        end
    end
  end

  defp open_subject(%Invite{subject_type: "conversation", chat_id: chat_id}, %User{} = user) do
    Chats.fetch_chat(chat_id, user)
  end

  defp open_subject(%Invite{subject_type: "listing", listing_id: listing_id}, %User{} = user) do
    cond do
      "mechanic" in user.roles ->
        Chats.get_or_create_listing_chat(user, listing_id)

      "customer" in user.roles ->
        case Repo.get(Listing, listing_id) do
          %Listing{customer_id: cid} = listing when cid == user.id ->
            # Owner accepting their own listing invite: open first related chat if any
            case Chats.list_chats_for_user(user)
                 |> Enum.find(&(&1.listing_id == listing.id)) do
              nil -> {:error, :no_chat_yet}
              chat -> {:ok, chat}
            end

          %Listing{} ->
            {:error, :forbidden}

          nil ->
            {:error, :not_found}
        end

      true ->
        {:error, :forbidden}
    end
  end

  defp open_subject(%Invite{subject_type: "profile", mechanic_user_id: mechanic_id}, %User{} = user) do
    with %User{} = mechanic <- Repo.get(User, mechanic_id) || :not_found,
         true <- "mechanic" in mechanic.roles,
         true <- "customer" in user.roles,
         false <- user.id == mechanic.id do
      Chats.get_or_create_private_pm(user, mechanic)
    else
      :not_found -> {:error, :not_found}
      false -> {:error, :forbidden}
      {:error, _} = err -> err
    end
  end

  defp insert_invite(attrs) do
    token = generate_token()
    expires_at = DateTime.utc_now() |> DateTime.add(@default_ttl_days, :day) |> DateTime.truncate(:second)

    %Invite{}
    |> Invite.create_changeset(Map.merge(attrs, %{"token" => token, "expires_at" => expires_at}))
    |> Repo.insert()
  end

  defp generate_token do
    :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)
  end
end
