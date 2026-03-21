defmodule MechanicsWeb.Plugs.AssignDefaultLayout do
  @moduledoc """
  Sets layout-related assigns so templates can read `@wide_layout` without KeyError.
  Controllers may override (e.g. account overview uses a wider main column).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    assign(conn, :wide_layout, false)
  end
end
