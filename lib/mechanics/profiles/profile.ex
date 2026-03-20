defmodule Mechanics.Profiles.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "profiles" do
    field :headline, :string
    field :bio, :string
    field :city, :string
    field :state, :string
    field :is_public, :boolean, default: false

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(headline bio city state is_public user_id)a
  @editable_fields ~w(headline bio city state is_public)a

  @doc false
  def create_changeset(profile, attrs) do
    profile
    |> cast(attrs, @required_fields)
    |> validate_profile()
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  @doc false
  def update_changeset(profile, attrs) do
    profile
    |> cast(attrs, @editable_fields)
    |> validate_required(@editable_fields)
    |> validate_profile()
  end

  defp validate_profile(changeset) do
    changeset
    |> validate_required(@required_fields -- [:user_id])
    |> validate_length(:state, min: 2, max: 2)
  end
end
