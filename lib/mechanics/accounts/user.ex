defmodule Mechanics.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :roles, {:array, :string}

    # Password reset rate limiting
    field :password_reset_count, :integer, default: 0
    field :password_reset_last_sent_at, :utc_datetime

    has_many :listings, Mechanics.Listings.Listing, foreign_key: :customer_id

    timestamps(type: :utc_datetime)
  end

  @valid_roles ~w(mechanic customer)
  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :password, :password_confirmation, :roles])
    |> validate_required([:email, :name, :password, :password_confirmation, :roles])
    |> validate_format(:email, ~r/@/)
    |> validate_roles()
    |> validate_length(:password, min: 6)
    |> validate_confirmation(:password)
    |> unique_constraint(:email)
    |> put_password_hash()
  end

  @doc """
  Updates display name and email while signed in (password unchanged).
  """
  def settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
  end

  @doc """
  Updates the user's role(s).

  Used for in-app role changes like "becoming a mechanic".
  """
  def roles_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:roles])
    |> validate_roles()
  end

  @doc """
  Changeset used for password resets. It does not require email/name/roles.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password, :password_confirmation])
    |> validate_required([:password, :password_confirmation])
    |> validate_length(:password, min: 6)
    |> validate_confirmation(:password)
    |> put_password_hash()
  end

  defp validate_roles(changeset) do
    validate_change(changeset, :roles, fn :roles, roles ->
      if is_list(roles) and roles != [] and Enum.all?(roles, &(&1 in @valid_roles)) do
        []
      else
        [roles: "must be a non-empty list containing only valid roles"]
      end
    end)
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, %{password_hash: Bcrypt.hash_pwd_salt(password)})
  end

  defp put_password_hash(changeset), do: changeset
end
