defmodule MechanicsWeb.Plugs.Authenticate do
  import Plug.Conn

  alias Mechanics.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :current_user_id)

    if user_id do
      current_user = Accounts.get_user!(user_id)
      assign(conn, :current_user, current_user)
    else
      assign(conn, :current_user, nil)
    end
  end
end
