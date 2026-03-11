defmodule MechanicsWeb.AuthController do
  use MechanicsWeb, :controller

  alias Mechanics.Accounts

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
        |> redirect(to: ~p"/")

      {:error, %Ecto.Changeset{} = changeset} ->
        render(conn, :new_registration, changeset: changeset)
    end
  end

  def new_session(conn, _params) do
    render(conn, :new_session)
  end

  def create_session(conn, %{"session" => %{"email" => email, "password" => password}}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        conn
        |> put_session(:current_user_id, user.id)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/")

      {:error, :invalid_credentials} ->
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
end
