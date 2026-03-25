defmodule MechanicsWeb.AuthController do
  use MechanicsWeb, :controller

  alias Mechanics.Accounts
  alias Mechanics.LoginAttempts

  def new_registration(conn, _params) do
    changeset = Accounts.change_user(%Mechanics.Accounts.User{})
    render(conn, :new_registration, changeset: changeset)
  end

  def create_registration(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        conn
        |> put_session(:current_user_id, user.id)
        |> put_flash(:info, "Account created successfully!")
        |> redirect(to: registration_redirect_path(user, user_params))

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new_registration, changeset: changeset)
    end
  end

  def new_session(conn, _params) do
    render(conn, :new_session)
  end

  def new_password_reset(conn, %{"token" => token}) do
    case Accounts.get_password_reset_token(token, DateTime.utc_now()) do
      {:ok, _reset_token} ->
        render(conn, :edit_password_reset, token: token)

      {:error, _} ->
        conn
        |> put_flash(:info, "If you have an account with us, then we'll send you a reset request.")
        |> redirect(to: ~p"/login")
    end
  end

  def new_password_reset(conn, _params) do
    render(conn, :new_password_reset)
  end

  def request_password_reset(conn, %{"password_reset" => %{"email" => email}}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    base_url = request_base_url(conn)

    _ = Accounts.request_password_reset(email, now, base_url: base_url)

    conn
    |> put_flash(:info, "If you have an account with us, then we'll send you a reset request.")
    |> redirect(to: ~p"/login")
  end

  def request_password_reset(conn, _params) do
    conn
    |> put_flash(:info, "If you have an account with us, then we'll send you a reset request.")
    |> redirect(to: ~p"/login")
  end

  def confirm_password_reset(conn, %{"password_reset" => %{"token" => token, "password" => password}} = params) do
    confirm = params["password_reset"]["password_confirmation"]

    case Accounts.reset_password_with_token(token, %{
           "password" => password,
           "password_confirmation" => confirm
         }) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password reset successful. You can sign in now.")
        |> redirect(to: ~p"/login")

      {:error, :invalid_token} ->
        conn
        |> put_flash(:info, "If you have an account with us, then we'll send you a reset request.")
        |> redirect(to: ~p"/login")

      {:error, :expired_token} ->
        conn
        |> put_flash(:info, "If you have an account with us, then we'll send you a reset request.")
        |> redirect(to: ~p"/login")

      {:error, %Ecto.Changeset{}} = _err ->
        render(conn, :edit_password_reset, token: token)
    end
  end

  def create_session(conn, %{"session" => %{"email" => email, "password" => password}}) do
    case LoginAttempts.check_locked(email) do
      :ok ->
        do_create_session(conn, email, password)

      {:locked, _lockout_until} ->
        conn
        |> put_flash(:error, "Please try again later.")
        |> render(:new_session)
    end
  end

  def create_session(conn, _params) do
    conn
    |> put_flash(:error, "Invalid email or password")
    |> render(:new_session)
  end

  defp do_create_session(conn, email, password) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        LoginAttempts.clear(email)

        conn
        |> put_session(:current_user_id, user.id)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/")

      {:error, :invalid_credentials} ->
        LoginAttempts.record_failure(email)

        conn
        |> put_flash(:error, "Invalid email or password")
        |> render(:new_session)
    end
  end

  def delete_user_session(conn, _params) do
    conn
    |> delete_session(:current_user_id)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/")
  end

  defp registration_redirect_path(user, user_params) do
    if wants_listing?(user_params) do
      if "mechanic" in user.roles do
        ~p"/profile"
      else
        ~p"/listings/new"
      end
    else
      ~p"/"
    end
  end

  defp wants_listing?(%{"wants_listing" => value}), do: value in [true, "true", "on", "1"]
  defp wants_listing?(_params), do: false

  defp request_base_url(conn) do
    host =
      case Plug.Conn.get_req_header(conn, "x-forwarded-host") do
        [h | _] when is_binary(h) and h != "" -> h
        _ -> conn.host
      end

    "https://#{host}"
  end
end
