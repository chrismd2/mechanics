defmodule Mechanics.PricingTest do
  use Mechanics.DataCase, async: false

  alias Mechanics.Accounts
  alias Mechanics.Pricing

  defp pricing_user!(suffix \\ System.unique_integer([:positive])) do
    {:ok, user} =
      Accounts.create_user(%{
        "email" => "pricing-#{suffix}@example.com",
        "name" => "Pricing User",
        "roles" => ["customer", "pricing_user"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user
  end

  defp url!(label) do
    "https://example.com/vehicles/#{label}-#{System.unique_integer([:positive])}"
  end

  describe "create_market_price/2" do
    test "stores a listing market price for a pricing_user" do
      user = pricing_user!()
      source_url = url!("camry-listing")

      assert {:ok, market_price} =
               Pricing.create_market_price(user, %{
                 "make" => "Toyota",
                 "model" => "Camry",
                 "year" => 2019,
                 "miles" => 45_000,
                 "price_cents" => 1_850_000,
                 "currency" => "USD",
                 "price_type" => "listing",
                 "vin" => "4T1B11HK5KU123456",
                 "source_url" => source_url
               })

      assert market_price.price_type == "listing"
      assert market_price.make == "Toyota"
      assert market_price.model == "Camry"
      assert market_price.year == 2019
      assert market_price.miles == 45_000
      assert market_price.price_cents == 1_850_000
      assert market_price.source_url == source_url
      assert market_price.user_id == user.id
    end

    test "stores a sale market price" do
      user = pricing_user!()

      assert {:ok, market_price} =
               Pricing.create_market_price(user, %{
                 "make" => "Honda",
                 "model" => "Civic",
                 "year" => 2018,
                 "miles" => 60_000,
                 "price_cents" => 1_400_000,
                 "price_type" => "sale",
                 "source_url" => url!("civic-sale")
               })

      assert market_price.price_type == "sale"
    end

    test "rejects invalid price_type" do
      user = pricing_user!()

      assert {:error, changeset} =
               Pricing.create_market_price(user, %{
                 "make" => "Ford",
                 "model" => "Focus",
                 "year" => 2017,
                 "miles" => 80_000,
                 "price_cents" => 900_000,
                 "price_type" => "auction",
                 "source_url" => url!("focus-bad")
               })

      assert %{price_type: _} = errors_on(changeset)
    end
  end

  describe "import_market_price_from_url/3" do
    test "returns already_exists when source_url is stored" do
      user = pricing_user!()
      source_url = url!("existing")

      {:ok, existing} =
        Pricing.create_market_price(user, %{
          "make" => "Toyota",
          "model" => "Camry",
          "year" => 2019,
          "miles" => 40_000,
          "price_cents" => 1_900_000,
          "price_type" => "listing",
          "source_url" => source_url
        })

      assert {:ok, :already_exists, ^existing} =
               Pricing.import_market_price_from_url(user, source_url,
                 extract: fn _ -> flunk("should not extract") end
               )
    end

    test "creates when agent extraction is complete" do
      user = pricing_user!()
      source_url = url!("extract-complete")

      assert {:ok, :created, record} =
               Pricing.import_market_price_from_url(user, source_url,
                 extract: fn _url ->
                   {:ok,
                    %{
                      "make" => "Subaru",
                      "model" => "Outback",
                      "year" => 2021,
                      "miles" => 25_000,
                      "price_cents" => 2_800_000,
                      "price_type" => "listing",
                      "currency" => "USD"
                    }}
                 end
               )

      assert record.source_url == source_url
      assert record.make == "Subaru"
      assert record.price_cents == 2_800_000
    end

    test "needs_form when extraction is incomplete" do
      user = pricing_user!()
      source_url = url!("extract-partial")

      assert {:needs_form, attrs} =
               Pricing.import_market_price_from_url(user, source_url,
                 extract: fn _url ->
                   {:ok, %{"make" => "Ford", "model" => "Escape", "price_type" => "listing"}}
                 end
               )

      assert attrs["source_url"] == source_url
      assert attrs["make"] == "Ford"
      refute Map.has_key?(attrs, "year")
      refute Map.has_key?(attrs, "miles")
      refute Map.has_key?(attrs, "price_cents")
    end

    test "needs_form with source_url when extraction fails" do
      user = pricing_user!()
      source_url = url!("extract-fail")

      assert {:needs_form, attrs} =
               Pricing.import_market_price_from_url(user, source_url,
                 extract: fn _url -> {:error, :boom} end
               )

      assert attrs["source_url"] == source_url
    end
  end

  describe "list_market_prices/1 and get_market_price_details/1" do
    test "filters by make model and price_type" do
      user = pricing_user!()

      {:ok, listing} =
        Pricing.create_market_price(user, %{
          "make" => "Toyota",
          "model" => "Camry",
          "year" => 2019,
          "miles" => 40_000,
          "price_cents" => 1_900_000,
          "price_type" => "listing",
          "source_url" => url!("list-1")
        })

      {:ok, _sale} =
        Pricing.create_market_price(user, %{
          "make" => "Toyota",
          "model" => "Camry",
          "year" => 2019,
          "miles" => 42_000,
          "price_cents" => 1_750_000,
          "price_type" => "sale",
          "source_url" => url!("sale-1")
        })

      {:ok, _other} =
        Pricing.create_market_price(user, %{
          "make" => "Toyota",
          "model" => "Corolla",
          "year" => 2019,
          "miles" => 40_000,
          "price_cents" => 1_500_000,
          "price_type" => "listing",
          "source_url" => url!("list-2")
        })

      market_prices =
        Pricing.list_market_prices(%{
          make: "Toyota",
          model: "Camry",
          price_type: "listing"
        })

      assert length(market_prices) == 1
      assert hd(market_prices).id == listing.id

      details = Pricing.get_market_price_details([listing.id])
      assert length(details) == 1
      assert hd(details).price_cents == 1_900_000
      assert hd(details).price_type == "listing"
    end
  end

  describe "lookup_vehicle_from_vin/2" do
    test "returns ready when market price has full vehicle attrs" do
      user = pricing_user!()

      vin =
        "4T1B11HK5KU" <>
          (System.unique_integer([:positive])
           |> Integer.to_string()
           |> String.pad_leading(6, "0")
           |> String.slice(-6, 6))

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Toyota",
          "model" => "Camry",
          "year" => 2019,
          "miles" => 45_000,
          "price_cents" => 1_800_000,
          "price_type" => "listing",
          "vin" => vin,
          "source_url" => url!("vin-lookup-ready")
        })

      assert {:ok, :ready, attrs} = Pricing.lookup_vehicle_from_vin(vin)
      assert attrs["make"] == "Toyota"
      assert attrs["model"] == "Camry"
      assert attrs["year"] == 2019
      assert attrs["miles"] == 45_000
      assert attrs["vin"] == vin
    end

    test "returns needs_form when checker fails" do
      previous = Application.get_env(:mechanics, Mechanics.Pricing.VinChecker)

      Application.put_env(:mechanics, Mechanics.Pricing.VinChecker,
        checker: fn _vin, _opts -> {:error, :nope} end
      )

      on_exit(fn ->
        if previous do
          Application.put_env(:mechanics, Mechanics.Pricing.VinChecker, previous)
        else
          Application.delete_env(:mechanics, Mechanics.Pricing.VinChecker)
        end
      end)

      assert {:needs_form, %{"vin" => "1HGCM82633A004352"}} =
               Pricing.lookup_vehicle_from_vin("1HGCM82633A004352")
    end

    test "merges miles into NHTSA-style partial decode for ready" do
      assert {:ok, :ready, attrs} =
               Pricing.lookup_vehicle_from_vin("1HGCM82633A004352",
                 miles: "42000",
                 checker: fn vin, _opts ->
                   {:ok,
                    %{
                      "vin" => vin,
                      "make" => "Honda",
                      "model" => "Accord",
                      "year" => 2003
                    }}
                 end
               )

      assert attrs["miles"] == 42_000
      assert attrs["make"] == "Honda"
    end

    test "rejects invalid vin" do
      assert {:error, :invalid_vin} = Pricing.lookup_vehicle_from_vin("nope")
    end
  end

  describe "suggest_prices/2" do
    test "persists a query and returns competitive and expected minimum when market prices exist" do
      user = pricing_user!()

      Enum.each(
        [
          {"listing", 2_000_000},
          {"listing", 1_900_000},
          {"sale", 1_700_000},
          {"sale", 1_650_000}
        ],
        fn {type, cents} ->
          {:ok, _} =
            Pricing.create_market_price(user, %{
              "make" => "Toyota",
              "model" => "Camry",
              "year" => 2019,
              "miles" => 45_000,
              "price_cents" => cents,
              "price_type" => type,
              "source_url" => url!("suggest-#{type}-#{cents}")
            })
        end
      )

      assert {:ok, query} =
               Pricing.suggest_prices(user, %{
                 "make" => "Toyota",
                 "model" => "Camry",
                 "year" => 2019,
                 "miles" => 45_000,
                 "vin" => "4T1B11HK5KU123456"
               })

      assert query.user_id == user.id
      assert query.make == "Toyota"
      assert query.model == "Camry"
      assert query.year == 2019
      assert query.miles == 45_000
      assert is_integer(query.suggested_competitive_cents)
      assert is_integer(query.suggested_minimum_cents)
      assert query.suggested_minimum_cents <= query.suggested_competitive_cents
      assert query.match_count >= 1
    end

    test "persists a query with nil suggestions when no market prices match" do
      user = pricing_user!()

      assert {:ok, query} =
               Pricing.suggest_prices(user, %{
                 "make" => "RareMake",
                 "model" => "RareModel",
                 "year" => 1999,
                 "miles" => 10_000
               })

      assert is_nil(query.suggested_competitive_cents)
      assert is_nil(query.suggested_minimum_cents)
      assert query.match_count == 0
    end
  end
end
