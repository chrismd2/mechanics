defmodule Mechanics.Pricing do
  @moduledoc """
  Vehicle market prices and price suggestion queries.
  """

  import Ecto.Query, warn: false

  alias Mechanics.Accounts.User
  alias Mechanics.Pricing.Agent
  alias Mechanics.Pricing.VehicleMarketPrice
  alias Mechanics.Pricing.VehiclePriceQuery
  alias Mechanics.Repo

  def create_market_price(%User{} = user, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.put("user_id", user.id)
      |> maybe_default_currency()
      |> coerce_market_price_numbers()

    %VehicleMarketPrice{}
    |> VehicleMarketPrice.changeset(attrs)
    |> Repo.insert()
  end

  def list_market_prices(filters \\ %{}) when is_map(filters) do
    filters = atomize_filter_keys(filters)

    VehicleMarketPrice
    |> apply_market_price_filters(filters)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> Repo.all()
  end

  def get_market_price_details(ids) when is_list(ids) do
    ids = Enum.map(ids, &to_string/1)

    from(m in VehicleMarketPrice,
      where: m.id in ^ids,
      select: %{
        id: m.id,
        price_cents: m.price_cents,
        currency: m.currency,
        price_type: m.price_type,
        year: m.year,
        miles: m.miles,
        make: m.make,
        model: m.model
      }
    )
    |> Repo.all()
  end

  @doc """
  Lists price suggestion queries for a user, newest first.

  Options:
  - `:limit` — max rows to return
  - `:filters` — map with optional `q`, `make`, `model`, `year`, `vin`
  """
  def list_queries(%User{} = user, opts \\ []) when is_list(opts) do
    filters =
      opts
      |> Keyword.get(:filters, %{})
      |> atomize_filter_keys()
      |> normalize_query_filters()

    limit = Keyword.get(opts, :limit)

    query =
      from(q in VehiclePriceQuery,
        where: q.user_id == ^user.id,
        order_by: [desc: q.inserted_at, desc: q.id]
      )
      |> apply_query_filters(filters)

    query =
      if is_integer(limit) and limit > 0 do
        limit(query, ^limit)
      else
        query
      end

    Repo.all(query)
  end

  def change_market_price(%VehicleMarketPrice{} = market_price, attrs \\ %{}) do
    VehicleMarketPrice.changeset(market_price, attrs)
  end

  def normalize_source_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.replace_trailing("/", "")
  end

  def normalize_source_url(_), do: ""

  def get_market_price_by_source_url(url) when is_binary(url) do
    normalized = normalize_source_url(url)

    if normalized == "" do
      nil
    else
      Repo.get_by(VehicleMarketPrice, source_url: normalized)
    end
  end

  @doc """
  Import a market price from a listing/sale URL.

  1. If `source_url` already exists, returns `{:ok, :already_exists, record}`.
  2. Otherwise asks the agent to extract fields from the page.
  3. If extraction is complete, saves and returns `{:ok, :created, record}`.
  4. If extraction is incomplete, returns `{:needs_form, attrs}` with `source_url` set.
  """
  def import_market_price_from_url(%User{} = user, url, opts \\ []) when is_binary(url) do
    source_url = normalize_source_url(url)

    cond do
      source_url == "" or not String.match?(source_url, ~r/\Ahttps?:\/\//i) ->
        {:error, :invalid_url}

      true ->
        case get_market_price_by_source_url(source_url) do
          %VehicleMarketPrice{} = existing ->
            {:ok, :already_exists, existing}

          nil ->
            extract = Keyword.get(opts, :extract, &Agent.extract_listing_from_url/1)

            case extract.(source_url) do
              {:ok, attrs} ->
                attrs =
                  attrs
                  |> stringify_keys()
                  |> Map.put("source_url", source_url)
                  |> maybe_default_currency()

                if complete_market_price_attrs?(attrs) do
                  case create_market_price(user, attrs) do
                    {:ok, record} -> {:ok, :created, record}
                    {:error, changeset} -> {:needs_form, attrs_from_changeset_error(attrs, changeset)}
                  end
                else
                  {:needs_form, attrs}
                end

              {:error, _reason} ->
                {:needs_form, %{"source_url" => source_url, "currency" => "USD", "price_type" => "listing"}}
            end
        end
    end
  end

  @doc """
  Resolve a vehicle from a VIN via `VinChecker`.

  - `{:ok, :ready, attrs}` when make/model/year/miles are all present (e.g. prior market price)
  - `{:needs_form, attrs}` when the VIN check fails or miles/other fields are still needed
  - `{:error, :invalid_vin}` for malformed VINs
  """
  def lookup_vehicle_from_vin(vin, opts \\ []) do
    alias Mechanics.Pricing.VinChecker

    normalized = VinChecker.normalize(vin)
    miles = Keyword.get(opts, :miles)

    cond do
      normalized == "" ->
        {:error, :invalid_vin}

      not VinChecker.valid_vin?(normalized) ->
        {:error, :invalid_vin}

      true ->
        case VinChecker.check(normalized, opts) do
          {:ok, attrs} ->
            attrs =
              attrs
              |> stringify_keys()
              |> Map.put("vin", normalized)
              |> maybe_merge_miles(miles)
              |> coerce_market_price_numbers()

            if complete_suggest_attrs?(attrs) do
              {:ok, :ready, attrs}
            else
              {:needs_form, attrs}
            end

          {:error, _reason} ->
            attrs =
              %{"vin" => normalized}
              |> maybe_merge_miles(miles)
              |> coerce_market_price_numbers()

            {:needs_form, attrs}
        end
    end
  end

  defp maybe_merge_miles(attrs, miles) when miles in [nil, ""], do: attrs

  defp maybe_merge_miles(attrs, miles) do
    case Mechanics.NumberParse.to_integer(miles) do
      {:ok, int} -> Map.put(attrs, "miles", int)
      :error -> attrs
    end
  end

  defp complete_suggest_attrs?(attrs) do
    required = ["make", "model", "year", "miles"]

    Enum.all?(required, fn key ->
      value = Map.get(attrs, key)
      not is_nil(value) and value != ""
    end)
  end

  defp complete_market_price_attrs?(attrs) do
    required = ["make", "model", "year", "miles", "price_cents", "price_type", "source_url"]

    Enum.all?(required, fn key ->
      value = Map.get(attrs, key)
      not is_nil(value) and value != ""
    end)
  end

  defp attrs_from_changeset_error(attrs, _changeset), do: attrs

  @doc """
  Runs the pricing agent and upserts a `vehicle_price_query` for this user + vehicle.

  Duplicate searches (same make, model, year, miles, and VIN) update the existing row
  instead of inserting another.
  """
  def suggest_prices(%User{} = user, attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, vehicle} <- normalize_vehicle_attrs(attrs) do
      suggestion = Agent.suggest(vehicle)

      query_attrs =
        vehicle
        |> Map.put("user_id", user.id)
        |> Map.put("suggested_competitive_cents", suggestion.competitive_cents)
        |> Map.put("suggested_minimum_cents", suggestion.minimum_cents)
        |> Map.put("match_count", suggestion.match_count)
        |> Map.put("agent_summary", suggestion.summary)
        |> Map.put("currency", Map.get(suggestion, :currency, "USD"))

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      existing = get_query_by_vehicle(user.id, vehicle) || %VehiclePriceQuery{}

      existing
      |> VehiclePriceQuery.changeset(query_attrs)
      |> Ecto.Changeset.put_change(:inserted_at, now)
      |> Ecto.Changeset.put_change(:updated_at, now)
      |> Repo.insert_or_update()
    end
  end

  defp get_query_by_vehicle(user_id, %{"make" => make, "model" => model, "year" => year, "miles" => miles, "vin" => vin}) do
    query =
      from(q in VehiclePriceQuery,
        where: q.user_id == ^user_id,
        where: q.make == ^make,
        where: q.model == ^model,
        where: q.year == ^year,
        where: q.miles == ^miles
      )

    query =
      if is_nil(vin) or vin == "" do
        where(query, [q], is_nil(q.vin) or q.vin == "")
      else
        where(query, [q], q.vin == ^vin)
      end

    Repo.one(query)
  end

  defp normalize_vehicle_attrs(attrs) do
    required = ["make", "model", "year", "miles"]

    missing =
      Enum.filter(required, fn key ->
        value = Map.get(attrs, key)
        is_nil(value) or (is_binary(value) and String.trim(value) == "")
      end)

    if missing != [] do
      {:error, :invalid_vehicle}
    else
      {:ok,
       %{
         "vin" => blank_to_nil(Map.get(attrs, "vin")),
         "make" => attrs |> Map.get("make") |> to_string() |> String.trim(),
         "model" => attrs |> Map.get("model") |> to_string() |> String.trim(),
         "year" => Mechanics.NumberParse.to_integer!(Map.get(attrs, "year")),
         "miles" => Mechanics.NumberParse.to_integer!(Map.get(attrs, "miles"))
       }}
    end
  rescue
    ArgumentError -> {:error, :invalid_vehicle}
  end

  defp apply_market_price_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:make, make}, q when is_binary(make) and make != "" ->
        where(q, [m], ilike(m.make, ^make))

      {:model, model}, q when is_binary(model) and model != "" ->
        where(q, [m], ilike(m.model, ^model))

      {:price_type, type}, q when type in ["listing", "sale"] ->
        where(q, [m], m.price_type == ^type)

      {:user_id, user_id}, q when not is_nil(user_id) ->
        where(q, [m], m.user_id == ^user_id)

      {:year, year}, q when is_integer(year) ->
        where(q, [m], m.year == ^year)

      {:year_min, year}, q when is_integer(year) ->
        where(q, [m], m.year >= ^year)

      {:year_max, year}, q when is_integer(year) ->
        where(q, [m], m.year <= ^year)

      {:miles_min, miles}, q when is_integer(miles) ->
        where(q, [m], m.miles >= ^miles)

      {:miles_max, miles}, q when is_integer(miles) ->
        where(q, [m], m.miles <= ^miles)

      {_other, _}, q ->
        q
    end)
  end

  defp apply_query_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:q, term}, q when is_binary(term) and term != "" ->
        pattern = "%" <> term <> "%"

        where(
          q,
          [row],
          ilike(row.make, ^pattern) or ilike(row.model, ^pattern) or
            ilike(fragment("coalesce(?, '')", row.vin), ^pattern)
        )

      {:make, make}, q when is_binary(make) and make != "" ->
        where(q, [row], ilike(row.make, ^make))

      {:model, model}, q when is_binary(model) and model != "" ->
        where(q, [row], ilike(row.model, ^model))

      {:vin, vin}, q when is_binary(vin) and vin != "" ->
        pattern = "%" <> vin <> "%"
        where(q, [row], ilike(fragment("coalesce(?, '')", row.vin), ^pattern))

      {:year, year}, q when is_integer(year) ->
        where(q, [row], row.year == ^year)

      {_other, _}, q ->
        q
    end)
  end

  defp normalize_query_filters(filters) when is_map(filters) do
    filters
    |> Map.take([:q, :make, :model, :year, :vin])
    |> Map.new(fn
      {:year, year} when is_binary(year) ->
        case Mechanics.NumberParse.to_integer(year) do
          {:ok, int} -> {:year, int}
          :error -> {:year, nil}
        end

      {key, value} when is_binary(value) ->
        {key, String.trim(value)}

      pair ->
        pair
    end)
  end

  defp atomize_filter_keys(filters) do
    Map.new(filters, fn
      {k, v} when is_atom(k) -> {k, v}
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
    end)
  rescue
    ArgumentError ->
      Map.new(filters, fn
        {k, v} when is_atom(k) -> {k, v}
        {"make", v} -> {:make, v}
        {"model", v} -> {:model, v}
        {"price_type", v} -> {:price_type, v}
        {"user_id", v} -> {:user_id, v}
        {"year", v} -> {:year, v}
        {"year_min", v} -> {:year_min, v}
        {"year_max", v} -> {:year_max, v}
        {"miles_min", v} -> {:miles_min, v}
        {"miles_max", v} -> {:miles_max, v}
        {"q", v} -> {:q, v}
        {"vin", v} -> {:vin, v}
        {_, _} -> {:__ignored__, nil}
      end)
      |> Map.delete(:__ignored__)
  end

  defp stringify_keys(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} when is_binary(k) -> {k, v}
    end)
  end

  defp maybe_default_currency(attrs) do
    case Map.get(attrs, "currency") do
      nil -> Map.put(attrs, "currency", "USD")
      "" -> Map.put(attrs, "currency", "USD")
      _ -> attrs
    end
  end

  defp coerce_market_price_numbers(attrs) do
    attrs
    |> coerce_int_field("year")
    |> coerce_int_field("miles")
    |> coerce_int_field("price_cents")
  end

  defp coerce_int_field(attrs, key) do
    case Map.fetch(attrs, key) do
      :error ->
        attrs

      {:ok, nil} ->
        attrs

      {:ok, ""} ->
        attrs

      {:ok, value} ->
        case Mechanics.NumberParse.to_integer(value) do
          {:ok, int} -> Map.put(attrs, key, int)
          :error -> attrs
        end
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.trim(value)
  defp blank_to_nil(value), do: value
end
