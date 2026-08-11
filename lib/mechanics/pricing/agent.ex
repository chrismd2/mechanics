defmodule Mechanics.Pricing.Agent do
  @moduledoc """
  Pricing agent: local tool calling against vehicle market prices, then
  competitive / expected-minimum suggestions.
  """

  require Logger

  alias Mechanics.Pricing
  alias Mechanics.Pricing.LLM

  @max_rounds 5

  def tool_definitions do
    [
      %{
        "type" => "function",
        "function" => %{
          "name" => "search_vehicle_market_prices",
          "description" =>
            "Search stored vehicle market prices (asking listings or completed sales) by make, model, year, miles, and optional price_type.",
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
          "description" => "Fetch price details for vehicle market price ids returned by search.",
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
    filters =
      %{}
      |> maybe_put(:make, Map.get(args, "make") || Map.get(args, :make))
      |> maybe_put(:model, Map.get(args, "model") || Map.get(args, :model))
      |> maybe_put(:price_type, Map.get(args, "price_type") || Map.get(args, :price_type))
      |> maybe_put(:year_min, parse_optional_int(Map.get(args, "year_min") || Map.get(args, :year_min)))
      |> maybe_put(:year_max, parse_optional_int(Map.get(args, "year_max") || Map.get(args, :year_max)))
      |> maybe_put(:miles_min, parse_optional_int(Map.get(args, "miles_min") || Map.get(args, :miles_min)))
      |> maybe_put(:miles_max, parse_optional_int(Map.get(args, "miles_max") || Map.get(args, :miles_max)))

    Pricing.list_market_prices(filters)
    |> Enum.map(fn row ->
      %{
        id: row.id,
        make: row.make,
        model: row.model,
        year: row.year,
        miles: row.miles,
        price_type: row.price_type
      }
    end)
  end

  def execute_tool("get_vehicle_market_price_details", args) when is_map(args) do
    ids = Map.get(args, "ids") || Map.get(args, :ids) || []
    Pricing.get_market_price_details(List.wrap(ids))
  end

  def execute_tool(_name, _args), do: %{error: "unknown_tool"}

  @doc """
  Suggests competitive and expected-minimum prices for a vehicle map.

  Returns a map with `:competitive_cents`, `:minimum_cents`, `:match_count`,
  `:summary`, and `:currency`.
  """
  def suggest(vehicle, opts \\ []) when is_map(vehicle) do
    year = Map.get(vehicle, "year") || Map.get(vehicle, :year)
    miles = Map.get(vehicle, "miles") || Map.get(vehicle, :miles)
    make = Map.get(vehicle, "make") || Map.get(vehicle, :make)
    model = Map.get(vehicle, "model") || Map.get(vehicle, :model)

    seed_matches =
      Pricing.list_market_prices(%{
        make: make,
        model: model,
        year_min: year - 1,
        year_max: year + 1,
        miles_min: trunc(miles * 0.8),
        miles_max: trunc(miles * 1.2)
      })

    case LLM.chat_completion(initial_messages(vehicle), tool_definitions(), opts) do
      {:ok, response} ->
        run_tool_loop(response, initial_messages(vehicle), 1, opts)
        |> finalize_suggestion(seed_matches)

      {:error, reason} ->
        Logger.info("Pricing agent falling back without LLM: #{inspect(reason)}")
        heuristic_suggestion(seed_matches)
    end
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
        %{
          competitive_cents: competitive,
          minimum_cents: minimum,
          match_count: length(seed_matches),
          summary: summary || String.slice(content, 0, 500),
          currency: "USD"
        }

      :error ->
        heuristic_suggestion(seed_matches)
        |> Map.put(:summary, blank_to_nil(String.slice(content, 0, 500)))
    end
  end

  defp heuristic_suggestion([]),
    do: %{
      competitive_cents: nil,
      minimum_cents: nil,
      match_count: 0,
      summary: "Insufficient market price data to suggest a price.",
      currency: "USD"
    }

  defp heuristic_suggestion(matches) do
    prices =
      matches
      |> Enum.map(& &1.price_cents)
      |> Enum.sort()

    %{
      competitive_cents: percentile(prices, 0.5),
      minimum_cents: percentile(prices, 0.1),
      match_count: length(prices),
      summary: "Suggested from #{length(prices)} matching vehicle market prices.",
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
         {:ok, map} <- Jason.decode(json_blob),
         competitive when is_integer(competitive) <-
           Map.get(map, "suggested_competitive_cents") || Map.get(map, "competitive_cents"),
         minimum when is_integer(minimum) <-
           Map.get(map, "suggested_minimum_cents") || Map.get(map, "minimum_cents") do
      summary = Map.get(map, "summary") || Map.get(map, "agent_summary")
      {:ok, competitive, minimum, summary}
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
    make=#{make}, model=#{model}, year=#{year}, miles=#{miles}, vin=#{vin || "n/a"}
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
  defp parse_optional_int(value) when is_integer(value), do: value

  defp parse_optional_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_optional_int(_), do: nil

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
