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
      attempted_profile_params = get_session(conn, :attempted_profile_params) || %{}
      conn = delete_session(conn, :attempted_profile_params)

      profile =
        if current_user do
          Profiles.list_profiles_by(%{user_id: current_user.id}) |> List.first()
        end

      changeset =
        cond do
          profile ->
            Profiles.change_profile(profile, attempted_profile_params)

          current_user ->
            Profile.update_changeset(
              %Profile{user_id: current_user.id, is_public: false},
              attempted_profile_params
            )

          true ->
            Profile.update_changeset(%Profile{is_public: false}, attempted_profile_params)
        end

      render(conn, :show,
        changeset: changeset,
        profile: profile,
        liability_acknowledged: attempted_profile_params["liability_disclaimer_accepted"] in ["true", "on", "1"]
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

      {attrs, forced_private?} = enforce_private_if_unverified(attrs, current_user)
      redirect_target = profile_redirect_target(conn, attrs)
      success_redirect_target = profile_success_redirect_target(attrs)

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
            |> delete_session(:attempted_profile_params)
            |> put_flash(
              :info,
              if(forced_private?, do: "Profile saved. Verify your email to make it public.", else: "Profile saved successfully.")
            )
            |> redirect(to: success_redirect_target)

          {:error, %Ecto.Changeset{} = changeset} ->
            conn
            |> put_session(:attempted_profile_params, profile_params)
            |> put_flash(:error, profile_error_message(changeset))
            |> redirect(to: redirect_target)

          {:error, _other} ->
            conn
            |> put_session(:attempted_profile_params, profile_params)
            |> put_flash(:error, "Could not save profile right now. Please try again.")
            |> redirect(to: redirect_target)
        end
      else
        conn
        |> put_session(:attempted_profile_params, profile_params)
        |> put_flash(:error, "Please accept the liability notice to save your profile.")
        |> redirect(to: redirect_target)
      end
    end
  end

  defp profile_redirect_target(conn, profile_params) do
    return_to =
      (profile_params["return_to"] || profile_params[:return_to] || "")
      |> to_string()
      |> String.trim()

    cond do
      String.starts_with?(return_to, "/account") ->
        return_to

      String.starts_with?(return_to, "/profile") ->
        return_to

      true ->
        fallback_referer_path(conn)
    end
  end

  defp profile_success_redirect_target(profile_params) do
    return_to =
      (profile_params["return_to"] || profile_params[:return_to] || "")
      |> to_string()
      |> String.trim()

    if String.starts_with?(return_to, "/account"), do: return_to, else: ~p"/"
  end

  defp fallback_referer_path(conn) do
    case Plug.Conn.get_req_header(conn, "referer") do
      [referer | _] ->
        uri = URI.parse(referer)
        path = uri.path || "/profile"

        if uri.query in [nil, ""] do
          path
        else
          "#{path}?#{uri.query}"
        end

      _ ->
        ~p"/profile"
    end
  end

  defp profile_error_message(%Ecto.Changeset{} = changeset) do
    state_errors = Keyword.get_values(changeset.errors, :state)

    if state_errors != [] do
      "Could not save profile. State must be a 2-letter abbreviation (example: AL)."
    else
      "Could not save profile. Please check your entries and try again."
    end
  end

  defp enforce_private_if_unverified(attrs, current_user) do
    wants_public? = attrs["is_public"] in [true, "true", "on", "1"]

    if current_user.email_verified do
      {attrs, false}
    else
      {Map.put(attrs, "is_public", false), wants_public?}
    end
  end
end
