defmodule Mechanics.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Mechanics.Repo
  alias Mechanics.Accounts.User

  def list_users do
    Repo.all(User)
  end

  def list_mechanics do
    Repo.all(
      from u in User,
        where: fragment("? = ANY(?)", "mechanic", u.roles),
        order_by: [desc: u.inserted_at]
    )
  end

  def list_customers do
    Repo.all(
      from u in User,
        where: fragment("? = ANY(?)", "customer", u.roles),
        order_by: [desc: u.inserted_at]
    )
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def create_user(attrs \\ %{}) do
    attrs = normalize_roles(attrs)

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  # Form and seeds send :role (single); User schema uses :roles (list).
  # Mechanic gets ["customer", "mechanic"]; customer gets ["customer"].
  defp normalize_roles(attrs) when is_map(attrs) do
    case attrs["role"] || attrs[:role] do
      "mechanic" -> Map.put(Map.drop(attrs, ["role", :role]), "roles", ["customer", "mechanic"])
      "customer" -> Map.put(Map.drop(attrs, ["role", :role]), "roles", ["customer"])
      _ -> attrs
    end
  end

  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    case user do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        if Bcrypt.verify_pass(password, user.password_hash) do
          {:ok, user}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end
end
