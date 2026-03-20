defmodule Mechanics.Accounts.PasswordResetToken do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "password_reset_tokens" do
    field :token, :string
    field :expires_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(token_struct, attrs) do
    token_struct
    |> cast(attrs, [:token, :user_id, :expires_at])
    |> validate_required([:token, :user_id, :expires_at])
    |> unique_constraint(:token)
  end
end

