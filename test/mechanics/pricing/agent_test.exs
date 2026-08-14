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
             (Map.get(row, :id) == market_price.id or Map.get(row, "id") == market_price.id) and
               (Map.get(row, :source) == "local" or Map.get(row, "source") == "local")
           end)
  end

  test "listing search candidates expose candidate: tool ids and price details" do
    {:ok, source} =
      Mechanics.Pricing.ListingSearch.create_auction_source(%{
        "kind" => "bidwrangler",
        "base_url" => "https://bid.example.com",
        "label" => "Example"
      })

    http_get = fn url ->
      assert String.contains?(url, "/api/items/search?query=")

      {:ok,
       Jason.encode!(%{
         "items" => [
           %{
             "id" => 42,
             "auction_id" => 9,
             "name" => "2019 Ford F450",
             "status" => "sold",
             "api_bidding_state" => %{"closing_bid" => %{"amount" => 12_000}}
           }
         ]
       })}
    end

    assert {:ok, [candidate]} =
             Mechanics.Pricing.ListingSearch.search("Ford F450",
               sources: [source],
               http_get: http_get
             )

    row = Mechanics.Pricing.ListingSearch.candidate_to_search_row(candidate)
    assert String.starts_with?(row.id, "candidate:")
    assert row.source == "external"
    assert row.price_type == "sale"

    details = Mechanics.Pricing.ListingSearch.get_candidate_price_details([row.id])
    assert hd(details).price_cents == 1_200_000

    merged =
      Agent.execute_tool("get_vehicle_market_price_details", %{"ids" => [row.id]})

    assert Enum.any?(merged, fn d -> Map.get(d, :price_cents) == 1_200_000 end)
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

  test "suggest uses heuristic when LLM returns null prices but seed comps exist" do
    user = pricing_user!()

    {:ok, _} =
      Pricing.create_market_price(user, %{
        "make" => "Ford",
        "model" => "F450",
        "year" => 2008,
        "miles" => 149_092,
        "price_cents" => 425_000,
        "price_type" => "sale",
        "source_url" => "https://example.com/f450-null-llm-#{System.unique_integer([:positive])}"
      })

    llm_body =
      ~s({"suggested_competitive_cents": null, "suggested_minimum_cents": null, "summary": "Insufficient data."})

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
          "make" => "ford",
          "model" => "f450",
          "year" => 2008,
          "miles" => 0,
          "zipcode" => "00000"
        },
        api_key: "valid-looking-key",
        http_client: http
      )

    assert result.competitive_cents == 425_000
    assert result.minimum_cents == 425_000
    assert result.match_count >= 1
    assert result.summary =~ "Suggested from"
  end

  describe "extract_listing_from_url/2 BidWrangler" do
    test "fetches /api/items/:id only and maps sold item without LLM" do
      ui = "https://bid.sextonauctioneers.com/ui/auctions/154363/23926836"
      item_api = "https://bid.sextonauctioneers.com/api/items/23926836"

      item_json =
        Jason.encode!(%{
          "id" => 23_926_836,
          "name" => "2008 Victory Kingpin 8-Ball Motorcycle",
          "vin" => "5VPPB26D883006543",
          "status" => "sold",
          "currency_name" => "USD",
          "simple_id" => "#24221",
          "lot_identifier" => "24221",
          "auction_name" => "Sexton Auction",
          "description_without_html" =>
            "Item Location: Pomona, MO 65789 Year: 2008 Make: Victory Model: Kingpin 8-Ball Mileage:47,040",
          "api_bidding_state" => %{
            "closing_bid" => %{"amount" => 3850},
            "high" => %{"amount" => 3850}
          },
          "images" => List.duplicate(%{"url" => "x"}, 20)
        })

      http_get = fn url ->
        refute String.contains?(url, "/api/auctions/")
        assert url == item_api
        {:ok, item_json}
      end

      assert {:ok, attrs} =
               Agent.extract_listing_from_url(ui,
                 http_get: http_get,
                 api_key: "should-not-be-used",
                 http_client: fn _, _, _ -> flunk("LLM should not run when attrs are complete") end
               )

      assert attrs["make"] == "Victory"
      assert attrs["model"] == "Kingpin 8-Ball"
      assert attrs["year"] == 2008
      assert attrs["miles"] == 47_040
      assert attrs["price_cents"] == 385_000
      assert attrs["price_type"] == "sale"
      assert attrs["vin"] == "5VPPB26D883006543"
      assert attrs["zipcode"] == "65789"
    end

    test "falls back to LLM on compact summary when required fields are missing" do
      ui = "https://bid.example.com/ui/auctions/1/2"
      item_api = "https://bid.example.com/api/items/2"

      item_json =
        Jason.encode!(%{
          "id" => 2,
          "name" => "Mystery Lot",
          "status" => "preview",
          "currency_name" => "USD",
          "description_without_html" => "No labeled vehicle fields here",
          "images" => List.duplicate(%{}, 10)
        })

      http_get = fn url ->
        refute String.contains?(url, "/api/auctions/")
        assert url == item_api
        {:ok, item_json}
      end

      http_client = fn _url, _headers, body ->
        decoded = Jason.decode!(body)
        user = Enum.find(decoded["messages"], &(&1["role"] == "user"))
        content = user["content"]
        refute content =~ "images"
        assert content =~ "Mystery Lot"

        {:ok,
         %{
           status: 200,
           body:
             Jason.encode!(%{
               "choices" => [
                 %{
                   "message" => %{
                     "content" =>
                       ~s({"make":"Ford","model":"F-150","year":2018,"miles":50000,"price_cents":1500000,"currency":"USD","price_type":"listing","vin":null,"notes":null,"zipcode":null})
                   }
                 }
               ]
             })
         }}
      end

      assert {:ok, attrs} =
               Agent.extract_listing_from_url(ui,
                 http_get: http_get,
                 api_key: "test-key",
                 http_client: http_client
               )

      assert attrs["make"] == "Ford"
      assert attrs["model"] == "F-150"
      assert attrs["year"] == 2018
      assert attrs["miles"] == 50_000
      assert attrs["price_cents"] == 1_500_000
    end
  end

  describe "page_text_from_html/1" do
    test "keeps Open Graph title and description for JS-rendered auction shells" do
      html = """
      <!DOCTYPE html>
      <html>
        <head>
          <title>Sexton Auctioneers, LLC</title>
          <meta property="og:title" content="2008 Victory Kingpin 8-Ball Motorcycle"/>
          <meta property="og:description" content="Year: 2008 Make: Victory Model: Kingpin 8-Ball Mileage:47,040 VIN #: 5VPPB26D883006543"/>
        </head>
        <body>
          <div id="root"></div>
          <script>window.app = {}</script>
        </body>
      </html>
      """

      text = Agent.page_text_from_html(html)

      assert text =~ "2008 Victory Kingpin 8-Ball Motorcycle"
      assert text =~ "Make: Victory"
      assert text =~ "Kingpin 8-Ball"
      assert text =~ "47,040"
      assert text =~ "5VPPB26D883006543"
      refute text =~ "<script"
      refute text =~ "window.app"
    end

    test "still includes visible body text when present" do
      html = """
      <html><body><h1>2019 Toyota Camry</h1><p>Miles: 40000 Asking $19,000</p></body></html>
      """

      text = Agent.page_text_from_html(html)

      assert text =~ "2019 Toyota Camry"
      assert text =~ "40000"
      assert text =~ "19,000"
    end
  end
end
