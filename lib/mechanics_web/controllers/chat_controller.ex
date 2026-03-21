defmodule MechanicsWeb.ChatController do
  use MechanicsWeb, :controller

  alias Mechanics.Accounts.User
  alias Mechanics.Chats
  alias Mechanics.Chats.Notifications
  alias Mechanics.Listings.Listing
  alias Mechanics.Repo

  def show(conn, %{"id" => chat_id}) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to view this conversation.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        case Chats.fetch_chat(chat_id, user) do
          {:ok, chat} ->
            _ = Notifications.mark_chat_read(chat.id, user)
            {:ok, messages} = Chats.list_messages(chat.id, user)

            header = Chats.chat_header_for_viewer(chat, user)

            conn
            |> assign(:chat, chat)
            |> assign(:messages, messages)
            |> assign(:chat_header, header)
            |> assign(:title, header.title)
            |> render(:show)

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "Conversation not found.")
            |> redirect(to: ~p"/")

          {:error, :forbidden} ->
            send_unauthorized(conn)
        end
    end
  end

  def open_listing_owner_next(conn, %{"listing_id" => listing_id}) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to view messages about your listing.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        cond do
          "customer" not in user.roles ->
            send_unauthorized(conn)

          true ->
            case Repo.get(Listing, listing_id) do
              nil ->
                conn
                |> put_flash(:error, "Listing not found.")
                |> redirect(to: ~p"/")

              %Listing{customer_id: cid} when cid != user.id ->
                conn
                |> put_flash(:error, "You can only open chats for your own listings.")
                |> redirect(to: ~p"/")

              %Listing{} ->
                case Notifications.first_unread_listing_chat_id_for_owner(listing_id, user) do
                  {:ok, chat_id} ->
                    redirect(conn, to: ~p"/chats/#{chat_id}")

                  {:error, :no_unread} ->
                    conn
                    |> put_flash(:info, "No unread messages for this listing right now.")
                    |> redirect(to: ~p"/listings/#{listing_id}/edit")
                end
            end
        end
    end
  end

  def open_mechanic_pm_next(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to view your messages.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        cond do
          "mechanic" not in user.roles ->
            send_unauthorized(conn)

          true ->
            case Notifications.first_unread_private_pm_chat_id_for_mechanic(user) do
              {:ok, chat_id} ->
                redirect(conn, to: ~p"/chats/#{chat_id}")

              {:error, :no_unread} ->
                conn
                |> put_flash(:info, "No unread private messages right now.")
                |> redirect(to: ~p"/")

              {:error, :forbidden} ->
                send_unauthorized(conn)
            end
        end
    end
  end

  def create_message(conn, %{"id" => chat_id, "message" => message_params}) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to send a message.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        body = message_params["body"] || message_params[:body] || ""
        body = String.trim(to_string(body))

        case Chats.create_message(chat_id, user, %{body: body}) do
          {:ok, _} ->
            redirect(conn, to: ~p"/chats/#{chat_id}")

          {:error, %Ecto.Changeset{}} ->
            conn
            |> put_flash(:error, "Message could not be sent. Check your text and try again.")
            |> redirect(to: ~p"/chats/#{chat_id}")

          {:error, _} ->
            conn
            |> put_flash(:error, "You cannot send a message in this conversation.")
            |> redirect(to: ~p"/")
        end
    end
  end

  def create_message(conn, %{"id" => chat_id}) do
    create_message(conn, %{"id" => chat_id, "message" => %{}})
  end

  def open_by_mechanic(conn, %{"mechanic_user_id" => mechanic_user_id}) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to message a mechanic.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        cond do
          "customer" not in user.roles ->
            send_unauthorized(conn)

          true ->
            case Repo.get(User, mechanic_user_id) do
              %User{} = mechanic ->
                if "mechanic" in mechanic.roles do
                  case Chats.get_or_create_private_pm(user, mechanic) do
                    {:ok, chat} ->
                      redirect(conn, to: ~p"/chats/#{chat.id}")

                    {:error, :invalid_participants} ->
                      conn
                      |> put_flash(:error, "You cannot message yourself.")
                      |> redirect(to: ~p"/")

                    {:error, _} ->
                      conn
                      |> put_flash(:error, "Could not open conversation.")
                      |> redirect(to: ~p"/")
                  end
                else
                  conn
                  |> put_flash(:error, "That user is not a mechanic.")
                  |> redirect(to: ~p"/")
                end

              nil ->
                conn
                |> put_flash(:error, "Mechanic not found.")
                |> redirect(to: ~p"/")
            end
        end
    end
  end

  def open_by_listing(conn, %{"listing_id" => listing_id}) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to discuss a job listing.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        if "mechanic" not in user.roles do
          send_unauthorized(conn)
        else
          case Chats.get_or_create_listing_chat(user, listing_id) do
            {:ok, chat} ->
              redirect(conn, to: ~p"/chats/#{chat.id}")

            {:error, :not_found} ->
              conn
              |> put_flash(:error, "Listing not found.")
              |> redirect(to: ~p"/")

            {:error, :forbidden} ->
              send_unauthorized(conn)
          end
        end
    end
  end

  defp send_unauthorized(conn) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(403, "You are not authorized to use this feature.")
  end
end
