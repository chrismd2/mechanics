defmodule MechanicsWeb.Plugs.Authenticate do
  import Plug.Conn

  alias Mechanics.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :current_user_id)

    case user_id && Accounts.get_user(user_id) do
      %{id: _} = current_user ->
        assign(conn, :current_user, current_user)

      _ when not is_nil(user_id) ->
        # Stale session after DB reset / deleted user — treat as logged out.
        conn
        |> delete_session(:current_user_id)
        |> assign(:current_user, nil)

      _ ->
        assign(conn, :current_user, nil)
    end
  end
end
