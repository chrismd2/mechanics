defmodule Mechanics.Profiles do
  @moduledoc """
  The Profiles context.
  """

  import Ecto.Query, warn: false

  alias Mechanics.Repo
  alias Mechanics.Accounts.User
  alias Mechanics.Profiles.Profile

  def list_mechanic_profiles do
    Repo.all(
      from p in Profile,
        join: u in User,
        on: u.id == p.user_id,
        where: p.is_public == true and fragment("? = ANY(?)", "mechanic", u.roles),
        order_by: [desc: p.inserted_at, desc: p.id]
    )
  end

  def get_profile!(id), do: Repo.get!(Profile, id)

  def create_profile(attrs \\ %{}) do
    %Profile{}
    |> Profile.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_profile(%Profile{} = profile, attrs) do
    profile
    |> Profile.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_profile(%Profile{} = profile) do
    Repo.delete(profile)
  end

  def change_profile(%Profile{} = profile, attrs \\ %{}) do
    Profile.update_changeset(profile, attrs)
  end

  @doc """
  Returns a list of profiles filtered by the given params.
  Example params: %{user_id: ..., is_public: ...}
  """
  def list_profiles_by(params) when is_map(params) do
    query =
      Profile
      |> where(^Enum.reduce(params, dynamic(true), fn
        {:user_id, val}, dynamic -> dynamic([p], ^dynamic and p.user_id == ^val)
        {key, val}, dynamic -> dynamic([p], ^dynamic and field(p, ^key) == ^val)
      end))

    Repo.all(from p in query, order_by: [desc: p.inserted_at, desc: p.id])
  end
end
