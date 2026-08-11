defmodule MechanicsWeb.PricingController do
  use MechanicsWeb, :controller

  alias Mechanics.Pricing
  alias Mechanics.Pricing.VehicleMarketPrice
  alias MechanicsWeb.Helpers.CurrencyFormatter

  def index(conn, _params) do
    case pricing_user(conn) do
      {:ok, _user} ->
        render(conn, :index, query: nil, vehicle: empty_vehicle())

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
            |> put_flash(:info, "That URL is already saved in vehicle market prices.")
            |> redirect(to: ~p"/pricing")

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
              :info,
              "Could not fully extract listing details. Review and complete the form, then save."
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

  def suggest(conn, %{"vehicle" => vehicle_params}) do
    case pricing_user(conn) do
      {:ok, user} ->
        case Pricing.suggest_prices(user, vehicle_params) do
          {:ok, query} ->
            render(conn, :index, query: query, vehicle: vehicle_params)

          {:error, :invalid_vehicle} ->
            conn
            |> put_flash(:error, "Enter make, model, year, and miles.")
            |> render(:index, query: nil, vehicle: vehicle_params)
        end

      :error ->
        redirect(conn, to: ~p"/")
    end
  end

  defp pricing_user(conn) do
    current_user = conn.assigns[:current_user]

    if current_user && "pricing_user" in (current_user.roles || []) do
      {:ok, current_user}
    else
      :error
    end
  end

  defp empty_vehicle do
    %{"vin" => "", "make" => "", "model" => "", "year" => "", "miles" => ""}
  end

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
