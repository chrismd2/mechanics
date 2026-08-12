defmodule MechanicsWeb.PricingControllerTest do
  use MechanicsWeb.ConnCase

  alias Mechanics.Accounts
  alias Mechanics.Pricing
  alias Mechanics.Repo

  defp create_pricing_user(conn) do
    suffix = System.unique_integer([:positive])
    email = "pricing-ctrl-#{suffix}@example.com"

    {:ok, user} =
      Accounts.create_user(%{
        "email" => email,
        "name" => "Pricing Controller User",
        "roles" => ["customer", "pricing_user"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user =
      user
      |> Ecto.Changeset.change(email_verified: true)
      |> Repo.update!()

    conn = init_test_session(conn, %{current_user_id: user.id})
    {:ok, conn: conn, user: user}
  end

  describe "GET /pricing/market-prices/new" do
    test "shows the URL-first form for pricing_user", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)

      conn = get(conn, "/pricing/market-prices/new")
      html = html_response(conn, 200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "form#market_price_url_form[action='/pricing/market-prices/from-url']") != []
      assert Floki.find(parsed, "input#market_price_source_url[name='market_price[source_url]']") != []
      assert Floki.find(parsed, "form#market_price_manual_form") == []
    end

    test "redirects home when user lacks pricing_user role", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          "email" => "customer-only-#{System.unique_integer([:positive])}@example.com",
          "name" => "Customer Only",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      user =
        user
        |> Ecto.Changeset.change(email_verified: true)
        |> Repo.update!()

      conn = init_test_session(conn, %{current_user_id: user.id})
      conn = get(conn, "/pricing/market-prices/new")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /pricing/market-prices/from-url" do
    setup do
      previous = Application.get_env(:mechanics, Mechanics.Pricing)

      on_exit(fn ->
        if previous do
          Application.put_env(:mechanics, Mechanics.Pricing, previous)
        else
          Application.delete_env(:mechanics, Mechanics.Pricing)
        end
      end)

      :ok
    end

    test "falls back to manual form when extraction cannot complete", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)
      source_url = "https://example.com/needs-form-#{System.unique_integer([:positive])}"

      # Without PRICING_LLM_API_KEY / fetchable page, import falls back to needs_form.
      conn =
        post(conn, "/pricing/market-prices/from-url", %{
          "market_price" => %{"source_url" => source_url}
        })

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Floki.find(parsed, "form#market_price_manual_form") != []
      assert html =~ source_url
      assert Floki.find(parsed, "input[name='market_price[make]']") != []
      assert Floki.find(parsed, "input#market_price_zipcode[name='market_price[zipcode]']") != []
      assert Phoenix.Flash.get(conn.assigns.flash, :warning) =~ "extract"
    end

    test "stays on URL form when URL already exists", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)
      source_url = "https://example.com/already-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Honda",
          "model" => "Civic",
          "year" => 2018,
          "miles" => 50_000,
          "price_cents" => 1_200_000,
          "price_type" => "listing",
          "source_url" => source_url
        })

      conn =
        post(conn, "/pricing/market-prices/from-url", %{
          "market_price" => %{"source_url" => source_url}
        })

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Floki.find(parsed, "form#market_price_url_form") != []
      assert Floki.find(parsed, "form#market_price_manual_form") == []
      assert html =~ source_url
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already"
    end

    test "imports a complete listing and suggests prices for that vehicle", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)
      source_url = "https://example.com/extract-complete-#{System.unique_integer([:positive])}"

      Application.put_env(:mechanics, Mechanics.Pricing,
        extract: fn _url ->
          {:ok,
           %{
             "make" => "Subaru",
             "model" => "Outback",
             "year" => 2021,
             "miles" => 25_000,
             "zipcode" => "55401",
             "price_cents" => 2_800_000,
             "price_type" => "listing",
             "currency" => "USD"
           }}
        end
      )

      conn =
        post(conn, "/pricing/market-prices/from-url", %{
          "market_price" => %{"source_url" => source_url}
        })

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "imported"
      assert html =~ ~r/competitive|minimum/i
      assert html =~ "Subaru"
      assert html =~ "Outback"
      assert Floki.find(parsed, "form#vehicle_manual_form") != []
      assert Floki.find(parsed, "input#vehicle_make[value='Subaru']") != []
      assert Floki.find(parsed, "input#vehicle_model[value='Outback']") != []
      assert Floki.find(parsed, "input#vehicle_year[value='2021']") != []
      assert Floki.find(parsed, "input#vehicle_miles[value='25000']") != []
      assert Floki.find(parsed, "input#vehicle_zipcode[value='55401']") != []

      queries = Pricing.list_queries(user)
      assert length(queries) == 1
      assert hd(queries).make == "Subaru"
      assert hd(queries).model == "Outback"
      assert hd(queries).year == 2021
      assert hd(queries).miles == 25_000
      assert hd(queries).zipcode == "55401"
    end
  end

  describe "POST /pricing/market-prices" do
    test "creates a listing market price and suggests prices for that vehicle", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)
      source_url = "https://example.com/manual-#{System.unique_integer([:positive])}"

      conn =
        post(conn, "/pricing/market-prices", %{
          "market_price" => %{
            "make" => "Toyota",
            "model" => "Camry",
            "year" => "2019",
            "miles" => "45000",
            "price" => "18500.00",
            "currency" => "USD",
            "price_type" => "listing",
            "source_url" => source_url
          }
        })

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "saved"
      assert html =~ ~r/competitive|minimum/i
      assert html =~ "Toyota"
      assert html =~ "Camry"
      assert Floki.find(parsed, "form#vehicle_manual_form") != []
      assert Floki.find(parsed, "input#vehicle_make[value='Toyota']") != []
      assert Floki.find(parsed, "input#vehicle_model[value='Camry']") != []
      assert Floki.find(parsed, "input#vehicle_year[value='2019']") != []
      assert Floki.find(parsed, "input#vehicle_miles[value='45000']") != []

      market_prices =
        Pricing.list_market_prices(%{make: "Toyota", model: "Camry"})

      assert length(market_prices) >= 1
      assert hd(market_prices).price_type == "listing"
      assert hd(market_prices).price_cents == 1_850_000
      assert hd(market_prices).source_url == source_url
      assert hd(market_prices).zipcode == "00000"

      queries = Pricing.list_queries(user)
      assert length(queries) == 1
      assert hd(queries).make == "Toyota"
      assert hd(queries).model == "Camry"
      assert hd(queries).year == 2019
      assert hd(queries).miles == 45_000
    end

    test "saves zipcode from the market price form", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)
      source_url = "https://example.com/zip-#{System.unique_integer([:positive])}"

      conn =
        post(conn, "/pricing/market-prices", %{
          "market_price" => %{
            "make" => "Toyota",
            "model" => "Camry",
            "year" => "2019",
            "miles" => "45000",
            "zipcode" => "55401",
            "price" => "18500.00",
            "currency" => "USD",
            "price_type" => "listing",
            "source_url" => source_url
          }
        })

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert [%{zipcode: "55401"}] = Pricing.list_market_prices(%{make: "Toyota", model: "Camry"})
      assert Floki.find(parsed, "input#vehicle_zipcode[value='55401']") != []
      assert hd(Pricing.list_queries(user)).zipcode == "55401"
    end

    test "flashes when saving a market price whose URL already exists", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)
      source_url = "https://example.com/dup-manual-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Ford",
          "model" => "F-150",
          "year" => 2017,
          "miles" => 80_000,
          "price_cents" => 2_000_000,
          "price_type" => "listing",
          "source_url" => source_url
        })

      conn =
        post(conn, "/pricing/market-prices", %{
          "market_price" => %{
            "make" => "Ford",
            "model" => "F-150",
            "year" => "2017",
            "miles" => "80000",
            "price" => "20000.00",
            "currency" => "USD",
            "price_type" => "listing",
            "source_url" => source_url
          }
        })

      assert html_response(conn, 200)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already"
    end
  end

  describe "GET /pricing" do
    test "shows the VIN-first form for pricing_user", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)

      conn = get(conn, "/pricing")
      html = html_response(conn, 200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "form#vehicle_vin_form[action='/pricing/from-vin']") != []
      assert Floki.find(parsed, "input#vehicle_vin[name='vehicle[vin]']") != []
      assert Floki.find(parsed, "form#vehicle_manual_form") == []
      assert Floki.find(parsed, "#recent-searches a[href='/pricing/queries']") != []
    end

    test "shows top three recent searches as re-run buttons", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      for {make, model, year, offset} <- [
            {"Chevy", "Malibu", 2016, -3},
            {"Ford", "Focus", 2017, -2},
            {"Toyota", "Camry", 2019, -1},
            {"Honda", "Accord", 2020, 0}
          ] do
        {:ok, query} =
          Pricing.suggest_prices(user, %{
            "make" => make,
            "model" => model,
            "year" => year,
            "miles" => 40_000
          })

        query
        |> Ecto.Changeset.change(inserted_at: DateTime.add(now, offset, :second))
        |> Repo.update!()
      end

      conn = get(conn, "/pricing")
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      recent = Floki.find(parsed, "#recent-searches form[action='/pricing/suggest']")
      assert length(recent) == 3
      assert html =~ "Honda"
      assert html =~ "Toyota"
      assert html =~ "Ford"
      refute html =~ "Malibu"
    end

    test "shows the manual form when manual=1", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)

      conn = get(conn, "/pricing?manual=1")
      html = html_response(conn, 200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "form#vehicle_manual_form[action='/pricing/suggest']") != []
      assert Floki.find(parsed, "input[name='vehicle[make]']") != []
      assert Floki.find(parsed, "input#vehicle_zipcode[name='vehicle[zipcode]']") != []
    end

    test "redirects home without pricing_user", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          "email" => "mech-#{System.unique_integer([:positive])}@example.com",
          "name" => "Mechanic Only",
          "roles" => ["mechanic"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      user =
        user
        |> Ecto.Changeset.change(email_verified: true)
        |> Repo.update!()

      conn = init_test_session(conn, %{current_user_id: user.id})
      conn = get(conn, "/pricing")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "GET /pricing/queries" do
    test "filters by make", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      {:ok, _} =
        Pricing.suggest_prices(user, %{
          "make" => "Honda",
          "model" => "Accord",
          "year" => 2020,
          "miles" => 30_000
        })

      {:ok, _} =
        Pricing.suggest_prices(user, %{
          "make" => "Toyota",
          "model" => "Camry",
          "year" => 2019,
          "miles" => 45_000
        })

      conn = get(conn, "/pricing/queries", %{"make" => "Honda"})
      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Floki.find(parsed, "details#recent-searches-filter") != []
      assert Floki.find(parsed, "form#recent_searches_filter_form") != []
      assert html =~ "Recent searches"
      assert html =~ "Honda"
      assert html =~ "Accord"
      refute html =~ "Camry"
    end

    test "formats miles and money with grouped digits", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      Enum.each(
        [
          {"listing", 2_600_000},
          {"sale", 2_400_000}
        ],
        fn {type, cents} ->
          {:ok, _} =
            Pricing.create_market_price(user, %{
              "make" => "Kenworth",
              "model" => "T880",
              "year" => 2016,
              "miles" => 41_921,
              "price_cents" => cents,
              "price_type" => type,
              "source_url" =>
                "https://example.com/format-#{type}-#{System.unique_integer([:positive])}"
            })
        end
      )

      {:ok, _} =
        Pricing.suggest_prices(user, %{
          "make" => "Kenworth",
          "model" => "T880",
          "year" => 2016,
          "miles" => 41_921
        })

      conn = get(conn, "/pricing/queries")
      html = html_response(conn, 200)

      assert html =~ "41,921"
      assert html =~ "$"
      assert html =~ "24,000.00" or html =~ "26,000.00"
    end

    test "dismisses a search and redirects back", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      {:ok, query} =
        Pricing.suggest_prices(user, %{
          "make" => "Honda",
          "model" => "Accord",
          "year" => 2020,
          "miles" => 30_000
        })

      conn =
        delete(conn, "/pricing/queries/#{query.id}", %{"return_to" => "/pricing/queries"})

      assert redirected_to(conn) == "/pricing/queries"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "dismissed"
      assert Pricing.list_queries(user) == []
    end

    test "redirects home without pricing_user", %{conn: conn} do
      {:ok, user} =
        Accounts.create_user(%{
          "email" => "no-pricing-#{System.unique_integer([:positive])}@example.com",
          "name" => "Customer Only",
          "roles" => ["customer"],
          "password" => "securepw123",
          "password_confirmation" => "securepw123"
        })

      user =
        user
        |> Ecto.Changeset.change(email_verified: true)
        |> Repo.update!()

      conn = init_test_session(conn, %{current_user_id: user.id})
      conn = get(conn, "/pricing/queries")
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "POST /pricing/from-vin" do
    setup do
      previous = Application.get_env(:mechanics, Mechanics.Pricing.VinChecker)

      on_exit(fn ->
        if previous do
          Application.put_env(:mechanics, Mechanics.Pricing.VinChecker, previous)
        else
          Application.delete_env(:mechanics, Mechanics.Pricing.VinChecker)
        end
      end)

      :ok
    end

    test "falls back to manual form when VIN check cannot complete", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)

      Application.put_env(:mechanics, Mechanics.Pricing.VinChecker,
        checker: fn _vin, _opts -> {:error, :decode_failed} end
      )

      vin = "1HGCM82633A123456"

      conn =
        post(conn, "/pricing/from-vin", %{
          "vehicle" => %{"vin" => vin, "miles" => "40000"}
        })

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Floki.find(parsed, "form#vehicle_manual_form") != []
      assert html =~ vin
      assert Phoenix.Flash.get(conn.assigns.flash, :warning) =~ "VIN"
    end

    test "rejects invalid VIN and stays on VIN step", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)

      conn =
        post(conn, "/pricing/from-vin", %{
          "vehicle" => %{"vin" => "SHORT", "miles" => ""}
        })

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Floki.find(parsed, "form#vehicle_vin_form") != []
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "VIN"
    end

    test "auto-suggests when VIN resolves fully from market prices", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)
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
          "price_cents" => 1_850_000,
          "price_type" => "listing",
          "vin" => vin,
          "source_url" => "https://example.com/vin-ready-#{System.unique_integer([:positive])}"
        })

      conn =
        post(conn, "/pricing/from-vin", %{
          "vehicle" => %{"vin" => vin, "miles" => ""}
        })

      html = html_response(conn, 200)
      assert html =~ ~r/competitive|minimum/i
      assert html =~ "Toyota"
    end
  end

  describe "POST /pricing/suggest" do
    test "persists a suggestion query for pricing_user", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Honda",
          "model" => "Accord",
          "year" => 2020,
          "miles" => 30_000,
          "price_cents" => 2_200_000,
          "price_type" => "sale",
          "source_url" => "https://example.com/accord-#{System.unique_integer([:positive])}"
        })

      conn =
        post(conn, "/pricing/suggest", %{
          "vehicle" => %{
            "make" => "Honda",
            "model" => "Accord",
            "year" => "2020",
            "miles" => "30000",
            "vin" => ""
          }
        })

      html = html_response(conn, 200)
      assert html =~ ~r/competitive|minimum/i

      queries = Pricing.list_queries(user)
      assert length(queries) >= 1
      assert hd(queries).make == "Honda"
    end

    test "accepts make and model only without year or miles", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Ford",
          "model" => "F750",
          "year" => 2015,
          "miles" => 179_473,
          "price_cents" => 6_300_000,
          "price_type" => "sale",
          "source_url" => "https://example.com/f750-only-#{System.unique_integer([:positive])}"
        })

      conn =
        post(conn, "/pricing/suggest", %{
          "vehicle" => %{
            "make" => "ford",
            "model" => "f750",
            "year" => "",
            "miles" => "",
            "vin" => "",
            "zipcode" => ""
          }
        })

      html = html_response(conn, 200)
      refute html =~ "Enter make and model"
      assert html =~ "Best guess"
      assert html =~ "$63,000"
      assert length(Pricing.list_queries(user)) == 1
      assert hd(Pricing.list_queries(user)).year == 0
    end

    test "best guess without year lists matching comps with their years", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      for {year, miles, cents, label} <- [
            {2000, 104_410, 450_000, "2000"},
            {2008, 149_092, 425_000, "2008"}
          ] do
        {:ok, _} =
          Pricing.create_market_price(user, %{
            "make" => "Ford",
            "model" => "F450",
            "year" => year,
            "miles" => miles,
            "price_cents" => cents,
            "price_type" => "sale",
            "source_url" => "https://example.com/f450-#{label}-#{System.unique_integer([:positive])}"
          })
      end

      conn =
        post(conn, "/pricing/suggest", %{
          "vehicle" => %{
            "make" => "ford",
            "model" => "f450",
            "year" => "",
            "miles" => "",
            "zipcode" => "00000"
          }
        })

      html = html_response(conn, 200)
      assert html =~ "Best guess"
      assert html =~ "Matching market prices (by year)"
      assert html =~ "2000 Ford F450"
      assert html =~ "2008 Ford F450"
      assert html =~ "$4,500.00"
      assert html =~ "$4,250.00"
    end

    test "re-running a recent search updates the existing query", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      {:ok, original} =
        Pricing.suggest_prices(user, %{
          "make" => "Honda",
          "model" => "Accord",
          "year" => 2020,
          "miles" => 30_000
        })

      assert length(Pricing.list_queries(user)) == 1

      conn =
        post(conn, "/pricing/suggest", %{
          "vehicle" => %{
            "make" => "Honda",
            "model" => "Accord",
            "year" => "2020",
            "miles" => "30000",
            "vin" => ""
          }
        })

      assert html_response(conn, 200) =~ "Honda"
      queries = Pricing.list_queries(user)
      assert length(queries) == 1
      assert hd(queries).id == original.id
    end

    test "shows similar market prices when suggestion prices are nil", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      {:ok, _} =
        Pricing.create_market_price(user, %{
          "make" => "Ford",
          "model" => "F750",
          "year" => 2015,
          "miles" => 179_473,
          "price_cents" => 6_300_000,
          "price_type" => "sale",
          "source_url" => "https://example.com/f750-#{System.unique_integer([:positive])}"
        })

      # Year outside seed ±1 (2016–2018) so comps miss; similar ±2 still includes 2015
      conn =
        post(conn, "/pricing/suggest", %{
          "vehicle" => %{
            "make" => "ford",
            "model" => "f750",
            "year" => "2017",
            "miles" => "10000",
            "vin" => "",
            "zipcode" => "00000"
          }
        })

      html = html_response(conn, 200)
      assert html =~ "I can't suggest a price, but here are some that are similar"
      assert html =~ "F750"
      assert html =~ "$63,000.00"
      assert html =~ "Dismiss"
      assert Floki.find(Floki.parse_document!(html), "#similar-market-prices") != []
    end

    test "dismissing a similar market price refills from the next match", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      rows =
        for n <- 1..4 do
          {:ok, row} =
            Pricing.create_market_price(user, %{
              "make" => "Ford",
              "model" => "F750",
              "year" => 2015,
              "miles" => 100_000 + n,
              "price_cents" => 6_000_000 + n * 10_000,
              "price_type" => "sale",
              "source_url" => "https://example.com/f750-dismiss-#{n}-#{System.unique_integer([:positive])}"
            })

          {:ok, row} =
            row
            |> Ecto.Changeset.change(%{
              inserted_at: DateTime.add(DateTime.utc_now(), n, :second) |> DateTime.truncate(:second)
            })
            |> Mechanics.Repo.update()

          row
        end

      conn =
        post(conn, "/pricing/suggest", %{
          "vehicle" => %{
            "make" => "ford",
            "model" => "f750",
            "year" => "2017",
            "miles" => "10000",
            "zipcode" => "00000"
          }
        })

      html = html_response(conn, 200)
      query = hd(Pricing.list_queries(user))
      first_id = Enum.at(rows, 3).id
      fourth_id = Enum.at(rows, 0).id

      assert html =~ first_id
      refute html =~ fourth_id

      conn =
        post(conn, "/pricing/queries/#{query.id}/similar/#{first_id}/dismiss")

      html = html_response(conn, 200)
      refute html =~ first_id
      assert html =~ fourth_id
      assert html =~ "I can't suggest a price, but here are some that are similar"
    end
  end
end
