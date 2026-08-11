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

  def list_queries(%User{} = user) do
    from(q in VehiclePriceQuery,
      where: q.user_id == ^user.id,
      order_by: [desc: q.inserted_at, desc: q.id]
    )
    |> Repo.all()
  end

  def change_market_price(%VehicleMarketPrice{} = market_price, attrs \\ %{}) do
    VehicleMarketPrice.changeset(market_price, attrs)
  end

  @doc """
  Runs the pricing agent and persists a `vehicle_price_query` snapshot.
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

      %VehiclePriceQuery{}
      |> VehiclePriceQuery.changeset(query_attrs)
      |> Repo.insert()
    end
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
         "year" => parse_int!(Map.get(attrs, "year")),
         "miles" => parse_int!(Map.get(attrs, "miles"))
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

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value) when is_binary(value), do: String.trim(value)
  defp blank_to_nil(value), do: value

  defp parse_int!(value) when is_integer(value), do: value

  defp parse_int!(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> raise ArgumentError, "invalid integer"
    end
  end
end
