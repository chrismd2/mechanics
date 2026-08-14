defmodule Mechanics.Pricing.AuctionSource do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_kinds ~w(unknown bidwrangler royal craigslist)

  schema "auction_sources" do
    field :kind, :string, default: "unknown"
    field :base_url, :string
    field :label, :string
    field :enabled, :boolean, default: true
    field :config, :map, default: %{}
    field :last_crawled_at, :utc_datetime

    has_many :listing_candidates, Mechanics.Pricing.ListingCandidate

    timestamps(type: :utc_datetime)
  end

  def changeset(source, attrs) do
    source
    |> cast(attrs, [:kind, :base_url, :label, :enabled, :config, :last_crawled_at])
    |> validate_required([:kind, :base_url, :label])
    |> update_change(:base_url, &normalize_base_url/1)
    |> update_change(:label, &trim/1)
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_format(:base_url, ~r/\Ahttps?:\/\/[^\/]+\/?\z/i, message: "must be an http(s) origin")
    |> unique_constraint(:base_url)
  end

  def valid_kinds, do: @valid_kinds

  defp normalize_base_url(nil), do: nil

  defp normalize_base_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.replace_trailing("/", "")
  end

  defp trim(nil), do: nil
  defp trim(value) when is_binary(value), do: String.trim(value)
end
