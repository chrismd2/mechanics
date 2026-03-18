defmodule Mechanics.AccountsFixtures do
  alias Mechanics.Accounts.User
  alias Mechanics.Repo

  def insert_user!(attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    %User{
      email: Map.get(attrs, :email, "user@example.com"),
      name: Map.get(attrs, :name, "Test User"),
      password_hash: Bcrypt.hash_pwd_salt(Map.get(attrs, :password, "secret123")),
      roles: Map.get(attrs, :roles, ["mechanic"]),
      inserted_at: Map.get(attrs, :inserted_at, now),
      updated_at: Map.get(attrs, :updated_at, now)
    }
    |> Repo.insert!()
  end
end
