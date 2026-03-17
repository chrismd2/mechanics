defmodule Mechanics.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :password_hash, :string
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :roles, {:array, :string}

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

  defp validate_roles(changeset) do
    validate_change(changeset, :roles, fn :roles, roles ->
      if is_list(roles) and Enum.all?(roles, &(&1 in @valid_roles)) and "customer" in roles do
        []
      else
        [roles: "must be a list containing at least 'customer' and optionally 'mechanic'"]
      end
    end)
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    change(changeset, %{password_hash: Bcrypt.hash_pwd_salt(password)})
  end

  defp put_password_hash(changeset), do: changeset
end
