defmodule Mechanics.Pricing.SourcesTest do
  use ExUnit.Case, async: true

  alias Mechanics.Pricing.AuctionSource
  alias Mechanics.Pricing.Sources
  alias Mechanics.Pricing.Sources.Royal

  test "infer_kind from host" do
    assert Sources.infer_kind("https://bid.sextonauctioneers.com") == "bidwrangler"
    assert Sources.infer_kind("https://live.royalauctiongroup.com") == "royal"
    assert Sources.infer_kind("https://nashville.craigslist.org") == "craigslist"
  end

  test "craigslist stub is not implemented" do
    source = %AuctionSource{
      kind: "craigslist",
      base_url: "https://craigslist.org",
      label: "CL",
      enabled: true,
      config: %{}
    }

    assert {:error, :not_implemented} = Sources.search(source, "f100", [])
  end

  test "royal search uses GraphQL lots and compact hits" do
    source = %AuctionSource{
      id: Ecto.UUID.generate(),
      kind: "royal",
      base_url: "https://live.royalauctiongroup.com",
      label: "Royal",
      enabled: true,
      config: %{}
    }

    http_post = fn url, body ->
      assert url == "https://live.royalauctiongroup.com/api"
      decoded = Jason.decode!(body)
      assert decoded["operationName"] == "get_lots_search"
      assert get_in(decoded, ["variables", "search", "text"]) == "ford f450"

      {:ok,
       Jason.encode!(%{
         "data" => %{
           "lots" => %{
             "total" => 1,
             "lots" => [
               %{
                 "auction_lot_id" => "76823",
                 "title" => "2018 Ford F-550",
                 "public_url" =>
                   "/auctions/6375/lot/76823-2018-ford-f-550-crew-cab-enclosed-service-truck",
                 "auction_lot_status" => 200,
                 "winning_bid_amount" => 21_000,
                 "auction" => %{"auction_id" => "6375", "title" => "June Auction"}
               }
             ]
           }
         }
       })}
    end

    assert {:ok, [hit]} = Sources.search(source, "ford f450", http_post: http_post)
    assert hit["external_id"] == "76823"
    assert hit["title"] == "2018 Ford F-550"
    assert String.contains?(hit["source_url"], "/lot/76823")
    refute Map.has_key?(hit["raw"], "images")
  end

  test "royal parse_lot_url and attrs_from_lot" do
    assert {:ok, %{lot_id: "76823", auction_id: "6375"}} =
             Royal.parse_lot_url(
               "https://live.royalauctiongroup.com/auctions/6375/lot/76823-2018-ford-f-550-crew-cab"
             )

    attrs =
      Royal.attrs_from_lot(%{
        "title" => "2018 Ford F-550 Crew Cab",
        "auction_lot_status" => 200,
        "winning_bid_amount" => 21_000,
        "lot_number" => "120",
        "description_plain" => "Miles: 85,000 VIN ABCDEFGH1JKLMNOPQ",
        "auction" => %{"title" => "June Auction"}
      })

    assert attrs["year"] == 2018
    assert attrs["make"] == "Ford"
    assert attrs["price_cents"] == 2_100_000
    assert attrs["price_type"] == "sale"
    assert attrs["miles"] == 85_000
  end

  test "royal attrs_from_lot treats Odom Reads N/A as miles 0" do
    attrs =
      Royal.attrs_from_lot(%{
        "title" => "2006 Ford F450 Versalift Bucket Truck",
        "auction_lot_status" => 200,
        "winning_bid_amount" => 1250,
        "lot_number" => "385-NR",
        "description_plain" =>
          "VIN: 1FDXF46Y06ED19911 Odom Reads N/A, title odom reads exempt. Pwd by Triton 6.8L V10 gas engine, automatic transmission. GVWR 16,000lbs, GAWR front 5,600lbs, and GAWR rear 12,000lbs, Versalift boom bucket, service body, storage compartments, running boards, am/fm stereo, heat and a/c. *Non-Runner*",
        "auction" => %{"title" => "December Auction"}
      })

    assert attrs["year"] == 2006
    assert attrs["make"] == "Ford"
    assert attrs["model"] == "F450 Versalift Bucket Truck"
    assert String.length(attrs["model"]) < 255
    assert attrs["miles"] == 0
    assert attrs["price_cents"] == 125_000
    assert attrs["price_type"] == "sale"
    assert attrs["vin"] == "1FDXF46Y06ED19911"
    assert Mechanics.Pricing.BidWrangler.complete_extract_attrs?(attrs)
  end
end
