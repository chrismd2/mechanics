defmodule MechanicsWeb.Helpers.CurrencyFormatterTest do
  use ExUnit.Case, async: true

  alias MechanicsWeb.Helpers.CurrencyFormatter

  test "format groups thousands for USD" do
    assert CurrencyFormatter.format(2_600_000, "USD") == "$26,000.00"
    assert CurrencyFormatter.format(1_850_000, "USD") == "$18,500.00"
    assert CurrencyFormatter.format(99, "USD") == "$0.99"
  end

  test "format_number groups thousands without the symbol" do
    assert CurrencyFormatter.format_number(2_600_000, "USD") == "26,000.00"
  end

  test "format_integer groups miles-style integers" do
    assert CurrencyFormatter.format_integer(41_921) == "41,921"
    assert CurrencyFormatter.format_integer(0) == "0"
  end
end
