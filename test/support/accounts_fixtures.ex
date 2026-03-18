defmodule Mechanics.AccountsFixtures do
  alias Mechanics.Accounts.User
  alias Mechanics.Repo

  def insert_user!(attrs \\ %{}) do
    now = DateTime.utc_now() |> truncate_datetime()

    %User{
      email: Map.get(attrs, :email, "user@example.com"),
      name: Map.get(attrs, :name, "Test User"),
      password_hash: Bcrypt.hash_pwd_salt(Map.get(attrs, :password, "secret123")),
      roles: Map.get(attrs, :roles, []),
      inserted_at: Map.get(attrs, :inserted_at, now) |> truncate_datetime(),
      updated_at: Map.get(attrs, :updated_at, now) |> truncate_datetime()
    }
    |> Repo.insert!()
  end

  defp truncate_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
  defp truncate_datetime(datetime), do: datetime
end
