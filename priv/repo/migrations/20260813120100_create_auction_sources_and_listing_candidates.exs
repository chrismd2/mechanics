defmodule Mechanics.Repo.Migrations.CreateAuctionSourcesAndListingCandidates do
  use Ecto.Migration

  def change do
    create table(:auction_sources, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :base_url, :string, null: false
      add :label, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :config, :map, null: false, default: %{}
      add :last_crawled_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:auction_sources, [:base_url])
    create index(:auction_sources, [:kind])
    create index(:auction_sources, [:enabled])

    create table(:listing_candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :auction_source_id, references(:auction_sources, type: :binary_id, on_delete: :nilify_all)
      add :external_id, :string
      add :source_url, :string, null: false
      add :title, :string
      add :query, :string
      add :raw, :map, null: false, default: %{}
      add :status, :string, null: false, default: "new"
      add :vehicle_market_price_id,
          references(:vehicle_market_prices, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:listing_candidates, [:source_url])
    create index(:listing_candidates, [:status])
    create index(:listing_candidates, [:auction_source_id])
    create index(:listing_candidates, [:query])
  end
end
