defmodule Mechanics.Pricing.ListingCandidate do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(new imported dismissed failed)

  schema "listing_candidates" do
    field :external_id, :string
    field :source_url, :string
    field :title, :string
    field :query, :string
    field :raw, :map, default: %{}
    field :status, :string, default: "new"

    belongs_to :auction_source, Mechanics.Pricing.AuctionSource
    belongs_to :vehicle_market_price, Mechanics.Pricing.VehicleMarketPrice

    timestamps(type: :utc_datetime)
  end

  def changeset(candidate, attrs) do
    candidate
    |> cast(attrs, [
      :auction_source_id,
      :external_id,
      :source_url,
      :title,
      :query,
      :raw,
      :status,
      :vehicle_market_price_id
    ])
    |> validate_required([:source_url, :status])
    |> update_change(:source_url, &trim/1)
    |> update_change(:title, &trim/1)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_format(:source_url, ~r/\Ahttps?:\/\//i, message: "must be an http(s) URL")
    |> unique_constraint(:source_url)
    |> foreign_key_constraint(:auction_source_id)
    |> foreign_key_constraint(:vehicle_market_price_id)
  end

  def valid_statuses, do: @valid_statuses

  defp trim(nil), do: nil
  defp trim(value) when is_binary(value), do: String.trim(value)
end
