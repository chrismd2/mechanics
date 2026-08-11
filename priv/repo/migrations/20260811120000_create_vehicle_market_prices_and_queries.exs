defmodule Mechanics.Repo.Migrations.CreateVehicleMarketPricesAndQueries do
  use Ecto.Migration

  def change do
    create table(:vehicle_market_prices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vin, :string
      add :make, :string, null: false
      add :model, :string, null: false
      add :year, :integer, null: false
      add :miles, :integer, null: false
      add :price_cents, :integer, null: false
      add :currency, :string, null: false, default: "USD"
      add :price_type, :string, null: false
      add :notes, :text
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:vehicle_market_prices, [:make, :model, :year])
    create index(:vehicle_market_prices, [:price_type])
    create index(:vehicle_market_prices, [:user_id])

    create table(:vehicle_price_queries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :vin, :string
      add :make, :string, null: false
      add :model, :string, null: false
      add :year, :integer, null: false
      add :miles, :integer, null: false
      add :suggested_competitive_cents, :integer
      add :suggested_minimum_cents, :integer
      add :currency, :string, null: false, default: "USD"
      add :match_count, :integer, null: false, default: 0
      add :agent_summary, :text
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:vehicle_price_queries, [:user_id])
    create index(:vehicle_price_queries, [:make, :model, :year])
  end
end
