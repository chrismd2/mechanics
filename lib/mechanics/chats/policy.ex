defmodule Mechanics.Chats.Policy do
  @moduledoc """
  Authorization for chat access: participants must still hold the role
  required for their side of the conversation (mechanic vs customer).
  """

  alias Mechanics.Chats.Chat
  alias Mechanics.Accounts.User

  @doc """
  Returns true if `user` is a participant and still has the role required
  for their participant slot on this chat.
  """
  def can_access?(%Chat{} = chat, %User{} = user) do
    participant?(chat, user) && role_matches_participant?(chat, user)
  end

  defp participant?(%Chat{} = chat, %User{} = user) do
    user.id in [chat.mechanic_user_id, chat.customer_user_id]
  end

  defp role_matches_participant?(%Chat{} = chat, %User{} = user) do
    cond do
      user.id == chat.mechanic_user_id -> "mechanic" in user.roles
      user.id == chat.customer_user_id -> "customer" in user.roles
      true -> false
    end
  end
end
