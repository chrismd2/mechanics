defmodule MechanicsWeb.Helpers.CurrencyFormatter do
  # Minor unit exponents from ISO 4217 (decimal places)
  @currency_exponents %{
    "AED" => 2, "AFN" => 2, "ALL" => 2, "AMD" => 2, "ANG" => 2, "AOA" => 2,
    "ARS" => 2, "AUD" => 2, "AWG" => 2, "AZN" => 2, "BAM" => 2, "BBD" => 2,
    "BDT" => 2, "BGN" => 2, "BIF" => 0, "BMD" => 2, "BND" => 2, "BOB" => 2,
    "BRL" => 2, "BSD" => 2, "BTN" => 2, "BWP" => 2, "BYN" => 2, "BZD" => 2,
    "CAD" => 2, "CDF" => 2, "CHF" => 2, "CLP" => 0, "CNY" => 2, "COP" => 2,
    "CRC" => 2, "CUP" => 2, "CVE" => 2, "CZK" => 2, "DJF" => 0, "DKK" => 2,
    "DOP" => 2, "DZD" => 2, "EGP" => 2, "ERN" => 2, "ETB" => 2, "EUR" => 2,
    "FJD" => 2, "FKP" => 2, "GBP" => 2, "GEL" => 2, "GHS" => 2, "GIP" => 2,
    "GMD" => 2, "GNF" => 0, "GTQ" => 2, "GYD" => 2, "HKD" => 2, "HNL" => 2,
    "HRK" => 2, "HTG" => 2, "HUF" => 2, "IDR" => 0, "ILS" => 2, "INR" => 2,
    "IQD" => 3, "IRR" => 2, "ISK" => 0, "JMD" => 2, "JOD" => 3, "KES" => 2,
    "KGS" => 2, "KHR" => 2, "KMF" => 0, "KPW" => 2, "KRW" => 0, "KWD" => 3,
    "KYD" => 2, "KZT" => 2, "LAK" => 2, "LBP" => 2, "LKR" => 2, "LRD" => 2,
    "LSL" => 2, "LYD" => 3, "MAD" => 2, "MDL" => 2, "MGA" => 2, "MKD" => 2,
    "MMK" => 2, "MNT" => 2, "MOP" => 2, "MRU" => 2, "MUR" => 2, "MVR" => 2,
    "MWK" => 2, "MXN" => 2, "MYR" => 2, "MZN" => 2, "NAD" => 2, "NGN" => 2,
    "NIO" => 2, "NOK" => 2, "NPR" => 2, "NZD" => 2, "OMR" => 3, "PAB" => 2,
    "PEN" => 2, "PGK" => 2, "PHP" => 2, "PKR" => 2, "PLN" => 2, "PYG" => 0,
    "QAR" => 2, "RON" => 2, "RSD" => 2, "RUB" => 2, "RWF" => 0, "SAR" => 2,
    "SBD" => 2, "SCR" => 2, "SDG" => 2, "SEK" => 2, "SGD" => 2, "SHP" => 2,
    "SLE" => 2, "SOS" => 2, "SRD" => 2, "SSP" => 2, "STN" => 2, "SVC" => 2,
    "SYP" => 2, "SZL" => 2, "THB" => 2, "TJS" => 2, "TMT" => 2, "TND" => 3,
    "TOP" => 2, "TRY" => 2, "TTD" => 2, "TWD" => 2, "TZS" => 2, "UAH" => 2,
    "UGX" => 0, "USD" => 2, "UYU" => 2, "UZS" => 2, "VES" => 2, "VND" => 0,
    "VUV" => 0, "WST" => 2, "XAF" => 0, "XCD" => 2, "XOF" => 0, "XPF" => 0,
    "YER" => 2, "ZAR" => 2, "ZMW" => 2, "ZWG" => 2
  }

  # Common currency symbols (most recognizable version)
  @currency_symbols %{
    "USD" => "$", "EUR" => "€", "GBP" => "£", "JPY" => "¥", "CNY" => "¥",
    "INR" => "₹", "RUB" => "₽", "BRL" => "R$", "KRW" => "₩", "AUD" => "$",
    "CAD" => "$", "CHF" => "CHF", "HKD" => "HK$", "MXN" => "MX$",
    "NZD" => "NZ$", "SGD" => "S$", "ZAR" => "R", "TRY" => "₺",
    "SEK" => "kr", "NOK" => "kr", "DKK" => "kr", "PLN" => "zł",
    "THB" => "฿", "IDR" => "Rp", "MYR" => "RM", "PHP" => "₱",
    "VND" => "₫", "ARS" => "$", "CLP" => "$", "COP" => "$",
    "PEN" => "S/", "EGP" => "E£", "NGN" => "₦", "GHS" => "GH₵",
    "KES" => "KSh", "ZMW" => "ZK", "XAF" => "FCFA", "XOF" => "CFA",
    "XCD" => "$", "AED" => "د.إ", "SAR" => "ر.س", "QAR" => "ر.ق",
    "KWD" => "د.ك", "BHD" => "د.ب", "OMR" => "ر.ع", "JOD" => "د.ا",
    "ILS" => "₪", "TWD" => "NT$", "HUF" => "Ft", "CZK" => "Kč",
    "RON" => "lei", "BGN" => "лв", "HRK" => "kn", "ISK" => "kr"
  }

  @default_exponent 2
  @default_symbol ""

  # ======================
  # Helper functions
  # ======================

  def get_exponent(currency_code) when is_binary(currency_code) do
    code = String.upcase(currency_code)
    Map.get(@currency_exponents, code, @default_exponent)
  end

  def get_symbol(currency_code) when is_binary(currency_code) do
    code = String.upcase(currency_code)
    Map.get(@currency_symbols, code, code)  # fallback to code if unknown
  end

  def valid_currency_codes do
    @currency_exponents
    |> Map.keys()
    |> Enum.sort()
  end

  # ======================
  # Main formatting functions (fixed decimals by default)
  # ======================

  @doc """
  Formats amount (in minor units) with fixed decimal places and currency symbol.
  Always shows the correct number of decimals for the currency.

  Examples:
    format(12345, "USD")  => "$123.45"
    format(10000, "USD")  => "$100.00"
    format(12345, "JPY")  => "¥12345"
    format(12345, "BHD")  => "د.ب12.345"
  """
  def format(amount, currency_code) when is_integer(amount) do
    symbol = get_symbol(currency_code)
    formatted = format_number(amount, currency_code)

    "#{symbol}#{formatted}"
  end

  @doc """
  Formats without the currency symbol (still fixed decimals).
  Useful when you want to show the number only.
  """
  def format_number(amount, currency_code) when is_integer(amount) do
    exponent = get_exponent(currency_code)
    decimal_amount = Decimal.div(Decimal.new(amount), Decimal.new(10 ** exponent))
    to_fixed_decimal_string(decimal_amount, exponent)
  end

  @doc """
  Returns only the symbol for a currency.
  """
  def symbol(currency_code) do
    get_symbol(currency_code)
  end

  @doc """
  Parses a major-unit amount string and converts it to minor units.
  Returns `{:ok, integer_minor_units}` or `{:error, :invalid_amount}`.
  """
  def parse_major_to_minor(amount, currency_code) when is_binary(amount) do
    exponent = get_exponent(currency_code)
    multiplier = Decimal.new(10 ** exponent)

    case Decimal.parse(String.trim(amount)) do
      {decimal_amount, ""} ->
        if Decimal.compare(decimal_amount, 0) in [:eq, :gt] and Decimal.scale(decimal_amount) <= exponent do
          minor_units =
            decimal_amount
            |> Decimal.mult(multiplier)
            |> Decimal.to_integer()

          {:ok, minor_units}
        else
          {:error, :invalid_amount}
        end

      _ ->
        {:error, :invalid_amount}
    end
  end

  defp to_fixed_decimal_string(decimal_amount, exponent) do
    decimal_amount
    |> Decimal.round(exponent)
    |> Decimal.to_string(:normal)
    |> pad_fractional_zeros(exponent)
  end

  defp pad_fractional_zeros(number, 0), do: number

  defp pad_fractional_zeros(number, exponent) do
    case String.split(number, ".", parts: 2) do
      [whole, fraction] ->
        whole <> "." <> String.pad_trailing(fraction, exponent, "0")

      [whole] ->
        whole <> "." <> String.duplicate("0", exponent)
    end
  end
end
