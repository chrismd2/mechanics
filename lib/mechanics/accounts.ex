defmodule Mechanics.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Mechanics.Repo
  alias Mechanics.Accounts.User
  alias Mechanics.Accounts.PasswordResetEmail
  alias Mechanics.Accounts.PasswordResetToken

  def list_users do
    Repo.all(User)
  end

  def list_mechanics do
    list_users_by_role("mechanic")
  end

  def list_customers do
    list_users_by_role("customer")
  end

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) do
    Repo.get_by(User, email: email)
  end

  def create_user(attrs \\ %{}) do
    attrs = normalize_roles(attrs)

    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  # Form and seeds send `role` (single); User schema stores `roles` (list).
  # A user only has `customer` role if it was assigned.
  defp normalize_roles(attrs) when is_map(attrs) do
    cond do
      # Registration / seeds send a single `role` key.
      role = attrs["role"] || attrs[:role] ->
        case role do
          "mechanic" -> Map.put(Map.drop(attrs, ["role", :role]), "roles", ["mechanic"])
          "customer" -> Map.put(Map.drop(attrs, ["role", :role]), "roles", ["customer"])
          _ -> attrs
        end

      # Some callers (including tests) may pass `roles: ["mechanic"]`.
      roles = attrs["roles"] || attrs[:roles] ->
        normalize_roles_from_list(attrs, roles)

      true ->
        attrs
    end
  end

  defp normalize_roles_from_list(attrs, roles) do
    roles_list =
      cond do
        is_binary(roles) -> [roles]
        is_list(roles) -> roles
        true -> roles
      end

    roles_list =
      if is_list(roles_list) do
        Enum.map(roles_list, fn
          r when is_atom(r) -> Atom.to_string(r)
          r -> r
        end)
      else
        roles_list
      end

    Map.put(Map.drop(attrs, ["roles", :roles]), "roles", roles_list)
  end

  def authenticate_user(email, password) do
    user = get_user_by_email(email)

    case user do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        if Bcrypt.verify_pass(password, user.password_hash) do
          # Successful sign-in resets the password reset throttling counters.
          cleared_user =
            user
            |> Ecto.Changeset.change(%{
              password_reset_count: 0,
              password_reset_last_sent_at: nil
            })
            |> Repo.update!()

          {:ok, cleared_user}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  @doc """
  Requests a password reset for `email`.

  Returns `{:ok, :sent}` if a reset email was sent, otherwise `{:ok, :not_sent}`
  (response content is intentionally ambiguous at the web layer).
  """
  def request_password_reset(email, now \\ DateTime.utc_now()) do
    # Ecto :utc_datetime columns in this project are configured to reject microseconds.
    # Truncate to second precision to avoid "expects microseconds to be empty" errors.
    now = DateTime.truncate(now, :second)

    user = get_user_by_email(email)
    window_seconds = 6 * 60 * 60
    threshold = DateTime.add(now, -window_seconds, :second)

    case user do
      nil ->
        {:ok, :not_sent}

      %User{} = user ->
        {count_in_window, allowed} =
          cond do
            is_nil(user.password_reset_last_sent_at) ->
              {0, true}

            DateTime.compare(user.password_reset_last_sent_at, threshold) == :lt ->
              {0, true}

            true ->
              {user.password_reset_count || 0, (user.password_reset_count || 0) < 3}
          end

        if allowed do
          token = generate_password_reset_token()
          expires_at = DateTime.add(now, password_reset_token_validity_seconds(), :second)

          {:ok, _} =
            Repo.transaction(fn ->
            %PasswordResetToken{}
            |> PasswordResetToken.changeset(%{
              token: token,
              user_id: user.id,
              expires_at: DateTime.truncate(expires_at, :second)
            })
            |> Repo.insert!()

            PasswordResetEmail.deliver(user, token)

            user
            |> Ecto.Changeset.change(%{
              password_reset_count: count_in_window + 1,
              password_reset_last_sent_at: now
            })
            |> Repo.update!()
          end)

          {:ok, :sent}
        else
          {:ok, :not_sent}
        end
    end
  end

  defp generate_password_reset_token do
    32
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  @doc """
  Returns the reset token record if it's valid (exists and not expired).
  """
  def get_password_reset_token(token, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    case Repo.get_by(PasswordResetToken, token: token) do
      nil ->
        {:error, :invalid_token}

      %PasswordResetToken{expires_at: expires_at} = reset_token ->
        if DateTime.compare(expires_at, now) in [:eq, :gt] do
          {:ok, reset_token}
        else
          {:error, :expired_token}
        end
    end
  end

  @doc """
  Resets the user's password for a given reset token.
  Token is deleted after successful reset.
  """
  def reset_password_with_token(token, %{"password" => password, "password_confirmation" => confirm}, now \\ DateTime.utc_now()) do
    now = DateTime.truncate(now, :second)

    with {:ok, %PasswordResetToken{} = reset_token} <- get_password_reset_token(token, now) do
      user = Repo.get!(User, reset_token.user_id)

      changeset = User.password_changeset(user, %{
        password: password,
        password_confirmation: confirm
      })

      case Repo.update(changeset) do
        {:ok, user} ->
          Repo.delete!(reset_token)
          {:ok, user}

        {:error, changeset} ->
          {:error, changeset}
      end
    end
  end

  defp password_reset_token_validity_seconds do
    # Token validity window (server-side). Keep testable by DB expiration updates.
    60 * 60
  end

  defp list_users_by_role(role) do
    Repo.all(
      from u in User,
        where: fragment("? = ANY(?)", ^role, u.roles),
        order_by: [desc: u.inserted_at, desc: u.id]
    )
  end
end
