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

  def create_market_price(%User{} = _user, attrs) when is_map(attrs) do
    attrs =
      attrs
      |> stringify_keys()
      |> Map.delete("user_id")
      |> maybe_default_currency()
      |> maybe_default_zipcode()
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

  @doc """
  Deletes a price suggestion query owned by the user.
  """
  def delete_query(%User{} = user, id) when is_binary(id) do
    case Repo.get_by(VehiclePriceQuery, id: id, user_id: user.id) do
      %VehiclePriceQuery{} = query -> Repo.delete(query)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Downcases and strips non-alphanumeric characters for a single vehicle token.

  Examples: `"F-450"` → `"f450"`, `"f_450"` → `"f450"`.
  """
  def normalize_vehicle_key(nil), do: ""

  def normalize_vehicle_key(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]/u, "")
  end

  def normalize_vehicle_key(value), do: value |> to_string() |> normalize_vehicle_key()

  @doc """
  Splits a make/model string on whitespace and normalizes each token.

  Used so `f450` matches `F450 King Ranch` (query tokens ⊆ stored) and
  `f450 king ranch` matches base `F-450` (stored tokens ⊆ query).
  """
  def normalize_vehicle_tokens(nil), do: []

  def normalize_vehicle_tokens(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.split(~r/\s+/u, trim: true)
    |> Enum.map(&normalize_vehicle_key/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def normalize_vehicle_tokens(value), do: value |> to_string() |> normalize_vehicle_tokens()

  @doc """
  Lists similar vehicle market prices for a suggest vehicle (looser than agent seeds).

  Make/model use alphanumeric **token** matching (see `normalize_vehicle_tokens/1`):
  tokens must match exactly (so `f450` ≠ `f4500`). Trim variants match when either
  side's token set contains the other (`f450` ↔ `F450 King Ranch`).

  Options:
  - `:limit` — max rows (default 3)
  - `:exclude_ids` — market price ids to skip (e.g. dismissed on a query)
  """
  def list_similar_market_prices(vehicle_attrs, opts \\ []) when is_map(vehicle_attrs) and is_list(opts) do
    attrs = stringify_keys(vehicle_attrs)
    make = attrs |> Map.get("make") |> to_string() |> String.trim()
    model = attrs |> Map.get("model") |> to_string() |> String.trim()
    year = parse_year(Map.get(attrs, "year"))

    make_tokens = normalize_vehicle_tokens(make)
    model_tokens = normalize_vehicle_tokens(model)

    limit = Keyword.get(opts, :limit, 3)
    exclude_ids = opts |> Keyword.get(:exclude_ids, []) |> List.wrap() |> Enum.map(&to_string/1)
    require_year? = Keyword.get(opts, :require_year, false)

    if make_tokens == [] or model_tokens == [] do
      []
    else
      base =
        from(m in VehicleMarketPrice,
          where:
            fragment(
              """
              (
                SELECT coalesce(array_agg(tok) FILTER (WHERE tok <> ''), ARRAY[]::text[])
                FROM (
                  SELECT regexp_replace(raw_token, '[^a-z0-9]', '', 'g') AS tok
                  FROM unnest(regexp_split_to_array(lower(btrim(?)), '\\s+')) AS raw_token
                ) s
              ) <@ ?::text[]
              OR ?::text[] <@ (
                SELECT coalesce(array_agg(tok) FILTER (WHERE tok <> ''), ARRAY[]::text[])
                FROM (
                  SELECT regexp_replace(raw_token, '[^a-z0-9]', '', 'g') AS tok
                  FROM unnest(regexp_split_to_array(lower(btrim(?)), '\\s+')) AS raw_token
                ) s
              )
              """,
              m.make,
              ^make_tokens,
              ^make_tokens,
              m.make
            ) and
              fragment(
                """
                (
                  SELECT coalesce(array_agg(tok) FILTER (WHERE tok <> ''), ARRAY[]::text[])
                  FROM (
                    SELECT regexp_replace(raw_token, '[^a-z0-9]', '', 'g') AS tok
                    FROM unnest(regexp_split_to_array(lower(btrim(?)), '\\s+')) AS raw_token
                  ) s
                ) <@ ?::text[]
                OR ?::text[] <@ (
                  SELECT coalesce(array_agg(tok) FILTER (WHERE tok <> ''), ARRAY[]::text[])
                  FROM (
                    SELECT regexp_replace(raw_token, '[^a-z0-9]', '', 'g') AS tok
                    FROM unnest(regexp_split_to_array(lower(btrim(?)), '\\s+')) AS raw_token
                  ) s
                )
                """,
                m.model,
                ^model_tokens,
                ^model_tokens,
                m.model
              ),
          order_by: [desc: m.inserted_at, desc: m.id]
        )

      base =
        if exclude_ids == [] do
          base
        else
          from(m in base, where: m.id not in ^exclude_ids)
        end

      with_year =
        if is_integer(year) do
          from(m in base, where: m.year >= ^(year - 2) and m.year <= ^(year + 2))
          |> maybe_limit(limit)
          |> Repo.all()
        else
          []
        end

      cond do
        with_year != [] ->
          with_year

        require_year? ->
          []

        true ->
          base
          |> maybe_limit(limit)
          |> Repo.all()
      end
    end
  end

  @doc """
  Appends a market price id to a query's `dismissed_similar_ids` (owner-only).
  """
  def dismiss_similar_market_price(%User{} = user, query_id, market_price_id)
      when is_binary(query_id) and is_binary(market_price_id) do
    case Repo.get_by(VehiclePriceQuery, id: query_id, user_id: user.id) do
      %VehiclePriceQuery{} = query ->
        ids = query.dismissed_similar_ids || []

        if market_price_id in ids do
          {:ok, query}
        else
          query
          |> Ecto.Changeset.change(%{dismissed_similar_ids: ids ++ [market_price_id]})
          |> Repo.update()
        end

      nil ->
        {:error, :not_found}
    end
  end

  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0, do: limit(query, ^limit)
  defp maybe_limit(query, _), do: query

  defp parse_year(nil), do: nil
  defp parse_year(0), do: nil
  defp parse_year(year) when is_integer(year) and year > 1900, do: year
  defp parse_year(year) when is_integer(year), do: nil

  defp parse_year(year) do
    case Mechanics.NumberParse.to_integer(year) do
      {:ok, int} -> parse_year(int)
      :error -> nil
    end
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
                  |> maybe_default_zipcode()

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
    zipcode = Keyword.get(opts, :zipcode)

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
              |> maybe_merge_zipcode(zipcode)
              |> maybe_default_zipcode()
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
              |> maybe_merge_zipcode(zipcode)
              |> maybe_default_zipcode()
              |> coerce_market_price_numbers()

            {:needs_form, attrs}
        end
    end
  end

  defp maybe_merge_miles(attrs, miles) when miles in [nil, ""] do
    Map.put_new(attrs, "miles", 0)
  end

  defp maybe_merge_miles(attrs, miles) do
    case Mechanics.NumberParse.to_integer(miles) do
      {:ok, int} -> Map.put(attrs, "miles", int)
      :error -> Map.put_new(attrs, "miles", 0)
    end
  end

  defp maybe_merge_zipcode(attrs, zipcode) when zipcode in [nil, ""], do: attrs

  defp maybe_merge_zipcode(attrs, zipcode) when is_binary(zipcode) do
    Map.put(attrs, "zipcode", String.trim(zipcode))
  end

  defp maybe_merge_zipcode(attrs, _), do: attrs

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

  Duplicate searches (same make, model, year, miles, VIN, and zipcode) update the existing row
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

  defp get_query_by_vehicle(
         user_id,
         %{"make" => make, "model" => model, "year" => year, "miles" => miles, "vin" => vin, "zipcode" => zipcode}
       ) do
    query =
      from(q in VehiclePriceQuery,
        where: q.user_id == ^user_id,
        where: q.make == ^make,
        where: q.model == ^model,
        where: q.year == ^year,
        where: q.miles == ^miles,
        where: q.zipcode == ^zipcode
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
    attrs =
      attrs
      |> default_blank_miles()
      |> default_blank_year()
      |> maybe_default_zipcode()

    required = ["make", "model", "miles", "zipcode"]

    missing =
      Enum.filter(required, fn key ->
        value = Map.get(attrs, key)
        is_nil(value) or (is_binary(value) and String.trim(value) == "")
      end)

    if missing != [] do
      {:error, :invalid_vehicle}
    else
      year = normalize_optional_year(Map.get(attrs, "year"))

      {:ok,
       %{
         "vin" => blank_to_nil(Map.get(attrs, "vin")),
         "make" => attrs |> Map.get("make") |> to_string() |> String.trim(),
         "model" => attrs |> Map.get("model") |> to_string() |> String.trim(),
         "year" => year,
         "miles" => Mechanics.NumberParse.to_integer!(Map.get(attrs, "miles")),
         "zipcode" => attrs |> Map.get("zipcode") |> to_string() |> String.trim()
       }}
    end
  rescue
    ArgumentError -> {:error, :invalid_vehicle}
  end

  defp default_blank_miles(attrs) do
    case Map.get(attrs, "miles") do
      miles when miles in [nil, ""] -> Map.put(attrs, "miles", 0)
      _ -> attrs
    end
  end

  defp default_blank_year(attrs) do
    case Map.get(attrs, "year") do
      year when year in [nil, ""] -> Map.put(attrs, "year", 0)
      _ -> attrs
    end
  end

  # 0 means "unspecified" so make/model-only searches can persist and find similar comps.
  defp normalize_optional_year(year) do
    int = Mechanics.NumberParse.to_integer!(year)

    cond do
      int == 0 -> 0
      int > 1900 and int < 2100 -> int
      true -> raise ArgumentError, "invalid year"
    end
  end

  defp maybe_default_zipcode(attrs) do
    case Map.get(attrs, "zipcode") do
      zip when zip in [nil, ""] -> Map.put(attrs, "zipcode", "00000")
      _ -> attrs
    end
  end

  defp apply_market_price_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:make, make}, q when is_binary(make) and make != "" ->
        case normalize_vehicle_tokens(make) do
          [] ->
            q

          make_tokens ->
            where(
              q,
              [m],
              fragment(
                """
                (
                  SELECT coalesce(array_agg(tok) FILTER (WHERE tok <> ''), ARRAY[]::text[])
                  FROM (
                    SELECT regexp_replace(raw_token, '[^a-z0-9]', '', 'g') AS tok
                    FROM unnest(regexp_split_to_array(lower(btrim(?)), '\\s+')) AS raw_token
                  ) s
                ) <@ ?::text[]
                OR ?::text[] <@ (
                  SELECT coalesce(array_agg(tok) FILTER (WHERE tok <> ''), ARRAY[]::text[])
                  FROM (
                    SELECT regexp_replace(raw_token, '[^a-z0-9]', '', 'g') AS tok
                    FROM unnest(regexp_split_to_array(lower(btrim(?)), '\\s+')) AS raw_token
                  ) s
                )
                """,
                m.make,
                ^make_tokens,
                ^make_tokens,
                m.make
              )
            )
        end

      {:model, model}, q when is_binary(model) and model != "" ->
        case normalize_vehicle_tokens(model) do
          [] ->
            q

          model_tokens ->
            where(
              q,
              [m],
              fragment(
                """
                (
                  SELECT coalesce(array_agg(tok) FILTER (WHERE tok <> ''), ARRAY[]::text[])
                  FROM (
                    SELECT regexp_replace(raw_token, '[^a-z0-9]', '', 'g') AS tok
                    FROM unnest(regexp_split_to_array(lower(btrim(?)), '\\s+')) AS raw_token
                  ) s
                ) <@ ?::text[]
                OR ?::text[] <@ (
                  SELECT coalesce(array_agg(tok) FILTER (WHERE tok <> ''), ARRAY[]::text[])
                  FROM (
                    SELECT regexp_replace(raw_token, '[^a-z0-9]', '', 'g') AS tok
                    FROM unnest(regexp_split_to_array(lower(btrim(?)), '\\s+')) AS raw_token
                  ) s
                )
                """,
                m.model,
                ^model_tokens,
                ^model_tokens,
                m.model
              )
            )
        end

      {:price_type, type}, q when type in ["listing", "sale"] ->
        where(q, [m], m.price_type == ^type)

      {:vin, vin}, q when is_binary(vin) and vin != "" ->
        normalized = vin |> String.trim() |> String.upcase()
        where(q, [m], fragment("upper(?)", m.vin) == ^normalized)

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
