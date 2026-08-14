defmodule Mechanics.Pricing.Agent do
  @moduledoc """
  Pricing agent: local tool calling against vehicle market prices, then
  competitive / expected-minimum suggestions.
  """

  require Logger

  alias Mechanics.Pricing
  alias Mechanics.Pricing.BidWrangler
  alias Mechanics.Pricing.ListingSearch
  alias Mechanics.Pricing.LLM
  alias Mechanics.Pricing.Sources.Royal, as: RoyalSource

  @max_rounds 5

  def tool_definitions do
    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "search_vehicle_market_prices",
          "description" =>
            "Search stored vehicle market prices and enabled external auction sources (BidWrangler, Royal) by make, model, year, miles, and optional price_type. External hits use ids prefixed with candidate:.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "make" => %{"type" => "string"},
              "model" => %{"type" => "string"},
              "year_min" => %{"type" => "integer"},
              "year_max" => %{"type" => "integer"},
              "miles_min" => %{"type" => "integer"},
              "miles_max" => %{"type" => "integer"},
              "price_type" => %{"type" => "string", "enum" => ["listing", "sale"]}
            },
            "required" => ["make", "model"]
          }
        }
      },
      %{
        "type" => "function",
        "function" => %{
          "name" => "get_vehicle_market_price_details",
          "description" =>
            "Fetch price details for vehicle market price ids or external candidate: ids returned by search.",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "ids" => %{
                "type" => "array",
                "items" => %{"type" => "string"}
              }
            },
            "required" => ["ids"]
          }
        }
      }
    ]
  end

  def execute_tool("search_vehicle_market_prices", args) when is_map(args) do
    make = Map.get(args, "make") || Map.get(args, :make)
    model = Map.get(args, "model") || Map.get(args, :model)

    filters =
      %{}
      |> maybe_put(:make, make)
      |> maybe_put(:model, model)
      |> maybe_put(:price_type, Map.get(args, "price_type") || Map.get(args, :price_type))
      |> maybe_put(:year_min, parse_optional_int(Map.get(args, "year_min") || Map.get(args, :year_min)))
      |> maybe_put(:year_max, parse_optional_int(Map.get(args, "year_max") || Map.get(args, :year_max)))
      |> maybe_put(:miles_min, parse_optional_int(Map.get(args, "miles_min") || Map.get(args, :miles_min)))
      |> maybe_put(:miles_max, parse_optional_int(Map.get(args, "miles_max") || Map.get(args, :miles_max)))

    local =
      Pricing.list_market_prices(filters)
      |> Enum.map(fn row ->
        %{
          id: row.id,
          make: row.make,
          model: row.model,
          year: row.year,
          miles: row.miles,
          zipcode: row.zipcode,
          price_type: row.price_type,
          source: "local"
        }
      end)

    external =
      case ListingSearch.search_for_vehicle(make, model) do
        {:ok, candidates} ->
          candidates
          |> Enum.map(&ListingSearch.candidate_to_search_row/1)
          |> maybe_filter_external_price_type(Map.get(filters, :price_type))

        {:error, _} ->
          []
      end

    local ++ external
  end

  def execute_tool("get_vehicle_market_price_details", args) when is_map(args) do
    ids = Map.get(args, "ids") || Map.get(args, :ids) || []
    ids = List.wrap(ids) |> Enum.map(&to_string/1)

    {candidate_ids, market_ids} =
      Enum.split_with(ids, fn id -> match?({:ok, _}, ListingSearch.parse_candidate_tool_id(id)) end)

    Pricing.get_market_price_details(market_ids) ++
      ListingSearch.get_candidate_price_details(candidate_ids)
  end

  def execute_tool(_name, _args), do: %{error: "unknown_tool"}

  defp maybe_filter_external_price_type(rows, nil), do: rows
  defp maybe_filter_external_price_type(rows, ""), do: rows

  defp maybe_filter_external_price_type(rows, price_type) when is_binary(price_type) do
    Enum.filter(rows, fn row -> row[:price_type] == price_type or row.price_type == price_type end)
  end

  @doc """
  Suggests competitive and expected-minimum prices for a vehicle map.

  Returns a map with `:competitive_cents`, `:minimum_cents`, `:match_count`,
  `:summary`, and `:currency`.
  """
  def suggest(vehicle, opts \\ []) when is_map(vehicle) do
    seed_matches = seed_market_matches(vehicle)
    year = Map.get(vehicle, "year") || Map.get(vehicle, :year)

    # No year → percentile best guess from make/model comps (skip LLM).
    if year in [nil, 0] do
      heuristic_suggestion(seed_matches, best_guess: true)
    else
      try do
        case LLM.chat_completion(initial_messages(vehicle), tool_definitions(), opts) do
          {:ok, response} ->
            run_tool_loop(response, initial_messages(vehicle), 1, opts)
            |> finalize_suggestion(seed_matches)

          {:error, reason} ->
            Logger.info("Pricing agent falling back without LLM: #{inspect(reason)}")
            heuristic_suggestion(seed_matches)
        end
      rescue
        e ->
          Logger.warning("Pricing agent falling back after exception: #{Exception.message(e)}")
          heuristic_suggestion(seed_matches)
      end
    end
  end

  defp seed_market_matches(vehicle) do
    year = Map.get(vehicle, "year") || Map.get(vehicle, :year)
    miles = Map.get(vehicle, "miles") || Map.get(vehicle, :miles) || 0
    make = Map.get(vehicle, "make") || Map.get(vehicle, :make)
    model = Map.get(vehicle, "model") || Map.get(vehicle, :model)
    vin = blank_to_nil(Map.get(vehicle, "vin") || Map.get(vehicle, :vin))

    by_make_model =
      if year in [nil, 0] do
        Pricing.list_similar_market_prices(
          %{"make" => make, "model" => model},
          limit: 50
        )
      else
        # Miles 0 means unspecified — skip the miles band so year+make/model comps are found.
        tight =
          if miles in [nil, 0] do
            []
          else
            Pricing.list_market_prices(%{
              make: make,
              model: model,
              year_min: year - 1,
              year_max: year + 1,
              miles_min: trunc(miles * 0.8),
              miles_max: trunc(miles * 1.2)
            })
          end

        if tight == [] do
          Pricing.list_market_prices(%{
            make: make,
            model: model,
            year_min: year - 1,
            year_max: year + 1
          })
        else
          tight
        end
      end

    by_vin =
      if is_binary(vin) and vin != "" do
        Pricing.list_market_prices(%{vin: vin})
      else
        []
      end

    (by_make_model ++ by_vin)
    |> Enum.uniq_by(& &1.id)
  end

  defp run_tool_loop(response, messages, round, opts) when round <= @max_rounds do
    choice = get_in(response, ["choices", Access.at(0), "message"]) || %{}
    tool_calls = Map.get(choice, "tool_calls") || []

    if tool_calls == [] do
      {choice, messages}
    else
      assistant_msg = Map.take(choice, ["role", "content", "tool_calls"])
      messages = messages ++ [assistant_msg]

      tool_messages =
        Enum.map(tool_calls, fn call ->
          id = Map.get(call, "id")
          name = get_in(call, ["function", "name"])
          args_json = get_in(call, ["function", "arguments"]) || "{}"

          args =
            case Jason.decode(args_json) do
              {:ok, decoded} when is_map(decoded) -> decoded
              _ -> %{}
            end

          result = execute_tool(name, args)

          %{
            "role" => "tool",
            "tool_call_id" => id,
            "content" => Jason.encode!(result)
          }
        end)

      messages = messages ++ tool_messages

      case LLM.chat_completion(messages, tool_definitions(), opts) do
        {:ok, next} -> run_tool_loop(next, messages, round + 1, opts)
        {:error, _} -> {choice, messages}
      end
    end
  end

  defp run_tool_loop(response, messages, _round, _opts) do
    choice = get_in(response, ["choices", Access.at(0), "message"]) || %{}
    {choice, messages}
  end

  defp finalize_suggestion({choice, _messages}, seed_matches) do
    content = Map.get(choice, "content") || ""

    case parse_suggestion_json(content) do
      {:ok, competitive, minimum, summary} ->
        if is_nil(competitive) and is_nil(minimum) and seed_matches != [] do
          # LLM said insufficient, but we have comps — use percentile suggestion.
          heuristic_suggestion(seed_matches)
        else
          %{
            competitive_cents: competitive,
            minimum_cents: minimum,
            match_count: length(seed_matches),
            summary: summary || blank_to_nil(String.slice(content, 0, 500)),
            currency: "USD"
          }
        end

      :error ->
        base = heuristic_suggestion(seed_matches)

        # Prefer heuristic copy over raw model text (often unparsed JSON).
        if usable_agent_summary?(content) do
          Map.put(base, :summary, String.slice(String.trim(content), 0, 500))
        else
          base
        end
    end
  end

  defp usable_agent_summary?(content) when is_binary(content) do
    trimmed = String.trim(content)
    trimmed != "" and not String.contains?(trimmed, "{")
  end

  defp usable_agent_summary?(_), do: false

  defp heuristic_suggestion(matches, opts \\ [])

  defp heuristic_suggestion([], _opts),
    do: %{
      competitive_cents: nil,
      minimum_cents: nil,
      match_count: 0,
      summary: "Insufficient market price data to suggest a price.",
      currency: "USD"
    }

  defp heuristic_suggestion(matches, opts) do
    prices =
      matches
      |> Enum.map(& &1.price_cents)
      |> Enum.sort()

    summary =
      if Keyword.get(opts, :best_guess, false) do
        "Best guess from #{length(prices)} matching vehicle market prices (year not specified)."
      else
        "Suggested from #{length(prices)} matching vehicle market prices."
      end

    %{
      competitive_cents: percentile(prices, 0.5),
      minimum_cents: percentile(prices, 0.1),
      match_count: length(prices),
      summary: summary,
      currency: "USD"
    }
  end

  defp percentile(sorted, p) when is_list(sorted) and sorted != [] do
    n = length(sorted)
    idx = max(0, min(n - 1, round((n - 1) * p)))
    Enum.at(sorted, idx)
  end

  defp parse_suggestion_json(content) when is_binary(content) do
    trimmed = String.trim(content)

    json_blob =
      cond do
        String.starts_with?(trimmed, "{") ->
          trimmed

        Regex.match?(~r/\{[\s\S]*\}/, trimmed) ->
          case Regex.run(~r/\{[\s\S]*\}/, trimmed) do
            [match | _] -> match
            _ -> nil
          end

        true ->
          nil
      end

    with true <- is_binary(json_blob),
         {:ok, map} <- Jason.decode(json_blob) do
      competitive =
        Map.get(map, "suggested_competitive_cents") || Map.get(map, "competitive_cents")

      minimum = Map.get(map, "suggested_minimum_cents") || Map.get(map, "minimum_cents")
      summary = Map.get(map, "summary") || Map.get(map, "agent_summary")

      competitive = if is_integer(competitive), do: competitive, else: nil
      minimum = if is_integer(minimum), do: minimum, else: nil

      # Accept partial or both-null (LLM said insufficient). Reject empty/non-object shapes.
      if is_integer(competitive) or is_integer(minimum) or is_binary(summary) do
        {:ok, competitive, minimum, summary}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  defp parse_suggestion_json(_), do: :error

  defp initial_messages(vehicle) do
    year = Map.get(vehicle, "year") || Map.get(vehicle, :year)
    miles = Map.get(vehicle, "miles") || Map.get(vehicle, :miles)
    make = Map.get(vehicle, "make") || Map.get(vehicle, :make)
    model = Map.get(vehicle, "model") || Map.get(vehicle, :model)
    vin = Map.get(vehicle, "vin") || Map.get(vehicle, :vin)
    zipcode = Map.get(vehicle, "zipcode") || Map.get(vehicle, :zipcode) || "00000"

    system = """
    You help price used vehicles using only tool results from our vehicle_market_prices database.
    Use sales for expected-minimum / floor context and listings for competitive / asking context.
    After calling tools as needed, reply with ONLY a JSON object:
    {"suggested_competitive_cents": <int>, "suggested_minimum_cents": <int>, "summary": "<short text>"}
    If data is insufficient, use null for both price fields and explain in summary.
    Prices must be integers in USD cents. suggested_minimum_cents must be <= suggested_competitive_cents when both are set.
    """

    user = """
    Suggest competitive and expected-minimum prices for:
    make=#{make}, model=#{model}, year=#{year}, miles=#{miles}, zipcode=#{zipcode}, vin=#{vin || "n/a"}
    Search around year ±1 and miles ±20% first; widen if needed.
    """

    [
      %{"role" => "system", "content" => system},
      %{"role" => "user", "content" => user}
    ]
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_optional_int(nil), do: nil
  defp parse_optional_int(value) do
    case Mechanics.NumberParse.to_integer(value) do
      {:ok, int} -> int
      :error -> nil
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @doc """
  Fetches a listing/sale page and asks the LLM to extract vehicle market price fields.

  BidWrangler UI item URLs (`/ui/auctions/:auction_id/:item_id`) use `{origin}/api/items/:item_id`
  with deterministic mapping (LLM only if required fields are still missing).

  Returns `{:ok, attrs_map}` with string keys (may be partial), or `{:error, reason}`.
  """
  def extract_listing_from_url(url, opts \\ []) when is_binary(url) do
    cond do
      match?({:ok, _}, BidWrangler.parse_item_ui_url(url)) ->
        {:ok, parsed} = BidWrangler.parse_item_ui_url(url)
        extract_bidwrangler_item(url, parsed, opts)

      match?({:ok, _}, RoyalSource.parse_lot_url(url)) ->
        extract_royal_lot(url, opts)

      true ->
        extract_from_html_page(url, opts)
    end
  end

  defp extract_royal_lot(url, opts) do
    case RoyalSource.fetch_detail(url, opts) do
      {:ok, attrs} ->
        if BidWrangler.complete_extract_attrs?(attrs) do
          {:ok, attrs}
        else
          summary =
            attrs
            |> Enum.map(fn {k, v} -> "#{k}: #{v}" end)
            |> Enum.join("\n")

          llm_extract_or_attrs(url, summary, attrs, opts)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_bidwrangler_item(url, %{origin: origin, item_id: item_id}, opts) do
    http_get = Keyword.get(opts, :http_get, &default_http_get/1)
    api_url = "#{origin}/api/items/#{item_id}"

    case http_get.(api_url) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, item} when is_map(item) ->
            attrs = BidWrangler.attrs_from_item(item)

            if BidWrangler.complete_extract_attrs?(attrs) do
              {:ok, attrs}
            else
              summary = BidWrangler.compact_summary(item)
              llm_extract_or_attrs(url, summary, attrs, opts)
            end

          _ ->
            {:error, :invalid_item_json}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp llm_extract_or_attrs(url, page_text, attrs, opts) do
    case LLM.chat_completion(extract_messages(url, page_text), [], opts) do
      {:ok, response} ->
        content = get_in(response, ["choices", Access.at(0), "message", "content"]) || ""

        case parse_extracted_listing(content) do
          {:ok, llm_attrs} -> {:ok, Map.merge(attrs, llm_attrs)}
          {:error, _} -> {:ok, attrs}
        end

      {:error, _} ->
        {:ok, attrs}
    end
  end

  defp extract_from_html_page(url, opts) do
    fetch = Keyword.get(opts, :fetch, &fetch_page_text/1)

    with {:ok, page_text} <- fetch.(url),
         {:ok, response} <-
           LLM.chat_completion(extract_messages(url, page_text), [], opts) do
      content = get_in(response, ["choices", Access.at(0), "message", "content"]) || ""
      parse_extracted_listing(content)
    end
  end

  defp default_http_get(url) do
    headers = [
      {"Accept", "application/json"},
      {"User-Agent", "MechanicsPricingBot/1.0"}
    ]

    case Finch.build(:get, url, headers) |> Finch.request(Mechanics.Finch, receive_timeout: 15_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_page_text(url) do
    headers = [
      {"Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
      {"User-Agent", "MechanicsPricingBot/1.0"}
    ]

    case Finch.build(:get, url, headers) |> Finch.request(Mechanics.Finch, receive_timeout: 15_000) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, page_text_from_html(body)}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Convert fetched HTML into plain text for listing extraction.

  Keeps Open Graph / meta title and description (and the document title) in addition
  to stripped body text so JS-rendered auction pages still yield vehicle details.
  """
  def page_text_from_html(body) when is_binary(body) do
    meta_bits =
      []
      |> maybe_append_meta(body, ~r/<meta[^>]+property=["']og:title["'][^>]*content=["']([^"']*)["'][^>]*>/i)
      |> maybe_append_meta(body, ~r/<meta[^>]+content=["']([^"']*)["'][^>]*property=["']og:title["'][^>]*>/i)
      |> maybe_append_meta(body, ~r/<meta[^>]+property=["']og:description["'][^>]*content=["']([^"']*)["'][^>]*>/i)
      |> maybe_append_meta(body, ~r/<meta[^>]+content=["']([^"']*)["'][^>]*property=["']og:description["'][^>]*>/i)
      |> maybe_append_meta(body, ~r/<meta[^>]+name=["']description["'][^>]*content=["']([^"']*)["'][^>]*>/i)
      |> maybe_append_meta(body, ~r/<meta[^>]+content=["']([^"']*)["'][^>]*name=["']description["'][^>]*>/i)
      |> maybe_append_title(body)

    body_text =
      body
      |> String.replace(~r/<script[\s\S]*?<\/script>/i, " ")
      |> String.replace(~r/<style[\s\S]*?<\/style>/i, " ")
      |> String.replace(~r/<[^>]+>/, " ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    (meta_bits ++ [body_text])
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 12_000)
  end

  defp maybe_append_meta(acc, html, pattern) do
    case Regex.run(pattern, html) do
      [_, content] ->
        trimmed = String.trim(content)
        if trimmed == "", do: acc, else: acc ++ [trimmed]

      _ ->
        acc
    end
  end

  defp maybe_append_title(acc, html) do
    case Regex.run(~r/<title[^>]*>([^<]*)<\/title>/i, html) do
      [_, title] ->
        trimmed = String.trim(title)
        if trimmed == "" or trimmed in acc, do: acc, else: acc ++ [trimmed]

      _ ->
        acc
    end
  end

  defp extract_messages(url, page_text) do
    system = """
    Extract used-vehicle listing or sale details from page text.
    Reply with ONLY a JSON object:
    {
      "make": string|null,
      "model": string|null,
      "year": integer|null,
      "miles": integer|null,
      "zipcode": string|null,
      "price_cents": integer|null,
      "currency": string|null,
      "price_type": "listing"|"sale"|null,
      "vin": string|null,
      "notes": string|null
    }
    price_cents must be an integer in minor units (USD cents). Prefer "listing" for asking prices and "sale" for sold/completed transactions.
    zipcode should be a 5-digit US ZIP when present on the page.
    Use null for unknown fields. Do not invent values that are not supported by the text.
    """

    user = """
    Source URL: #{url}

    Page text:
    #{page_text}
    """

    [
      %{"role" => "system", "content" => system},
      %{"role" => "user", "content" => user}
    ]
  end

  defp parse_extracted_listing(content) when is_binary(content) do
    trimmed = String.trim(content)

    json_blob =
      cond do
        String.starts_with?(trimmed, "{") ->
          trimmed

        Regex.match?(~r/\{[\s\S]*\}/, trimmed) ->
          case Regex.run(~r/\{[\s\S]*\}/, trimmed) do
            [match | _] -> match
            _ -> nil
          end

        true ->
          nil
      end

    with true <- is_binary(json_blob),
         {:ok, map} when is_map(map) <- Jason.decode(json_blob) do
      attrs =
        %{
          "make" => blank_to_nil(Map.get(map, "make")),
          "model" => blank_to_nil(Map.get(map, "model")),
          "year" => parse_optional_int(Map.get(map, "year")),
          "miles" => parse_optional_int(Map.get(map, "miles")),
          "zipcode" => blank_to_nil(Map.get(map, "zipcode")),
          "price_cents" => parse_optional_int(Map.get(map, "price_cents")),
          "currency" => blank_to_nil(Map.get(map, "currency")) || "USD",
          "price_type" => normalize_price_type(Map.get(map, "price_type")),
          "vin" => blank_to_nil(Map.get(map, "vin")),
          "notes" => blank_to_nil(Map.get(map, "notes"))
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()

      {:ok, attrs}
    else
      _ -> {:error, :unparseable_extraction}
    end
  end

  defp normalize_price_type(type) when type in ["listing", "sale"], do: type
  defp normalize_price_type(_), do: nil
end
