defmodule MechanicsWeb.InviteController do
  use MechanicsWeb, :controller

  alias Mechanics.Accounts.User
  alias Mechanics.Invites

  def create_for_chat(conn, %{"chat_id" => chat_id}) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to create an invite.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        case Invites.create_conversation_invite(user, chat_id) do
          {:ok, invite} ->
            url = url(~p"/invites/#{invite.token}")

            conn
            |> put_flash(:info, "Invite link ready: #{url}")
            |> redirect(to: ~p"/chats/#{chat_id}")

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Conversation not found.")
            |> redirect(to: ~p"/")

          {:error, :forbidden} ->
            conn
            |> put_flash(:error, "You cannot invite people to this conversation.")
            |> redirect(to: ~p"/chats/#{chat_id}")

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not create invite.")
            |> redirect(to: ~p"/chats/#{chat_id}")
        end
    end
  end

  def show(conn, %{"token" => token}) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to accept this invite.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        with {:ok, invite} <- Invites.get_by_token(token),
             {:ok, chat} <- Invites.accept(invite, user) do
          conn
          |> put_flash(:info, "Invite accepted. Opening the conversation.")
          |> redirect(to: ~p"/chats/#{chat.id}")
        else
          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Invite not found.")
            |> redirect(to: ~p"/")

          {:error, :expired} ->
            conn
            |> put_flash(:error, "This invite has expired.")
            |> redirect(to: ~p"/")

          {:error, :already_accepted} ->
            conn
            |> put_flash(:error, "This invite was already used.")
            |> redirect(to: ~p"/")

          {:error, :forbidden} ->
            conn
            |> put_flash(:error, "You are not allowed to join via this invite.")
            |> redirect(to: ~p"/")

          {:error, :no_chat_yet} ->
            conn
            |> put_flash(:info, "Invite accepted, but there is no conversation yet for that listing.")
            |> redirect(to: ~p"/")

          {:error, _} ->
            conn
            |> put_flash(:error, "Could not accept invite.")
            |> redirect(to: ~p"/")
        end
    end
  end
end
