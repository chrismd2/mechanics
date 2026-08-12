defmodule MechanicsWeb.PricingController do
  use MechanicsWeb, :controller

  alias Mechanics.Pricing
  alias Mechanics.Pricing.VehicleMarketPrice
  alias MechanicsWeb.Helpers.CurrencyFormatter

  def index(conn, params) do
    case pricing_user(conn) do
      {:ok, user} ->
        step = if params["manual"] in ["1", "true"], do: :manual, else: :vin

        render_suggest(conn, user,
          step: step,
          query: nil,
          vehicle: empty_vehicle()
        )

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def queries(conn, params) do
    case pricing_user(conn) do
      {:ok, user} ->
        filters = query_filter_params(params)
        queries = Pricing.list_queries(user, filters: filters)

        conn
        |> assign(:wide_layout, true)
        |> render(:queries, queries: queries, filters: filters)

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def delete_query(conn, %{"id" => id} = params) do
    case pricing_user(conn) do
      {:ok, user} ->
        case Pricing.delete_query(user, id) do
          {:ok, _query} ->
            conn
            |> put_flash(:info, "Search dismissed.")
            |> redirect(to: pricing_return_to(params["return_to"]))

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "That search was not found.")
            |> redirect(to: pricing_return_to(params["return_to"]))
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def dismiss_similar(conn, %{"id" => query_id, "market_price_id" => market_price_id}) do
    case pricing_user(conn) do
      {:ok, user} ->
        case Pricing.dismiss_similar_market_price(user, query_id, market_price_id) do
          {:ok, query} ->
            render_suggest(conn, user,
              step: :manual,
              query: query,
              vehicle: vehicle_from_query(query)
            )

          {:error, :not_found} ->
            conn
            |> put_flash(:error, "That search was not found.")
            |> redirect(to: ~p"/pricing")
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def new_market_price(conn, _params) do
    case pricing_user(conn) do
      {:ok, _user} ->
        render(conn, :new_market_price,
          step: :url,
          source_url: "",
          changeset: Pricing.change_market_price(%VehicleMarketPrice{currency: "USD", price_type: "listing"})
        )

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def import_market_price_from_url(conn, %{"market_price" => %{"source_url" => url}}) do
    case pricing_user(conn) do
      {:ok, user} ->
        case Pricing.import_market_price_from_url(user, url) do
          {:ok, :already_exists, _existing} ->
            conn
            |> put_flash(
              :error,
              "That URL is already saved in vehicle market prices. Use a different listing URL, or cancel."
            )
            |> render(:new_market_price,
              step: :url,
              source_url: url,
              changeset: Pricing.change_market_price(%VehicleMarketPrice{})
            )

          {:ok, :created, _record} ->
            conn
            |> put_flash(:info, "Vehicle market price imported from URL.")
            |> redirect(to: ~p"/pricing")

          {:needs_form, attrs} ->
            changeset =
              %VehicleMarketPrice{}
              |> Pricing.change_market_price(attrs)
              |> Map.put(:action, nil)

            conn
            |> put_flash(
              :warning,
              "Could not extract all listing details from that URL. Review and complete the form, then save."
            )
            |> render(:new_market_price,
              step: :manual,
              source_url: Map.get(attrs, "source_url", ""),
              changeset: changeset
            )

          {:error, :invalid_url} ->
            conn
            |> put_flash(:error, "Enter a valid http(s) URL.")
            |> render(:new_market_price,
              step: :url,
              source_url: url,
              changeset: Pricing.change_market_price(%VehicleMarketPrice{})
            )
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def create_market_price(conn, %{"market_price" => params}) do
    case pricing_user(conn) do
      {:ok, user} ->
        {money_attrs, money_error} = normalize_money(params)
        attrs = Map.drop(money_attrs, ["price"])

        source_url =
          attrs
          |> Map.get("source_url", "")
          |> Pricing.normalize_source_url()

        attrs = Map.put(attrs, "source_url", source_url)

        cond do
          money_error ->
            changeset =
              %VehicleMarketPrice{}
              |> Pricing.change_market_price(attrs)
              |> Ecto.Changeset.add_error(:price_cents, money_error)
              |> Map.put(:action, :insert)

            render(conn, :new_market_price,
              step: :manual,
              source_url: source_url,
              changeset: changeset
            )

          true ->
            case Pricing.create_market_price(user, attrs) do
              {:ok, _market_price} ->
                conn
                |> put_flash(:info, "Vehicle market price saved.")
                |> redirect(to: ~p"/pricing")

              {:error, %Ecto.Changeset{} = changeset} ->
                conn =
                  if source_url_taken?(changeset) do
                    put_flash(
                      conn,
                      :error,
                      "That URL is already saved in vehicle market prices. Use a different listing URL, or cancel."
                    )
                  else
                    conn
                  end

                render(conn, :new_market_price,
                  step: :manual,
                  source_url: source_url,
                  changeset: changeset
                )
            end
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  defp source_url_taken?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:source_url, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  def lookup_from_vin(conn, %{"vehicle" => %{"vin" => vin}} = params) do
    case pricing_user(conn) do
      {:ok, user} ->
        miles = get_in(params, ["vehicle", "miles"])
        zipcode = get_in(params, ["vehicle", "zipcode"])

        case Pricing.lookup_vehicle_from_vin(vin, miles: miles, zipcode: zipcode) do
          {:ok, :ready, attrs} ->
            case Pricing.suggest_prices(user, attrs) do
              {:ok, query} ->
                render_suggest(conn, user,
                  step: :manual,
                  query: query,
                  vehicle: stringify_vehicle(attrs)
                )

              {:error, :invalid_vehicle} ->
                conn
                |> put_flash(:error, "Enter make and model (year and miles are optional).")
                |> render_suggest(user,
                  step: :manual,
                  query: nil,
                  vehicle: stringify_vehicle(attrs)
                )
            end

          {:needs_form, attrs} ->
            conn
            |> put_flash(
              :warning,
              "Could not look up that VIN. Confirm the vehicle details, then suggest prices."
            )
            |> render_suggest(user,
              step: :manual,
              query: nil,
              vehicle: stringify_vehicle(attrs)
            )

          {:error, :invalid_vin} ->
            conn
            |> put_flash(:error, "Enter a valid 17-character VIN.")
            |> render_suggest(user,
              step: :vin,
              query: nil,
              vehicle: %{
                "vin" => vin || "",
                "miles" => miles || "0",
                "zipcode" => zipcode || "00000"
              }
            )
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  def suggest(conn, %{"vehicle" => vehicle_params}) do
    case pricing_user(conn) do
      {:ok, user} ->
        case Pricing.suggest_prices(user, vehicle_params) do
          {:ok, query} ->
            render_suggest(conn, user,
              step: :manual,
              query: query,
              vehicle: vehicle_params
            )

          {:error, :invalid_vehicle} ->
            conn
            |> put_flash(:error, "Enter make and model (year and miles are optional).")
            |> render_suggest(user,
              step: :manual,
              query: nil,
              vehicle: vehicle_params
            )
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  defp render_suggest(conn, user, assigns) do
    query = Keyword.get(assigns, :query)
    vehicle = Keyword.get(assigns, :vehicle) || empty_vehicle()

    similar_market_prices =
      cond do
        is_nil(query) ->
          []

        # Best guess (no year): always list matching comps with years.
        query.year in [nil, 0] ->
          Pricing.list_similar_market_prices(
            %{
              "make" => query.make,
              "model" => query.model,
              "year" => query.year,
              "miles" => query.miles,
              "vin" => query.vin,
              "zipcode" => query.zipcode
            },
            limit: 3,
            exclude_ids: query.dismissed_similar_ids || []
          )

        # Year specified but no prices: only show year-nearby comps (do not drop year).
        is_nil(query.suggested_competitive_cents) and is_nil(query.suggested_minimum_cents) ->
          Pricing.list_similar_market_prices(
            %{
              "make" => query.make,
              "model" => query.model,
              "year" => query.year,
              "miles" => query.miles,
              "vin" => query.vin,
              "zipcode" => query.zipcode
            },
            limit: 3,
            exclude_ids: query.dismissed_similar_ids || [],
            require_year: true
          )

        true ->
          []
      end

    conn
    |> assign(:wide_layout, true)
    |> render(
      :index,
      Keyword.merge(
        [
          recent_queries: Pricing.list_queries(user, limit: 3),
          similar_market_prices: similar_market_prices,
          vehicle: vehicle
        ],
        assigns
      )
    )
  end

  defp vehicle_from_query(query) do
    %{
      "vin" => query.vin || "",
      "make" => query.make || "",
      "model" => query.model || "",
      "year" => if(query.year in [nil, 0], do: "", else: stringify_num(query.year)),
      "miles" => stringify_num(query.miles),
      "zipcode" => query.zipcode || "00000"
    }
  end

  defp query_filter_params(params) when is_map(params) do
    %{
      "q" => Map.get(params, "q", ""),
      "make" => Map.get(params, "make", ""),
      "model" => Map.get(params, "model", ""),
      "year" => Map.get(params, "year", ""),
      "vin" => Map.get(params, "vin", "")
    }
  end

  defp pricing_return_to(path) when path in ["/pricing", "/pricing/queries"], do: path
  defp pricing_return_to(_), do: ~p"/pricing/queries"

  defp pricing_user(conn) do
    current_user = conn.assigns[:current_user]

    if current_user && "pricing_user" in (current_user.roles || []) do
      {:ok, current_user}
    else
      :error
    end
  end

  defp empty_vehicle do
    %{"vin" => "", "make" => "", "model" => "", "year" => "", "miles" => "0", "zipcode" => "00000"}
  end

  defp stringify_vehicle(attrs) when is_map(attrs) do
    empty_vehicle()
    |> Map.merge(%{
      "vin" => to_string(Map.get(attrs, "vin") || ""),
      "make" => to_string(Map.get(attrs, "make") || ""),
      "model" => to_string(Map.get(attrs, "model") || ""),
      "year" => stringify_num(Map.get(attrs, "year")),
      "miles" => stringify_num(Map.get(attrs, "miles")),
      "zipcode" => to_string(Map.get(attrs, "zipcode") || "00000")
    })
  end

  defp stringify_num(nil), do: ""
  defp stringify_num(value), do: to_string(value)

  defp normalize_money(attrs) do
    currency =
      attrs
      |> Map.get("currency", "USD")
      |> to_string()
      |> String.upcase()

    attrs =
      attrs
      |> Map.put("currency", currency)
      |> coerce_form_int("year")
      |> coerce_form_int("miles")

    price = Map.get(attrs, "price", "")
    valid_currency? = currency in CurrencyFormatter.valid_currency_codes()

    cond do
      not valid_currency? ->
        {Map.delete(attrs, "price_cents"), "Choose a valid currency."}

      true ->
        case CurrencyFormatter.parse_major_to_minor(to_string(price), currency) do
          {:ok, price_cents} ->
            {Map.put(attrs, "price_cents", price_cents), nil}

          {:error, :invalid_amount} ->
            {Map.delete(attrs, "price_cents"), "Enter a valid amount for the selected currency."}
        end
    end
  end

  defp coerce_form_int(attrs, key) do
    case Map.fetch(attrs, key) do
      {:ok, value} when value not in [nil, ""] ->
        case Mechanics.NumberParse.to_integer(value) do
          {:ok, int} -> Map.put(attrs, key, int)
          :error -> attrs
        end

      _ ->
        attrs
    end
  end
end
