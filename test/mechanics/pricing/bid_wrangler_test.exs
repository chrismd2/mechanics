defmodule Mechanics.Pricing.BidWranglerTest do
  use ExUnit.Case, async: true

  alias Mechanics.Pricing.BidWrangler

  @ui_url "https://bid.sextonauctioneers.com/ui/auctions/154363/23926836"
  @item_api "https://bid.sextonauctioneers.com/api/items/23926836"

  describe "parse_item_ui_url/1 and item_api_url/1" do
    test "parses BidWrangler UI item URLs" do
      assert {:ok, %{origin: "https://bid.sextonauctioneers.com", auction_id: "154363", item_id: "23926836"}} =
               BidWrangler.parse_item_ui_url(@ui_url)

      assert BidWrangler.item_api_url(@ui_url) == @item_api
      assert BidWrangler.item_api_url(@ui_url <> "/") == @item_api
    end

    test "rejects non-item URLs" do
      assert :error = BidWrangler.parse_item_ui_url("https://bid.sextonauctioneers.com/api/auctions/154363")
      assert :error = BidWrangler.parse_item_ui_url("https://example.com/listing/1")
      assert BidWrangler.item_api_url("https://example.com/listing/1") == nil
    end
  end

  describe "attrs_from_item/1" do
    test "maps sold item JSON to market price attrs" do
      item = %{
        "id" => 23_926_836,
        "name" => "2008 Victory Kingpin 8-Ball Motorcycle",
        "vin" => "5VPPB26D883006543",
        "status" => "sold",
        "currency_name" => "USD",
        "simple_id" => "#24221",
        "lot_identifier" => "24221",
        "auction_name" => "Day One - April 30th | Sexton Auctioneers April 2026 Online Equipment Auction",
        "description_without_html" =>
          "Item Location: Sexton Auctioneers Yard - 5182 US Hwy 63, Pomona, MO 65789 Principal Contact: Levi O. Year: 2008 Make: Victory Model: Kingpin 8-Ball Vehicle Type: Motorcycle Mileage:47,040 VIN #: 5VPPB26D883006543",
        "api_bidding_state" => %{
          "closing_bid" => %{"amount" => 3850, "status" => "sold"},
          "high" => %{"amount" => 3850}
        },
        "images" => List.duplicate(%{"url" => "https://example.com/img.jpg"}, 50),
        "bidding_schedule" => [%{}, %{}, %{}]
      }

      attrs = BidWrangler.attrs_from_item(item)

      assert attrs["make"] == "Victory"
      assert attrs["model"] == "Kingpin 8-Ball"
      assert attrs["year"] == 2008
      assert attrs["miles"] == 47_040
      assert attrs["vin"] == "5VPPB26D883006543"
      assert attrs["zipcode"] == "65789"
      assert attrs["price_cents"] == 385_000
      assert attrs["price_type"] == "sale"
      assert attrs["currency"] == "USD"
      assert attrs["notes"] =~ "2008 Victory"
      assert attrs["notes"] =~ "#24221"
    end

    test "uses listing_price for non-sold items when present" do
      attrs =
        BidWrangler.attrs_from_item(%{
          "name" => "2019 Toyota Camry",
          "status" => "preview",
          "currency_name" => "USD",
          "listing_price" => 19_000,
          "description_without_html" => "Year: 2019 Make: Toyota Model: Camry Mileage:40,000",
          "api_bidding_state" => %{"high" => %{"amount" => 100}}
        })

      assert attrs["price_type"] == "listing"
      assert attrs["price_cents"] == 1_900_000
      assert attrs["make"] == "Toyota"
      assert attrs["year"] == 2019
      assert attrs["miles"] == 40_000
    end
  end

  describe "compact_summary/1" do
    test "omits images and bidding_schedule" do
      summary =
        BidWrangler.compact_summary(%{
          "name" => "2008 Victory",
          "vin" => "5VPPB26D883006543",
          "status" => "sold",
          "currency_name" => "USD",
          "description_without_html" => "Year: 2008 Make: Victory",
          "images" => List.duplicate(%{}, 50),
          "videos" => [%{}],
          "bidding_schedule" => List.duplicate(%{}, 13),
          "api_bidding_state" => %{"closing_bid" => %{"amount" => 3850}, "high" => %{"amount" => 3850}}
        })

      refute summary =~ "images"
      refute summary =~ "bidding_schedule"
      assert summary =~ "2008 Victory"
      assert summary =~ "3850"
      assert summary =~ "5VPPB26D883006543"
      assert String.length(summary) < 4000
    end
  end
end
