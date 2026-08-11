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
    test "falls back to manual form when extraction cannot complete", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)
      source_url = "https://example.com/needs-form-#{System.unique_integer([:positive])}"

      # Without GROQ_API_KEY / fetchable page, import falls back to needs_form.
      conn =
        post(conn, "/pricing/market-prices/from-url", %{
          "market_price" => %{"source_url" => source_url}
        })

      html = html_response(conn, 200)
      parsed = Floki.parse_document!(html)

      assert Floki.find(parsed, "form#market_price_manual_form") != []
      assert html =~ source_url
      assert Floki.find(parsed, "input[name='market_price[make]']") != []
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
  end

  describe "POST /pricing/market-prices" do
    test "creates a listing market price and redirects", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)
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

      assert redirected_to(conn) =~ "/pricing"

      market_prices =
        Pricing.list_market_prices(%{make: "Toyota", model: "Camry"})

      assert length(market_prices) >= 1
      assert hd(market_prices).price_type == "listing"
      assert hd(market_prices).price_cents == 1_850_000
      assert hd(market_prices).source_url == source_url
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

      assert Floki.find(parsed, "form#recent_searches_filter_form") != []
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
  end
end
