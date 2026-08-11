defmodule Mechanics.Pricing.VehicleMarketPrice do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User

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

    belongs_to :user, User

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
      :user_id
    ])
    |> validate_required([:make, :model, :year, :miles, :price_cents, :currency, :price_type])
    |> update_change(:make, &trim_string/1)
    |> update_change(:model, &trim_string/1)
    |> update_change(:currency, &upcase_currency/1)
    |> validate_inclusion(:price_type, @valid_price_types)
    |> validate_number(:year, greater_than: 1900, less_than: 2100)
    |> validate_number(:miles, greater_than_or_equal_to: 0)
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_length(:currency, is: 3)
    |> foreign_key_constraint(:user_id)
  end

  defp trim_string(nil), do: nil
  defp trim_string(value) when is_binary(value), do: String.trim(value)
  defp trim_string(value), do: value

  defp upcase_currency(nil), do: "USD"
  defp upcase_currency(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp upcase_currency(_), do: "USD"
end
