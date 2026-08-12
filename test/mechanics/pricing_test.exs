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
    end

    test "defaults blank zipcode to 00000" do
      user = pricing_user!()

      assert {:ok, market_price} =
               Pricing.create_market_price(user, %{
                 "make" => "Toyota",
                 "model" => "Camry",
                 "year" => 2019,
                 "miles" => 45_000,
                 "price_cents" => 1_850_000,
                 "price_type" => "listing",
                 "source_url" => url!("zip-default"),
                 "zipcode" => ""
               })

      assert market_price.zipcode == "00000"
    end

    test "stores an explicit zipcode" do
      user = pricing_user!()

      assert {:ok, market_price} =
               Pricing.create_market_price(user, %{
                 "make" => "Toyota",
                 "model" => "Camry",
                 "year" => 2019,
                 "miles" => 45_000,
                 "price_cents" => 1_850_000,
                 "price_type" => "listing",
                 "source_url" => url!("zip-explicit"),
                 "zipcode" => "55401"
               })

      assert market_price.zipcode == "55401"
    end

    test "does not store a submitting user on market prices" do
      assert :user_id not in Mechanics.Pricing.VehicleMarketPrice.__schema__(:fields)
    end

    test "schema includes zipcode" do
      assert :zipcode in Mechanics.Pricing.VehicleMarketPrice.__schema__(:fields)
      assert :zipcode in Mechanics.Pricing.VehiclePriceQuery.__schema__(:fields)
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
    test "filters by vin case-insensitively" do
      user = pricing_user!()
      vin = "1NKZL70X5GJ124207"

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Kenworth",
          "model" => "T880",
          "year" => 2016,
          "miles" => 41_921,
          "price_cents" => 2_600_000,
          "price_type" => "listing",
          "vin" => vin,
          "source_url" => url!("list-by-vin")
        })

      assert [%{vin: ^vin}] = Pricing.list_market_prices(%{vin: String.downcase(vin)})
      assert [] = Pricing.list_market_prices(%{vin: "ZZZZZZZZZZZZZZZZZ"})
    end

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

    test "defaults blank miles to 0 so make/model/year decode is ready" do
      assert {:ok, :ready, attrs} =
               Pricing.lookup_vehicle_from_vin("1HGCM82633A004352",
                 miles: "",
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

      assert attrs["miles"] == 0
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

    test "treats blank miles as 0" do
      user = pricing_user!()

      assert {:ok, query} =
               Pricing.suggest_prices(user, %{
                 "make" => "Ford",
                 "model" => "F-150",
                 "year" => 2015,
                 "miles" => ""
               })

      assert query.miles == 0
    end

    test "accepts make and model only (blank year and miles)" do
      user = pricing_user!()

      {:ok, f750} =
        Pricing.create_market_price(user, %{
          "make" => "Ford",
          "model" => "F750",
          "year" => 2015,
          "miles" => 179_473,
          "price_cents" => 6_300_000,
          "price_type" => "sale",
          "source_url" => url!("f750-make-model-only")
        })

      assert {:ok, query} =
               Pricing.suggest_prices(user, %{
                 "make" => "ford",
                 "model" => "f750",
                 "year" => "",
                 "miles" => ""
               })

      assert query.year == 0
      assert query.miles == 0
      assert query.match_count >= 1
      assert query.suggested_competitive_cents == f750.price_cents
      assert query.suggested_minimum_cents == f750.price_cents
      assert query.agent_summary =~ "Best guess"
      assert query.agent_summary =~ "year not specified"
    end

    test "defaults blank zipcode to 00000 on suggest" do
      user = pricing_user!()

      assert {:ok, query} =
               Pricing.suggest_prices(user, %{
                 "make" => "Ford",
                 "model" => "F-150",
                 "year" => 2015,
                 "miles" => 10_000,
                 "zipcode" => ""
               })

      assert query.zipcode == "00000"
    end

    test "widens miles band so same make/model/year comps are used" do
      user = pricing_user!()

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Kenworth",
          "model" => "T880",
          "year" => 2016,
          "miles" => 41_921,
          "price_cents" => 2_600_000,
          "price_type" => "listing",
          "source_url" => url!("suggest-widen-miles")
        })

      assert {:ok, query} =
               Pricing.suggest_prices(user, %{
                 "make" => "Kenworth",
                 "model" => "T880",
                 "year" => 2016,
                 "miles" => 9_999,
                 "vin" => "1NKZL70X5GJ124207"
               })

      assert query.match_count >= 1
      assert is_integer(query.suggested_competitive_cents)
      assert is_integer(query.suggested_minimum_cents)
    end

    test "includes market prices that match VIN outside the miles band" do
      user = pricing_user!()
      vin = "1HGCM82633A004999"

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Honda",
          "model" => "Civic",
          "year" => 2018,
          "miles" => 120_000,
          "price_cents" => 900_000,
          "price_type" => "sale",
          "vin" => vin,
          "source_url" => url!("suggest-vin-comp")
        })

      assert {:ok, query} =
               Pricing.suggest_prices(user, %{
                 "make" => "Honda",
                 "model" => "Civic",
                 "year" => 2018,
                 "miles" => 10_000,
                 "vin" => vin
               })

      assert query.match_count >= 1
      assert is_integer(query.suggested_competitive_cents)
    end

    test "updates an existing query instead of creating a duplicate" do
      user = pricing_user!()

      vehicle = %{
        "make" => "Honda",
        "model" => "Accord",
        "year" => 2020,
        "miles" => 30_000,
        "vin" => "1HGCM82633A004352"
      }

      assert {:ok, first} = Pricing.suggest_prices(user, vehicle)
      assert {:ok, second} = Pricing.suggest_prices(user, vehicle)

      assert second.id == first.id
      assert length(Pricing.list_queries(user)) == 1
    end
  end

  describe "list_queries/2" do
    test "returns newest first and respects limit" do
      user = pricing_user!()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for {make, year, offset} <- [{"Alpha", 2018, -2}, {"Beta", 2019, -1}, {"Gamma", 2020, 0}] do
        {:ok, query} =
          Pricing.suggest_prices(user, %{
            "make" => make,
            "model" => "Car",
            "year" => year,
            "miles" => 20_000
          })

        query
        |> Ecto.Changeset.change(inserted_at: DateTime.add(now, offset, :second))
        |> Mechanics.Repo.update!()
      end

      assert [%{make: "Gamma"}, %{make: "Beta"}, %{make: "Alpha"}] = Pricing.list_queries(user)
      assert [%{make: "Gamma"}, %{make: "Beta"}] = Pricing.list_queries(user, limit: 2)
    end

    test "filters by q, make, model, year, and vin" do
      user = pricing_user!()

      {:ok, _} =
        Pricing.suggest_prices(user, %{
          "make" => "Honda",
          "model" => "Accord",
          "year" => 2020,
          "miles" => 30_000,
          "vin" => "1HGCM82633A004352"
        })

      {:ok, _} =
        Pricing.suggest_prices(user, %{
          "make" => "Toyota",
          "model" => "Camry",
          "year" => 2019,
          "miles" => 45_000,
          "vin" => "4T1B11HK5KU123456"
        })

      assert [%{make: "Honda"}] =
               Pricing.list_queries(user, filters: %{"make" => "Honda"})

      assert [%{model: "Camry"}] =
               Pricing.list_queries(user, filters: %{"model" => "Camry"})

      assert [%{year: 2020}] =
               Pricing.list_queries(user, filters: %{"year" => "2020"})

      assert [%{make: "Toyota"}] =
               Pricing.list_queries(user, filters: %{"vin" => "4T1B11HK"})

      assert [%{make: "Honda"}] =
               Pricing.list_queries(user, filters: %{"q" => "Accord"})
    end
  end

  describe "delete_query/2" do
    test "deletes a query owned by the user" do
      user = pricing_user!()

      {:ok, query} =
        Pricing.suggest_prices(user, %{
          "make" => "Honda",
          "model" => "Accord",
          "year" => 2020,
          "miles" => 30_000
        })

      assert {:ok, _} = Pricing.delete_query(user, query.id)
      assert Pricing.list_queries(user) == []
    end

    test "returns not_found for another user's query" do
      owner = pricing_user!()
      other = pricing_user!()

      {:ok, query} =
        Pricing.suggest_prices(owner, %{
          "make" => "Honda",
          "model" => "Accord",
          "year" => 2020,
          "miles" => 30_000
        })

      assert {:error, :not_found} = Pricing.delete_query(other, query.id)
      assert length(Pricing.list_queries(owner)) == 1
    end
  end

  describe "list_similar_market_prices/2" do
    test "finds Ford F750 with lowercase ford/f750 and mismatched miles" do
      user = pricing_user!()

      {:ok, f750} =
        Pricing.create_market_price(user, %{
          "make" => "Ford",
          "model" => "F750",
          "year" => 2015,
          "miles" => 179_473,
          "price_cents" => 6_300_000,
          "price_type" => "sale",
          "vin" => "3FRWF7FC1FV747306",
          "source_url" => url!("f750-sale")
        })

      similar =
        Pricing.list_similar_market_prices(%{
          "make" => "ford",
          "model" => "f750",
          "year" => 2015,
          "miles" => 10_000
        })

      assert Enum.any?(similar, &(&1.id == f750.id))
    end

    test "returns at most 3 and skips exclude_ids so the next rows refill" do
      user = pricing_user!()

      rows =
        for n <- 1..5 do
          {:ok, row} =
            Pricing.create_market_price(user, %{
              "make" => "Ford",
              "model" => "F750",
              "year" => 2015,
              "miles" => 100_000 + n,
              "price_cents" => 5_000_000 + n * 1000,
              "price_type" => "sale",
              "source_url" => url!("f750-#{n}")
            })

          # Ensure deterministic newest-first by bumping inserted_at
          {:ok, row} =
            row
            |> Ecto.Changeset.change(%{
              inserted_at: DateTime.add(DateTime.utc_now(), n, :second) |> DateTime.truncate(:second)
            })
            |> Mechanics.Repo.update()

          row
        end

      # Newest first: n=5,4,3,2,1
      top = Pricing.list_similar_market_prices(%{"make" => "Ford", "model" => "F750", "year" => 2015})
      assert length(top) == 3
      top_ids = Enum.map(top, & &1.id)
      assert hd(top_ids) == Enum.at(rows, 4).id

      exclude = Enum.take(top_ids, 1)

      next =
        Pricing.list_similar_market_prices(
          %{"make" => "Ford", "model" => "F750", "year" => 2015},
          exclude_ids: exclude
        )

      assert length(next) == 3
      refute Enum.at(rows, 4).id in Enum.map(next, & &1.id)
      assert Enum.at(rows, 1).id in Enum.map(next, & &1.id)
    end

    test "widens past year band when needed" do
      user = pricing_user!()

      {:ok, f750} =
        Pricing.create_market_price(user, %{
          "make" => "Ford",
          "model" => "F750",
          "year" => 2015,
          "miles" => 179_473,
          "price_cents" => 6_300_000,
          "price_type" => "sale",
          "source_url" => url!("f750-widen")
        })

      similar =
        Pricing.list_similar_market_prices(%{
          "make" => "ford",
          "model" => "f750",
          "year" => 2020
        })

      assert Enum.any?(similar, &(&1.id == f750.id))
    end
  end

  describe "dismiss_similar_market_price/3" do
    test "appends id and preserves dismissals across suggest re-run" do
      user = pricing_user!()

      {:ok, market} =
        Pricing.create_market_price(user, %{
          "make" => "RareMake",
          "model" => "RareModel",
          "year" => 1999,
          "miles" => 1,
          "price_cents" => 100_000,
          "price_type" => "listing",
          "source_url" => url!("rare-dismiss")
        })

      # Year far from market so agent seeds miss; suggestions nil
      assert {:ok, query} =
               Pricing.suggest_prices(user, %{
                 "make" => "RareMake",
                 "model" => "RareModel",
                 "year" => 2010,
                 "miles" => 50_000
               })

      assert is_nil(query.suggested_competitive_cents)

      assert {:ok, updated} = Pricing.dismiss_similar_market_price(user, query.id, market.id)
      assert market.id in updated.dismissed_similar_ids

      assert {:ok, rerun} =
               Pricing.suggest_prices(user, %{
                 "make" => "RareMake",
                 "model" => "RareModel",
                 "year" => 2010,
                 "miles" => 50_000
               })

      assert rerun.id == query.id
      assert market.id in rerun.dismissed_similar_ids
    end
  end
end
