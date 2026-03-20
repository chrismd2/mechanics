defmodule MechanicsWeb.ProfileController do
  use MechanicsWeb, :controller

  alias Mechanics.Profiles
  alias Mechanics.Profiles.Profile

  def show(conn, _params) do
    current_user = conn.assigns[:current_user]

    unless current_user && "mechanic" in current_user.roles do
      conn
      |> redirect(to: ~p"/")
    else
      profile =
        if current_user do
          Profiles.list_profiles_by(%{user_id: current_user.id}) |> List.first()
        end

      changeset =
        cond do
          profile ->
            Profiles.change_profile(profile)

          current_user ->
            Profile.update_changeset(
              %Profile{user_id: current_user.id, is_public: false},
              %{}
            )

          true ->
            Profile.update_changeset(%Profile{is_public: false}, %{})
        end

      render(conn, :show,
        changeset: changeset,
        profile: profile,
        liability_acknowledged: false
      )
    end
  end

  def save(conn, %{"profile" => profile_params}) do
    current_user = conn.assigns[:current_user]

    liability_accepted? =
      profile_params["liability_disclaimer_accepted"] in ["true", "on", "1"]

    unless current_user && "mechanic" in current_user.roles do
      conn
      |> put_flash(:error, "Only mechanics can create a profile.")
      |> redirect(to: ~p"/")
    else
      profile = Profiles.list_profiles_by(%{user_id: current_user.id}) |> List.first()

      attrs =
        profile_params
        |> Map.drop(["liability_disclaimer_accepted"])
        |> Map.put("user_id", current_user.id)

      if liability_accepted? do
        {:ok, _profile} =
          case profile do
            nil -> Profiles.create_profile(attrs)
            %Profile{} = existing -> Profiles.update_profile(existing, attrs)
          end

        conn
        |> put_flash(:info, "Profile saved successfully.")
        |> redirect(to: ~p"/")
      else
        changeset =
          cond do
            profile -> Profiles.change_profile(profile, attrs)
            true -> Profile.create_changeset(%Profile{}, attrs)
          end

        render(conn, :show,
          changeset: changeset,
          profile: profile,
          liability_acknowledged: false
        )
      end
    end
  end
end
