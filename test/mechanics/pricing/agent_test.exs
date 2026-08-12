defmodule Mechanics.Pricing.AgentTest do
  use Mechanics.DataCase, async: false

  alias Mechanics.Accounts
  alias Mechanics.Pricing
  alias Mechanics.Pricing.Agent

  defp pricing_user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Accounts.create_user(%{
        "email" => "pricing-user-#{suffix}@example.com",
        "name" => "Pricing User",
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
        "price_type" => "listing",
        "source_url" => "https://example.com/outback-#{System.unique_integer([:positive])}"
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
        "price_type" => "sale",
        "source_url" => "https://example.com/forester-#{System.unique_integer([:positive])}"
      })

    result = Agent.execute_tool("get_vehicle_market_price_details", %{"ids" => [market_price.id]})

    assert is_list(result)
    row = hd(result)
    cents = Map.get(row, :price_cents) || Map.get(row, "price_cents")
    type = Map.get(row, :price_type) || Map.get(row, "price_type")
    assert cents == 2_400_000
    assert type == "sale"
  end

  test "suggest falls back to heuristic when LLM returns HTTP 401 (invalid key)" do
    user = pricing_user!()

    {:ok, _} =
      Pricing.create_market_price(user, %{
        "make" => "Kenworth",
        "model" => "T880",
        "year" => 2016,
        "miles" => 41_921,
        "price_cents" => 2_600_000,
        "price_type" => "listing",
        "source_url" => "https://example.com/t880-#{System.unique_integer([:positive])}"
      })

    http =
      fn _url, _headers, _body ->
        {:ok, %{status: 401, body: ~s({"error":{"message":"Invalid API Key"}})}}
      end

    result =
      Agent.suggest(
        %{
          "make" => "Kenworth",
          "model" => "T880",
          "year" => 2016,
          "miles" => 41_921,
          "zipcode" => "00000"
        },
        api_key: "invalid-key",
        http_client: http
      )

    assert result.competitive_cents == 2_600_000
    assert result.minimum_cents == 2_600_000
    assert result.match_count == 1
    assert result.summary =~ "matching vehicle market prices"
    refute result.summary =~ "suggested_competitive_cents"
  end

  test "suggest falls back to heuristic when LLM http_client raises" do
    user = pricing_user!()

    {:ok, _} =
      Pricing.create_market_price(user, %{
        "make" => "Volvo",
        "model" => "VNL",
        "year" => 2018,
        "miles" => 200_000,
        "price_cents" => 3_100_000,
        "price_type" => "sale",
        "source_url" => "https://example.com/vnl-#{System.unique_integer([:positive])}"
      })

    http = fn _url, _headers, _body -> raise "connection reset" end

    result =
      Agent.suggest(
        %{
          "make" => "Volvo",
          "model" => "VNL",
          "year" => 2018,
          "miles" => 200_000,
          "zipcode" => "00000"
        },
        api_key: "any-key",
        http_client: http
      )

    assert result.competitive_cents == 3_100_000
    assert result.minimum_cents == 3_100_000
    assert result.match_count == 1
  end

  test "suggest accepts partial LLM JSON with null minimum without showing raw JSON" do
    user = pricing_user!()

    {:ok, _} =
      Pricing.create_market_price(user, %{
        "make" => "Peterbilt",
        "model" => "579",
        "year" => 2017,
        "miles" => 50_000,
        "price_cents" => 2_600_000,
        "price_type" => "listing",
        "source_url" => "https://example.com/579-#{System.unique_integer([:positive])}"
      })

    llm_body =
      ~s({"suggested_competitive_cents": 2600000, "suggested_minimum_cents": null, "summary": "Only one listing found, insufficient data for expected-minimum price."})

    http =
      fn _url, _headers, _body ->
        {:ok,
         %{
           status: 200,
           body:
             Jason.encode!(%{
               "choices" => [
                 %{"message" => %{"role" => "assistant", "content" => llm_body}}
               ]
             })
         }}
      end

    result =
      Agent.suggest(
        %{
          "make" => "Peterbilt",
          "model" => "579",
          "year" => 2017,
          "miles" => 50_000,
          "zipcode" => "00000"
        },
        api_key: "valid-looking-key",
        http_client: http
      )

    assert result.competitive_cents == 2_600_000
    assert is_nil(result.minimum_cents)
    assert result.summary == "Only one listing found, insufficient data for expected-minimum price."
    refute result.summary =~ "{"
  end
end
