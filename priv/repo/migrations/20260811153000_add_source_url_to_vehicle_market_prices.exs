defmodule Mechanics.Repo.Migrations.AddSourceUrlToVehicleMarketPrices do
  use Ecto.Migration

  def change do
    alter table(:vehicle_market_prices) do
      add :source_url, :text
    end

    create unique_index(:vehicle_market_prices, [:source_url],
      where: "source_url IS NOT NULL",
      name: :vehicle_market_prices_source_url_index
    )
  end
end
