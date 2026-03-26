defmodule Mechanics.AccountsFixtures do
  alias Mechanics.Accounts.User
  alias Mechanics.Listings.Listing
  alias Mechanics.Profiles.Profile
  alias Mechanics.Repo

  def insert_user!(attrs \\ %{}) do
    now = DateTime.utc_now() |> truncate_datetime()

    %User{
      email: Map.get(attrs, :email, "user@example.com"),
      name: Map.get(attrs, :name, "Test User"),
      password_hash: Bcrypt.hash_pwd_salt(Map.get(attrs, :password, "secret123")),
      roles: Map.get(attrs, :roles, []),
      email_verified: Map.get(attrs, :email_verified, true),
      inserted_at: Map.get(attrs, :inserted_at, now) |> truncate_datetime(),
      updated_at: Map.get(attrs, :updated_at, now) |> truncate_datetime()
    }
    |> Repo.insert!()
  end

  def insert_profile!(attrs \\ %{}) do
    now = DateTime.utc_now() |> truncate_datetime()

    %Profile{
      headline: Map.get(attrs, :headline, "Mobile mechanic"),
      bio: Map.get(attrs, :bio, "I come to you. ASE certified."),
      city: Map.get(attrs, :city, "Phoenix"),
      state: Map.get(attrs, :state, "AZ"),
      is_public: Map.get(attrs, :is_public, false),
      user_id: Map.fetch!(attrs, :user_id),
      inserted_at: Map.get(attrs, :inserted_at, now) |> truncate_datetime(),
      updated_at: Map.get(attrs, :updated_at, now) |> truncate_datetime()
    }
    |> Repo.insert!()
  end

  def insert_listing!(attrs \\ %{}) do
    now = DateTime.utc_now() |> truncate_datetime()

    %Listing{
      title: Map.get(attrs, :title, "Oil change"),
      description: Map.get(attrs, :description, "Standard oil change service"),
      price_cents: Map.get(attrs, :price_cents, 5_000),
      currency: Map.get(attrs, :currency, "USD"),
      is_public: Map.get(attrs, :is_public, false),
      customer_id: Map.fetch!(attrs, :customer_id),
      inserted_at: Map.get(attrs, :inserted_at, now) |> truncate_datetime(),
      updated_at: Map.get(attrs, :updated_at, now) |> truncate_datetime()
    }
    |> Repo.insert!()
  end

  defp truncate_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :second)
  defp truncate_datetime(datetime), do: datetime
end
