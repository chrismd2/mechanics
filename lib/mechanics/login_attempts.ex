defmodule Mechanics.LoginAttempts do
  @moduledoc """
  Tracks failed login attempts per email and enforces lockout after too many failures.
  """
  @max_attempts 5
  @lockout_seconds 15 * 60

  def init do
    if :ets.whereis(:mechanics_login_attempts) == :undefined do
      :ets.new(:mechanics_login_attempts, [:set, :public, :named_table])
    end
    :ok
  end

  @doc """
  Returns :ok if the email is not locked out, or {:locked, lockout_until_ts} if locked.
  """
  def check_locked(email) when is_binary(email) do
    key = normalize_email(email)
    now = System.system_time(:second)

    case :ets.lookup(:mechanics_login_attempts, key) do
      [] ->
        :ok

      [{^key, _count, lockout_until}] when is_integer(lockout_until) and lockout_until > now ->
        {:locked, lockout_until}

      [_] ->
        :ok
    end
  end

  @doc """
  Records a failed attempt for the given email. Returns :ok or {:locked, lockout_until_ts}
  when the account is now locked (after max attempts).
  """
  def record_failure(email) when is_binary(email) do
    key = normalize_email(email)
    now = System.system_time(:second)
    lockout_until = now + @lockout_seconds

    updated =
      case :ets.lookup(:mechanics_login_attempts, key) do
        [] ->
          {1, lockout_until}

        [{^key, count, _}] ->
          new_count = count + 1
          lockout = if new_count >= @max_attempts, do: lockout_until, else: 0
          {new_count, lockout}
      end

    {count, lockout_ts} = updated
    :ets.insert(:mechanics_login_attempts, {key, count, lockout_ts})

    if count >= @max_attempts do
      {:locked, lockout_ts}
    else
      :ok
    end
  end

  @doc """
  Clears attempt count for the given email (e.g. after successful login).
  """
  def clear(email) when is_binary(email) do
    key = normalize_email(email)
    :ets.delete(:mechanics_login_attempts, key)
    :ok
  end

  @doc """
  Clears all attempt data. For use in tests.
  """
  def clear_all do
    :ets.delete_all_objects(:mechanics_login_attempts)
    :ok
  end

  defp normalize_email(email), do: String.downcase(String.trim(email))
end
