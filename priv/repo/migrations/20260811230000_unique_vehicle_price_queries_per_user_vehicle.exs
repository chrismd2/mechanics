defmodule Mechanics.Repo.Migrations.UniqueVehiclePriceQueriesPerUserVehicle do
  use Ecto.Migration

  def up do
    # Keep the newest row per user + vehicle; drop older duplicates so the unique index can apply.
    execute("""
    DELETE FROM vehicle_price_queries
    WHERE id IN (
      SELECT id
      FROM (
        SELECT
          id,
          ROW_NUMBER() OVER (
            PARTITION BY user_id, make, model, year, miles, coalesce(vin, '')
            ORDER BY inserted_at DESC, id DESC
          ) AS rn
        FROM vehicle_price_queries
      ) ranked
      WHERE rn > 1
    )
    """)

    execute("""
    CREATE UNIQUE INDEX vehicle_price_queries_user_vehicle_unique
    ON vehicle_price_queries (user_id, make, model, year, miles, coalesce(vin, ''))
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS vehicle_price_queries_user_vehicle_unique")
  end
end
