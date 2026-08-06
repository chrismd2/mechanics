defmodule Mechanics.Invites.Invite do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User
  alias Mechanics.Chats.Chat
  alias Mechanics.Listings.Listing

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @subject_types ~w(conversation listing profile)

  schema "invites" do
    field :token, :string
    field :subject_type, :string
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :chat, Chat
    belongs_to :listing, Listing
    belongs_to :mechanic_user, User, foreign_key: :mechanic_user_id
    belongs_to :inviter_user, User, foreign_key: :inviter_user_id
    belongs_to :accepted_by_user, User, foreign_key: :accepted_by_user_id

    timestamps(type: :utc_datetime)
  end

  def subject_types, do: @subject_types

  def create_changeset(invite, attrs) do
    invite
    |> cast(attrs, [
      :token,
      :subject_type,
      :chat_id,
      :listing_id,
      :mechanic_user_id,
      :inviter_user_id,
      :expires_at
    ])
    |> validate_required([:token, :subject_type, :inviter_user_id, :expires_at])
    |> validate_inclusion(:subject_type, @subject_types)
    |> unique_constraint(:token)
    |> validate_subject_refs()
    |> foreign_key_constraint(:chat_id)
    |> foreign_key_constraint(:listing_id)
    |> foreign_key_constraint(:mechanic_user_id)
    |> foreign_key_constraint(:inviter_user_id)
  end

  def accept_changeset(invite, attrs) do
    invite
    |> cast(attrs, [:accepted_by_user_id, :accepted_at])
    |> validate_required([:accepted_by_user_id, :accepted_at])
    |> foreign_key_constraint(:accepted_by_user_id)
  end

  defp validate_subject_refs(changeset) do
    case get_field(changeset, :subject_type) do
      "conversation" ->
        changeset
        |> validate_required([:chat_id])
        |> put_change(:listing_id, nil)
        |> put_change(:mechanic_user_id, nil)

      "listing" ->
        changeset
        |> validate_required([:listing_id])
        |> put_change(:chat_id, nil)
        |> put_change(:mechanic_user_id, nil)

      "profile" ->
        changeset
        |> validate_required([:mechanic_user_id])
        |> put_change(:chat_id, nil)
        |> put_change(:listing_id, nil)

      _ ->
        changeset
    end
  end
end
