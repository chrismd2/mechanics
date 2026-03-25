defmodule MechanicsWeb.Plugs.DevRoutes do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    if System.get_env("ENV") == nil or System.get_env("ENV") == "prod" do
      conn
      |> redirect(to: "/")
      |> halt()
    else
      conn
    end
  end
end
