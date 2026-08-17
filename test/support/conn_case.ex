defmodule MechanicsWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use MechanicsWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate
  import ExUnit.Assertions

  using do
    quote do
      # The default endpoint for testing
      @endpoint MechanicsWeb.Endpoint

      use MechanicsWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import MechanicsWeb.ConnCase
    end
  end

  setup tags do
    Mechanics.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Asserts a disclaimer dialog is a vertical scroll container so mobile users can
  reach Accept when the notice is taller than the viewport.
  """
  def assert_scrollable_disclaimer_modal(html, selector) do
    parsed = Floki.parse_document!(html)
    nodes = Floki.find(parsed, selector)
    assert nodes != [], "expected #{selector} on the page"

    class = nodes |> hd() |> Floki.attribute("class") |> List.first() || ""
    assert class =~ "overflow-y-auto"
    assert class =~ "overscroll-contain"

    panel = Floki.find(hd(nodes), "[data-disclaimer-modal-panel]")
    assert panel != [], "#{selector} should wrap the notice in data-disclaimer-modal-panel"
  end
end
