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
    test "shows the market price form for pricing_user", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)

      conn = get(conn, "/pricing/market-prices/new")
      html = html_response(conn, 200)

      assert html =~ ~r/listing/i
      assert html =~ ~r/sale/i

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "form[action='/pricing/market-prices'][method='post']") != []
      assert Floki.find(parsed, "input[name='market_price[make]']") != []
      assert Floki.find(parsed, "input[name='market_price[model]']") != []
      assert Floki.find(parsed, "input[name='market_price[year]']") != []
      assert Floki.find(parsed, "input[name='market_price[miles]']") != []
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

  describe "POST /pricing/market-prices" do
    test "creates a listing market price and redirects", %{conn: conn} do
      {:ok, conn: conn, user: user} = create_pricing_user(conn)

      conn =
        post(conn, "/pricing/market-prices", %{
          "market_price" => %{
            "make" => "Toyota",
            "model" => "Camry",
            "year" => "2019",
            "miles" => "45000",
            "price" => "18500.00",
            "currency" => "USD",
            "price_type" => "listing"
          }
        })

      assert redirected_to(conn) =~ "/pricing"

      market_prices =
        Pricing.list_market_prices(%{make: "Toyota", model: "Camry", user_id: user.id})

      assert length(market_prices) >= 1
      assert hd(market_prices).price_type == "listing"
      assert hd(market_prices).price_cents == 1_850_000
    end
  end

  describe "GET /pricing" do
    test "shows the suggest form for pricing_user", %{conn: conn} do
      {:ok, conn: conn, user: _user} = create_pricing_user(conn)

      conn = get(conn, "/pricing")
      html = html_response(conn, 200)

      parsed = Floki.parse_document!(html)
      assert Floki.find(parsed, "form[action='/pricing/suggest'][method='post']") != []
      assert Floki.find(parsed, "input[name='vehicle[make]']") != []
      assert Floki.find(parsed, "input[name='vehicle[model]']") != []
      assert Floki.find(parsed, "input[name='vehicle[year]']") != []
      assert Floki.find(parsed, "input[name='vehicle[miles]']") != []
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
          "price_type" => "sale"
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
  end
end
