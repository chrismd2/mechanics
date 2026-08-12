defmodule Mechanics.Pricing.VehiclePriceQuery do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @default_zipcode "00000"

  schema "vehicle_price_queries" do
    field :vin, :string
    field :make, :string
    field :model, :string
    field :year, :integer
    field :miles, :integer
    field :zipcode, :string, default: @default_zipcode
    field :suggested_competitive_cents, :integer
    field :suggested_minimum_cents, :integer
    field :currency, :string, default: "USD"
    field :match_count, :integer, default: 0
    field :agent_summary, :string
    field :dismissed_similar_ids, {:array, :binary_id}, default: []

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
      :zipcode,
      :suggested_competitive_cents,
      :suggested_minimum_cents,
      :currency,
      :match_count,
      :agent_summary,
      :dismissed_similar_ids,
      :user_id
    ])
    |> maybe_default_zipcode()
    |> maybe_default_dismissed_similar_ids()
    |> validate_required([:make, :model, :year, :miles, :zipcode, :currency, :match_count])
    |> update_change(:make, &trim_string/1)
    |> update_change(:model, &trim_string/1)
    |> update_change(:zipcode, &normalize_zipcode/1)
    |> update_change(:currency, &upcase_currency/1)
    |> validate_number(:year, greater_than_or_equal_to: 0, less_than: 2100)
    |> validate_change(:year, fn :year, year ->
      if year == 0 or year > 1900 do
        []
      else
        [year: "must be blank or a real model year"]
      end
    end)
    |> validate_number(:miles, greater_than_or_equal_to: 0)
    |> validate_number(:match_count, greater_than_or_equal_to: 0)
    |> validate_length(:currency, is: 3)
    |> validate_format(:zipcode, ~r/\A\d{5}(-\d{4})?\z/, message: "must be a 5-digit ZIP or ZIP+4")
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id, name: :vehicle_price_queries_user_vehicle_unique)
  end

  defp maybe_default_dismissed_similar_ids(changeset) do
    case get_field(changeset, :dismissed_similar_ids) do
      nil -> put_change(changeset, :dismissed_similar_ids, [])
      _ -> changeset
    end
  end

  defp maybe_default_zipcode(changeset) do
    case get_field(changeset, :zipcode) do
      zip when zip in [nil, ""] -> put_change(changeset, :zipcode, @default_zipcode)
      _ -> changeset
    end
  end

  defp normalize_zipcode(nil), do: @default_zipcode
  defp normalize_zipcode(""), do: @default_zipcode
  defp normalize_zipcode(value) when is_binary(value), do: String.trim(value)
  defp normalize_zipcode(value), do: value

  defp trim_string(nil), do: nil
  defp trim_string(value) when is_binary(value), do: String.trim(value)
  defp trim_string(value), do: value

  defp upcase_currency(nil), do: "USD"
  defp upcase_currency(value) when is_binary(value), do: value |> String.trim() |> String.upcase()
  defp upcase_currency(_), do: "USD"
end
