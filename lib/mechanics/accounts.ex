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
    list_users_by_role("mechanic")
  end

  def list_customers do
    list_users_by_role("customer")
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

  # Form and seeds send `role` (single); User schema stores `roles` (list).
  # A user only has `customer` role if it was assigned.
  defp normalize_roles(attrs) when is_map(attrs) do
    cond do
      # Registration / seeds send a single `role` key.
      role = attrs["role"] || attrs[:role] ->
        case role do
          "mechanic" -> Map.put(Map.drop(attrs, ["role", :role]), "roles", ["mechanic"])
          "customer" -> Map.put(Map.drop(attrs, ["role", :role]), "roles", ["customer"])
          _ -> attrs
        end

      # Some callers (including tests) may pass `roles: ["mechanic"]`.
      roles = attrs["roles"] || attrs[:roles] ->
        normalize_roles_from_list(attrs, roles)

      true ->
        attrs
    end
  end

  defp normalize_roles_from_list(attrs, roles) do
    roles_list =
      cond do
        is_binary(roles) -> [roles]
        is_list(roles) -> roles
        true -> roles
      end

    roles_list =
      if is_list(roles_list) do
        Enum.map(roles_list, fn
          r when is_atom(r) -> Atom.to_string(r)
          r -> r
        end)
      else
        roles_list
      end

    Map.put(Map.drop(attrs, ["roles", :roles]), "roles", roles_list)
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

  defp list_users_by_role(role) do
    Repo.all(
      from u in User,
        where: fragment("? = ANY(?)", ^role, u.roles),
        order_by: [desc: u.inserted_at, desc: u.id]
    )
  end
end
