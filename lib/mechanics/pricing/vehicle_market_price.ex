defmodule Mechanics.Pricing.VehicleMarketPrice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_price_types ~w(listing sale)

  schema "vehicle_market_prices" do
    field :vin, :string
    field :make, :string
    field :model, :string
    field :year, :integer
    field :miles, :integer
    field :price_cents, :integer
    field :currency, :string, default: "USD"
    field :price_type, :string
    field :notes, :string
    field :source_url, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(market_price, attrs) do
    market_price
    |> cast(attrs, [
      :vin,
      :make,
      :model,
      :year,
      :miles,
      :price_cents,
      :currency,
      :price_type,
      :notes,
      :source_url
    ])
    |> validate_required([
      :make,
      :model,
      :year,
      :miles,
      :price_cents,
      :currency,
      :price_type,
      :source_url
    ])
    |> update_change(:make, &trim_string/1)
    |> update_change(:model, &trim_string/1)
    |> update_change(:source_url, &trim_string/1)
    |> update_change(:currency, &upcase_currency/1)
    |> validate_inclusion(:price_type, @valid_price_types)
    |> validate_number(:year, greater_than: 1900, less_than: 2100)
    |> validate_number(:miles, greater_than_or_equal_to: 0)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_length(:currency, is: 3)
    |> validate_source_url()
    |> unique_constraint(:source_url, name: :vehicle_market_prices_source_url_index)
  end

  defp validate_source_url(changeset) do
    validate_change(changeset, :source_url, fn :source_url, url ->
      if is_binary(url) and String.match?(url, ~r/\Ahttps?:\/\//i) do
        []
      else
        [source_url: "must be an http(s) URL"]
      end
    end)
  end

  defp trim_string(nil), do: nil
  defp trim_string(value) when is_binary(value), do: String.trim(value)
  defp trim_string(value), do: value

  defp upcase_currency(nil), do: "USD"
  defp upcase_currency(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp upcase_currency(_), do: "USD"
end
