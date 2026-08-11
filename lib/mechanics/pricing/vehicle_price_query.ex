defmodule Mechanics.Pricing.VehiclePriceQuery do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "vehicle_price_queries" do
    field :vin, :string
    field :make, :string
    field :model, :string
    field :year, :integer
    field :miles, :integer
    field :suggested_competitive_cents, :integer
    field :suggested_minimum_cents, :integer
    field :currency, :string, default: "USD"
    field :match_count, :integer, default: 0
    field :agent_summary, :string

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  def changeset(query, attrs) do
    query
    |> cast(attrs, [
      :vin,
      :make,
      :model,
      :year,
      :miles,
      :suggested_competitive_cents,
      :suggested_minimum_cents,
      :currency,
      :match_count,
      :agent_summary,
      :user_id
    ])
    |> validate_required([:make, :model, :year, :miles, :currency, :match_count])
    |> update_change(:make, &trim_string/1)
    |> update_change(:model, &trim_string/1)
    |> update_change(:currency, &upcase_currency/1)
    |> validate_number(:year, greater_than: 1900, less_than: 2100)
    |> validate_number(:miles, greater_than_or_equal_to: 0)
    |> validate_number(:match_count, greater_than_or_equal_to: 0)
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
