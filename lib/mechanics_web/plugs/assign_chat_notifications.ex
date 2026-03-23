defmodule MechanicsWeb.Plugs.AssignChatNotifications do
  @moduledoc false
  import Plug.Conn

  alias Mechanics.Chats.Notifications

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      nil ->
        assign(conn, :chat_notification_feed, nil)

      user ->
        assign(conn, :chat_notification_feed, Notifications.header_feed(user))
    end
  end
end
