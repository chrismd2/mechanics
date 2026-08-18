defmodule Mechanics.NumberParse do
  @moduledoc """
  Parses user/agent numeric input that may include commas or fractional values.
  """

  @doc """
  Removes grouping commas and whitespace from a numeric string.
  """
  def sanitize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(",", "")
    |> String.replace(~r/\s+/, "")
  end

  def sanitize(value), do: value

  @doc """
  Parses an integer from an integer, float, Decimal, or string (commas allowed).
  Floats are rounded to the nearest integer.
  """
  def to_integer(value) when is_integer(value), do: {:ok, value}

  def to_integer(value) when is_float(value), do: {:ok, round(value)}

  def to_integer(%Decimal{} = value) do
    {:ok, value |> Decimal.round(0) |> Decimal.to_integer()}
  end

  def to_integer(value) when is_binary(value) do
    cleaned = sanitize(value)

    case Decimal.parse(cleaned) do
      {decimal, ""} ->
        {:ok, decimal |> Decimal.round(0) |> Decimal.to_integer()}

      _ ->
        :error
    end
  end

  def to_integer(_), do: :error

  @doc """
  Like `to_integer/1` but raises `ArgumentError` on failure.
  """
  def to_integer!(value) do
    case to_integer(value) do
      {:ok, int} -> int
      :error -> raise ArgumentError, "invalid integer: #{inspect(value)}"
    end
  end
end
