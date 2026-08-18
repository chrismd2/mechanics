defmodule Mechanics.NumberParseTest do
  use ExUnit.Case, async: true

  alias Mechanics.NumberParse
  alias MechanicsWeb.Helpers.CurrencyFormatter

  test "to_integer strips commas and rounds floats" do
    assert NumberParse.to_integer("45,000") == {:ok, 45_000}
    assert NumberParse.to_integer("45,000.4") == {:ok, 45_000}
    assert NumberParse.to_integer("45,000.6") == {:ok, 45_001}
    assert NumberParse.to_integer(12_345.2) == {:ok, 12_345}
    assert NumberParse.to_integer(2019) == {:ok, 2019}
  end

  test "parse_major_to_minor accepts comma-formatted amounts and fractional dollars" do
    assert CurrencyFormatter.parse_major_to_minor("18,500.00", "USD") == {:ok, 1_850_000}
    assert CurrencyFormatter.parse_major_to_minor("18,500.5", "USD") == {:ok, 1_850_050}
    assert CurrencyFormatter.parse_major_to_minor("100", "USD") == {:ok, 10_000}
  end
end
