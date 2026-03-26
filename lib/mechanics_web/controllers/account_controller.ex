defmodule MechanicsWeb.AccountController do
  use MechanicsWeb, :controller

  import Phoenix.Component, only: [to_form: 2]

  alias Mechanics.Accounts
  alias Mechanics.Accounts.User
  alias Mechanics.Chats.Notifications
  alias Mechanics.Listings
  alias Mechanics.Profiles
  alias Mechanics.Profiles.Profile

  def show(conn, params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to view your account.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        conn
        |> assign_account_page(user, account_tab: Map.get(params, "tab"))
        |> render(:show)
    end
  end

  def update(conn, params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to update your account.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        case Map.get(params, "account") do
          account_params when is_map(account_params) ->
            case Accounts.update_user_settings(user, account_params, base_url: request_base_url(conn)) do
              {:ok, updated_user} ->
                conn
                |> put_flash(
                  :info,
                  if(updated_user.email != user.email,
                    do: "Account settings updated. Please verify your new email address.",
                    else: "Account settings updated."
                  )
                )
                |> redirect(to: account_path(tab: "settings"))

              {:error, %Ecto.Changeset{} = changeset} ->
                conn
                |> assign_account_page(user,
                  account_tab: "settings",
                  user_form: to_form(changeset, as: :account)
                )
                |> render(:show)
            end

          _ ->
            conn
            |> put_flash(:error, "Invalid form submission.")
            |> redirect(to: account_path(tab: "settings"))
        end
    end
  end

  def become_mechanic(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in to update your account.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        case Accounts.add_mechanic_role(user) do
          {:ok, _updated_user} ->
            conn
            |> put_flash(:info, "You're now a mechanic.")
            |> redirect(to: account_path(tab: "settings"))

          {:error, :not_customer} ->
            conn
            |> put_flash(:error, "Only customers can become mechanics.")
            |> redirect(to: account_path(tab: "settings"))

          {:error, %Ecto.Changeset{}} ->
            conn
            |> put_flash(:error, "Could not update your role. Please try again.")
            |> redirect(to: account_path(tab: "settings"))
        end
    end
  end

  def update_password(conn, params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in first.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        case Map.get(params, "account_password") do
          %{"password" => p, "password_confirmation" => c}
          when is_binary(p) and is_binary(c) ->
            case Accounts.update_user_password(user, %{"password" => p, "password_confirmation" => c}) do
              {:ok, _} ->
                conn
                |> put_flash(:info, "Password updated.")
                |> redirect(to: account_path(tab: "settings"))

              {:error, %Ecto.Changeset{} = changeset} ->
                conn
                |> assign_account_page(user,
                  account_tab: "settings",
                  password_changeset: changeset
                )
                |> render(:show)
            end

          _ ->
            conn
            |> put_flash(:error, "Enter and confirm your new password.")
            |> redirect(to: account_path(tab: "settings"))
        end
    end
  end

  def delete_account(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "Sign in first.")
        |> redirect(to: ~p"/login")

      %User{} = user ->
        case Accounts.delete_user(user) do
          {:ok, _deleted_user} ->
            conn
            |> configure_session(drop: true)
            |> put_flash(:info, "Your account was deleted.")
            |> redirect(to: ~p"/")

          {:error, _changeset} ->
            conn
            |> put_flash(:error, "Could not delete your account right now. Please try again.")
            |> redirect(to: account_path(tab: "settings"))
        end
    end
  end

  defp assign_account_page(conn, %User{} = user, extra) do
    extra_map = Enum.into(extra, %{})
    attempted_profile_params = get_session(conn, :attempted_profile_params) || %{}
    conn = delete_session(conn, :attempted_profile_params)
    feed = Notifications.header_feed(user, compact: true)
    user_form = Map.get(extra_map, :user_form) || to_form(Accounts.change_user_settings(user), as: :account)
    {profile, profile_changeset} = mechanic_profile_forms(user, attempted_profile_params)

    password_form =
      case Map.get(extra_map, :password_changeset) do
        %Ecto.Changeset{} = cs -> to_form(cs, as: :account_password)
        _ -> to_form(%{"password" => "", "password_confirmation" => ""}, as: :account_password)
      end

    user_listings =
      if "customer" in user.roles do
        Listings.list_listings_by(%{customer_id: user.id})
      else
        []
      end

    requested_tab = Map.get(extra_map, :account_tab) || Map.get(extra_map, "account_tab")
    account_tab = normalize_account_tab(requested_tab, user_listings)

    conn
    |> assign(:page_title, "Account")
    |> assign(:wide_layout, true)
    |> assign(:notification_feed, feed)
    |> assign(:user_form, user_form)
    |> assign(:profile, profile)
    |> assign(:profile_changeset, profile_changeset)
    |> assign(:liability_acknowledged, attempted_profile_params["liability_disclaimer_accepted"] in ["true", "on", "1"])
    |> assign(:user_listings, user_listings)
    |> assign(:password_form, password_form)
    |> assign(:account_tab, account_tab)
  end

  defp account_path(opts) when is_list(opts) do
    base = ~p"/account"
    case Keyword.get(opts, :tab) do
      nil -> base
      tab when is_binary(tab) -> "#{base}?#{URI.encode_query(%{"tab" => tab})}"
      _ -> base
    end
  end

  defp request_base_url(conn) do
    host =
      case Plug.Conn.get_req_header(conn, "x-forwarded-host") do
        [h | _] when is_binary(h) and h != "" -> h
        _ -> conn.host
      end

    "https://#{host}"
  end

  defp normalize_account_tab(requested, user_listings) do
    allowed = ["notifications", "settings"]
    allowed = if user_listings != [], do: ["listings" | allowed], else: allowed

    req =
      case requested do
        t when is_binary(t) -> String.trim(t)
        _ -> ""
      end

    if req != "" and req in allowed, do: req, else: "notifications"
  end

  defp mechanic_profile_forms(%User{} = user, attempted_profile_params) do
    if "mechanic" in user.roles do
      profile = Profiles.list_profiles_by(%{user_id: user.id}) |> List.first()

      changeset =
        cond do
          profile ->
            Profiles.change_profile(profile, attempted_profile_params)

          true ->
            Profile.update_changeset(
              %Profile{user_id: user.id, is_public: false},
              attempted_profile_params
            )
        end

      {profile, changeset}
    else
      {nil, nil}
    end
  end
end
