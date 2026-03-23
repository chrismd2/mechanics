defmodule Mechanics.Chats do
  @moduledoc """
  Chats between mechanics and customers (private messages or listing-specific).
  """

  import Ecto.Query, warn: false

  alias Mechanics.Accounts.User
  alias Mechanics.Chats.Chat
  alias Mechanics.Chats.Message
  alias Mechanics.Chats.Policy
  alias Mechanics.Listings.Listing
  alias Mechanics.Profiles
  alias Mechanics.Repo

  @doc """
  Short heading for lists, the document `<h1>`, and similar. Same as `chat_header_for_viewer/2` **title**.

  For full context (pay, poster, description, mechanic profile fields, etc.), use **`details`** from
  `chat_header_for_viewer/2` in the UI.
  """
  def title_for_viewer(chat, viewer) do
    chat_header_for_viewer(chat, viewer).title
  end

  @doc """
  One-line title for **account conversation cards** and similar compact lists (no detail rows).

  Restores context that was split into `chat_header_for_viewer/2` **details**: e.g. PM with headline
  snippet, listing pay and poster, or owner view with mechanic headline and job.
  """
  def card_title_for_viewer(%Chat{listing_id: nil} = chat, %User{} = viewer) do
    cond do
      viewer.id == chat.customer_user_id ->
        case Repo.get(User, chat.mechanic_user_id) do
          %User{} = mechanic_user ->
            mechanic_label = display_name_or_email(mechanic_user)

            case mechanic_headline_trimmed(chat.mechanic_user_id) do
              nil -> "PM with #{mechanic_label}"
              h -> "PM with #{mechanic_label} · #{h}"
            end

          _ ->
            "Private message"
        end

      viewer.id == chat.mechanic_user_id ->
        case Repo.get(User, chat.customer_user_id) do
          %User{} = customer_user ->
            "PM with #{display_name_or_email(customer_user)}"

          _ ->
            "Private message"
        end

      true ->
        "Private message"
    end
  end

  def card_title_for_viewer(%Chat{listing_id: lid} = chat, %User{} = viewer) when not is_nil(lid) do
    listing = chat.listing || Repo.get(Listing, lid)

    case listing do
      %Listing{} = l ->
        job_title = if is_binary(l.title) and l.title != "", do: l.title, else: "Job"

        cond do
          viewer.id == chat.mechanic_user_id ->
            poster =
              case Repo.get(User, l.customer_id) do
                %User{} = poster_user -> display_name_or_email(poster_user)
                _ -> "Customer"
              end

            "#{job_title} · #{format_listing_price(l)} · posted by #{poster}"

          viewer.id == chat.customer_user_id ->
            case Repo.get(User, chat.mechanic_user_id) do
              %User{} = mechanic_user ->
                mlabel = display_name_or_email(mechanic_user)

                case mechanic_headline_trimmed(chat.mechanic_user_id) do
                  nil -> "#{mlabel} · #{job_title}"
                  h -> "#{mlabel} · #{h} — #{job_title}"
                end

              _ ->
                listing_fallback_title(l)
            end

          true ->
            listing_fallback_title(l)
        end

      _ ->
        "Listing conversation"
    end
  end

  @doc """
  Heading plus **labeled details** for the chat page and notification rows.

  * **Private PM** — title is `PM with {other}`; when the viewer is the customer and the mechanic
    has a profile, **Name**, **Headline**, **Bio**, and **Location** appear as detail rows (non-empty
    fields only).
  * **Listing thread** — mechanic sees the **job title** as the heading; **Pay**, **Posted by**,
    and **Description** (when present) as details. The listing owner sees the **mechanic’s name**
    as the heading; then the same **profile** rows when present, then **Job** and **Description**.
  """
  def chat_header_for_viewer(%Chat{listing_id: nil} = chat, %User{} = viewer) do
    cond do
      viewer.id == chat.customer_user_id ->
        case Repo.get(User, chat.mechanic_user_id) do
          %User{} = mechanic_user ->
            mechanic_label = display_name_or_email(mechanic_user)

            %{title: "PM with #{mechanic_label}", details: mechanic_profile_detail_rows(mechanic_user)}

          _ ->
            %{title: "Private message", details: []}
        end

      viewer.id == chat.mechanic_user_id ->
        case Repo.get(User, chat.customer_user_id) do
          %User{} = customer_user ->
            %{title: "PM with #{display_name_or_email(customer_user)}", details: []}

          _ ->
            %{title: "Private message", details: []}
        end

      true ->
        %{title: "Private message", details: []}
    end
  end

  def chat_header_for_viewer(%Chat{listing_id: lid} = chat, %User{} = viewer) when not is_nil(lid) do
    listing = chat.listing || Repo.get(Listing, lid)

    case listing do
      %Listing{} = l ->
        job_title = if is_binary(l.title) and l.title != "", do: l.title, else: "Job"

        cond do
          viewer.id == chat.mechanic_user_id ->
            poster =
              case Repo.get(User, l.customer_id) do
                %User{} = poster_user -> display_name_or_email(poster_user)
                _ -> "Customer"
              end

            details =
              [
                %{label: "Pay", value: format_listing_price(l)},
                %{label: "Posted by", value: poster}
              ] ++ listing_description_details(l)

            %{title: job_title, details: details}

          viewer.id == chat.customer_user_id ->
            case Repo.get(User, chat.mechanic_user_id) do
              %User{} = mechanic_user ->
                mlabel = display_name_or_email(mechanic_user)

                details =
                  mechanic_profile_detail_rows(mechanic_user) ++
                    [%{label: "Job", value: job_title}] ++ listing_description_details(l)

                %{title: mlabel, details: details}

              _ ->
                %{title: "Listing conversation", details: listing_description_details(l)}
            end

          true ->
            %{title: listing_fallback_title(l), details: listing_description_details(l)}
        end

      _ ->
        %{title: "Listing conversation", details: []}
    end
  end

  defp listing_fallback_title(%Listing{title: title})
       when is_binary(title) and title != "",
       do: "Job: #{title}"

  defp listing_fallback_title(_), do: "Listing conversation"

  defp listing_description_details(%Listing{description: d}) when is_binary(d) do
    t = String.trim(d)
    if t != "", do: [%{label: "Description", value: t}], else: []
  end

  defp listing_description_details(_), do: []

  defp display_name_or_email(%User{name: name, email: email}) do
    cond do
      is_binary(name) and String.trim(name) != "" -> name
      is_binary(email) and email != "" -> email
      true -> "User"
    end
  end

  defp format_listing_price(%Listing{price_cents: cents, currency: cur}) when is_integer(cents) do
    whole = div(cents, 100)
    frac = cents |> rem(100) |> abs() |> Integer.to_string() |> String.pad_leading(2, "0")
    currency = if is_binary(cur) and cur != "", do: String.upcase(cur), else: "USD"
    "$#{whole}.#{frac} #{currency}"
  end

  defp format_listing_price(_), do: "—"

  defp mechanic_headline_trimmed(mechanic_user_id) do
    case Profiles.list_profiles_by(%{user_id: mechanic_user_id}) |> List.first() do
      %{headline: h} when is_binary(h) ->
        t = String.trim(h)
        if t != "", do: t, else: nil

      _ ->
        nil
    end
  end

  defp mechanic_profile_detail_rows(%User{} = mechanic) do
    case Profiles.list_profiles_by(%{user_id: mechanic.id}) |> List.first() do
      %{headline: headline, bio: bio, city: city, state: state} = _profile ->
        name = display_name_or_email(mechanic)

        []
        |> maybe_detail_row("Name", name)
        |> maybe_detail_row("Headline", trimmed_non_empty(headline))
        |> maybe_detail_row("Bio", trimmed_non_empty(bio))
        |> maybe_detail_row("Location", profile_location_line(city, state))

      _ ->
        []
    end
  end

  defp maybe_detail_row(rows, _label, nil), do: rows
  defp maybe_detail_row(rows, _label, ""), do: rows

  defp maybe_detail_row(rows, label, value) when is_binary(value) do
    rows ++ [%{label: label, value: value}]
  end

  defp trimmed_non_empty(s) when is_binary(s) do
    t = String.trim(s)
    if t != "", do: t, else: nil
  end

  defp trimmed_non_empty(_), do: nil

  defp profile_location_line(city, state) do
    c = if is_binary(city), do: String.trim(city), else: ""
    s = if is_binary(state), do: String.trim(state), else: ""

    cond do
      c != "" and s != "" -> "#{c}, #{s}"
      c != "" -> c
      s != "" -> s
      true -> nil
    end
  end

  @doc false
  def create_chat(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    %Chat{}
    |> Chat.create_changeset(attrs)
    |> Repo.insert()
  end

  def fetch_chat(chat_id, %User{} = user) do
    case Repo.get(Chat, chat_id) do
      nil ->
        {:error, :not_found}

      %Chat{} = chat ->
        if Policy.can_access?(chat, user) do
          {:ok, Repo.preload(chat, [:listing])}
        else
          {:error, :forbidden}
        end
    end
  end

  def list_chats_for_user(%User{} = user) do
    from(c in Chat,
      where: c.mechanic_user_id == ^user.id or c.customer_user_id == ^user.id,
      order_by: [desc: c.updated_at, desc: c.id]
    )
    |> Repo.all()
    |> Repo.preload([:listing])
    |> Enum.filter(&Policy.can_access?(&1, user))
  end

  def update_chat(%Chat{} = chat, attrs, %User{} = user) when is_map(attrs) do
    with {:ok, chat} <- authorize_participant(chat, user) do
      chat
      |> Chat.update_changeset(stringify_keys(attrs))
      |> Repo.update()
    end
  end

  def delete_chat(%Chat{} = chat, %User{} = user) do
    with {:ok, chat} <- authorize_participant(chat, user) do
      Repo.delete(chat)
    end
  end

  defp authorize_participant(%Chat{} = chat, %User{} = user) do
    if Policy.can_access?(chat, user) do
      {:ok, chat}
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Opens or creates a private message chat (no listing) between a customer and a mechanic.
  """
  def get_or_create_private_pm(%User{} = customer, %User{} = mechanic) do
    with :ok <- require_role(customer, "customer"),
         :ok <- require_role(mechanic, "mechanic"),
         false <- customer.id == mechanic.id do
      find_or_insert_pm(customer.id, mechanic.id)
    else
      true -> {:error, :invalid_participants}
      {:error, reason} -> {:error, reason}
    end
  end

  defp find_or_insert_pm(customer_id, mechanic_id) do
    query =
      from c in Chat,
        where:
          is_nil(c.listing_id) and c.customer_user_id == ^customer_id and
            c.mechanic_user_id == ^mechanic_id

    case Repo.one(query) do
      %Chat{} = chat ->
        {:ok, Repo.preload(chat, [:listing])}

      nil ->
        %Chat{}
        |> Chat.create_changeset(%{
          "mechanic_user_id" => mechanic_id,
          "customer_user_id" => customer_id,
          "listing_id" => nil
        })
        |> Repo.insert()
        |> case do
          {:ok, chat} -> {:ok, Repo.preload(chat, [:listing])}
          other -> other
        end
    end
  end

  @doc """
  Opens or creates a chat between `mechanic` and the listing owner about `listing_id`.
  """
  def get_or_create_listing_chat(%User{} = mechanic, listing_id)
      when is_binary(listing_id) do
    with :ok <- require_role(mechanic, "mechanic") do
      case Repo.get(Listing, listing_id) do
        nil ->
          {:error, :not_found}

        %Listing{} = listing ->
          cond do
            not listing.is_public ->
              {:error, :forbidden}

            listing.customer_id == mechanic.id ->
              {:error, :forbidden}

            true ->
              case Repo.get(User, listing.customer_id) do
                %User{} = customer ->
                  case require_role(customer, "customer") do
                    :ok -> find_or_insert_listing_chat(mechanic.id, customer.id, listing.id)
                    {:error, _} = err -> err
                  end

                nil ->
                  {:error, :not_found}
              end
          end
      end
    end
  end

  defp find_or_insert_listing_chat(mechanic_id, customer_id, listing_id) do
    query =
      from c in Chat,
        where:
          c.listing_id == ^listing_id and c.mechanic_user_id == ^mechanic_id and
            c.customer_user_id == ^customer_id

    case Repo.one(query) do
      %Chat{} = chat ->
        {:ok, Repo.preload(chat, [:listing])}

      nil ->
        %Chat{}
        |> Chat.create_changeset(%{
          "mechanic_user_id" => mechanic_id,
          "customer_user_id" => customer_id,
          "listing_id" => listing_id
        })
        |> Repo.insert()
        |> case do
          {:ok, chat} -> {:ok, Repo.preload(chat, [:listing])}
          other -> other
        end
    end
  end

  defp require_role(%User{roles: roles}, role) do
    if role in roles, do: :ok, else: {:error, :forbidden}
  end

  def create_message(chat_id, %User{} = sender, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, chat} <- fetch_chat(chat_id, sender),
         :ok <- require_sender_participant(chat, sender),
         {:ok, msg} <- insert_message(chat, sender, attrs) do
      _ = touch_chat_timestamp(chat)
      {:ok, msg}
    end
  end

  defp require_sender_participant(%Chat{} = chat, %User{} = sender) do
    if sender.id in [chat.mechanic_user_id, chat.customer_user_id] do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp insert_message(%Chat{} = chat, %User{} = sender, attrs) do
    %Message{}
    |> Message.create_changeset(
      Map.merge(attrs, %{
        "chat_id" => chat.id,
        "sender_user_id" => sender.id
      })
    )
    |> Repo.insert()
  end

  defp touch_chat_timestamp(%Chat{} = chat) do
    chat
    |> Ecto.Changeset.change(%{updated_at: DateTime.utc_now() |> DateTime.truncate(:second)})
    |> Repo.update()
  end

  def list_messages(chat_id, %User{} = user) do
    with {:ok, chat} <- fetch_chat(chat_id, user) do
      messages =
        from(m in Message,
          where: m.chat_id == ^chat.id,
          order_by: [asc: m.inserted_at, asc: m.id],
          preload: [:sender]
        )
        |> Repo.all()

      {:ok, messages}
    end
  end

  def fetch_message(message_id, %User{} = user) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{} = message ->
        with {:ok, _chat} <- fetch_chat(message.chat_id, user) do
          {:ok, message}
        end
    end
  end

  def update_message(%Message{} = message, attrs, %User{} = user) when is_map(attrs) do
    with {:ok, message} <- authorize_message_editor(message, user) do
      message
      |> Message.update_changeset(stringify_keys(attrs))
      |> Repo.update()
    end
  end

  def delete_message(%Message{} = message, %User{} = user) do
    with {:ok, message} <- authorize_message_editor(message, user) do
      Repo.delete(message)
    end
  end

  defp authorize_message_editor(%Message{} = message, %User{} = user) do
    with {:ok, _} <- fetch_chat(message.chat_id, user) do
      if message.sender_user_id == user.id do
        {:ok, message}
      else
        {:error, :forbidden}
      end
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
