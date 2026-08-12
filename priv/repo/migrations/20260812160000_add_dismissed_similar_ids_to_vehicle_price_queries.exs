defmodule Mechanics.Repo.Migrations.AddDismissedSimilarIdsToVehiclePriceQueries do
  use Ecto.Migration

  def change do
    alter table(:vehicle_price_queries) do
      add :dismissed_similar_ids, {:array, :binary_id}, null: false, default: []
    end
  end
end
