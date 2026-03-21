defmodule Mechanics.Chats.Message do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User
  alias Mechanics.Chats.Chat

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_messages" do
    field :body, :string

    belongs_to :chat, Chat
    belongs_to :sender, User, foreign_key: :sender_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [:body, :chat_id, :sender_user_id])
    |> validate_required([:body, :chat_id, :sender_user_id])
    |> validate_length(:body, min: 1, max: 10_000)
    |> foreign_key_constraint(:chat_id)
    |> foreign_key_constraint(:sender_user_id)
  end

  @doc false
  def update_changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 10_000)
  end
end
