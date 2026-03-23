defmodule MechanicsWeb.ProfileController do
  use MechanicsWeb, :controller

  alias Mechanics.Disclaimers
  alias Mechanics.Profiles
  alias Mechanics.Profiles.Profile
  alias Mechanics.Repo

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
        result =
          Repo.transaction(fn ->
            profile_result =
              case profile do
                nil -> Profiles.create_profile(attrs)
                %Profile{} = existing -> Profiles.update_profile(existing, attrs)
              end

            case profile_result do
              {:ok, %Profile{} = saved_profile} ->
                with {:ok, _agreement} <- Disclaimers.log_user_agreement(current_user.id, :liability) do
                  saved_profile
                else
                  {:error, _} = err -> Repo.rollback(err)
                end

              {:error, %Ecto.Changeset{} = changeset} ->
                Repo.rollback(changeset)
            end
          end)

        case result do
          {:ok, %Profile{} = _profile} ->
            conn
            |> put_flash(:info, "Profile saved successfully.")
            |> redirect(to: profile_redirect_target(profile_params))

          {:error, %Ecto.Changeset{} = changeset} ->
            render(
              conn,
              :show,
              changeset: changeset,
              profile: profile,
              liability_acknowledged: false
            )

          {:error, _other} ->
            changeset =
              cond do
                profile -> Profiles.change_profile(profile, attrs)
                true -> Profile.create_changeset(%Profile{}, attrs)
              end

            render(conn, :show, changeset: changeset, profile: profile, liability_acknowledged: false)
        end
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

  defp profile_redirect_target(profile_params) do
    return_to =
      (profile_params["return_to"] || profile_params[:return_to] || "")
      |> to_string()
      |> String.trim()

    if return_to == "/account" do
      ~p"/account"
    else
      ~p"/"
    end
  end
end
