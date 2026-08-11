defmodule Mechanics.Repo.Migrations.RemoveUserIdFromVehicleMarketPrices do
  use Ecto.Migration

  def change do
    drop_if_exists index(:vehicle_market_prices, [:user_id])

    alter table(:vehicle_market_prices) do
      remove :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end
  end
end
