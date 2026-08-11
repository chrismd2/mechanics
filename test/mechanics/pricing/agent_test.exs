defmodule Mechanics.Pricing.AgentTest do
  use Mechanics.DataCase, async: false

  alias Mechanics.Accounts
  alias Mechanics.Pricing
  alias Mechanics.Pricing.Agent

  defp pricing_user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        "email" => "pricing-agent-#{suffix}@example.com",
        "name" => "Agent User",
        "roles" => ["customer", "pricing_user"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user
  end

  test "tool_definitions includes search_vehicle_market_prices and get_vehicle_market_price_details" do
    names =
      Agent.tool_definitions()
      |> Enum.map(fn tool -> get_in(tool, ["function", "name"]) || get_in(tool, [:function, :name]) end)

    assert "search_vehicle_market_prices" in names
    assert "get_vehicle_market_price_details" in names
  end

  test "execute_tool search_vehicle_market_prices returns matching rows from the database" do
    user = pricing_user!()

    {:ok, market_price} =
      Pricing.create_market_price(user, %{
        "make" => "Subaru",
        "model" => "Outback",
        "year" => 2021,
        "miles" => 25_000,
        "price_cents" => 2_800_000,
        "price_type" => "listing"
      })

    result =
      Agent.execute_tool("search_vehicle_market_prices", %{
        "make" => "Subaru",
        "model" => "Outback",
        "price_type" => "listing"
      })

    assert is_list(result)

    assert Enum.any?(result, fn row ->
             Map.get(row, :id) == market_price.id or Map.get(row, "id") == market_price.id
           end)
  end

  test "execute_tool get_vehicle_market_price_details returns price fields for ids" do
    user = pricing_user!()

    {:ok, market_price} =
      Pricing.create_market_price(user, %{
        "make" => "Subaru",
        "model" => "Forester",
        "year" => 2020,
        "miles" => 35_000,
        "price_cents" => 2_400_000,
        "price_type" => "sale"
      })

    result = Agent.execute_tool("get_vehicle_market_price_details", %{"ids" => [market_price.id]})

    assert is_list(result)
    row = hd(result)
    cents = Map.get(row, :price_cents) || Map.get(row, "price_cents")
    type = Map.get(row, :price_type) || Map.get(row, "price_type")
    assert cents == 2_400_000
    assert type == "sale"
  end
end
