defmodule Mechanics.Chats.Chat do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User
  alias Mechanics.Chats.Message
  alias Mechanics.Listings.Listing

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chats" do
    field :topic, :string

    belongs_to :mechanic_user, User, foreign_key: :mechanic_user_id
    belongs_to :customer_user, User, foreign_key: :customer_user_id
    belongs_to :listing, Listing

    has_many :messages, Message, foreign_key: :chat_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(chat, attrs) do
    chat
    |> cast(attrs, [:topic, :mechanic_user_id, :customer_user_id, :listing_id])
    |> validate_required([:mechanic_user_id, :customer_user_id])
    |> foreign_key_constraint(:mechanic_user_id)
    |> foreign_key_constraint(:customer_user_id)
    |> foreign_key_constraint(:listing_id)
  end

  @doc false
  def update_changeset(chat, attrs) do
    chat
    |> cast(attrs, [:topic])
  end
end
