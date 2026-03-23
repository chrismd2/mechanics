defmodule Mechanics.Chats.ReadState do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User
  alias Mechanics.Chats.Chat

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_read_states" do
    field :last_read_at, :utc_datetime

    belongs_to :user, User
    belongs_to :chat, Chat

    timestamps(type: :utc_datetime)
  end

  @doc false
  def upsert_changeset(state, attrs) do
    state
    |> cast(attrs, [:user_id, :chat_id, :last_read_at])
    |> validate_required([:user_id, :chat_id, :last_read_at])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:chat_id)
    |> unique_constraint([:user_id, :chat_id])
  end
end
