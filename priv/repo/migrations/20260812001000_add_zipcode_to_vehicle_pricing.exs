defmodule Mechanics.Repo.Migrations.AddZipcodeToVehiclePricing do
  use Ecto.Migration

  def up do
    alter table(:vehicle_market_prices) do
      add :zipcode, :string, null: false, default: "00000"
    end

    alter table(:vehicle_price_queries) do
      add :zipcode, :string, null: false, default: "00000"
    end

    execute("UPDATE vehicle_market_prices SET zipcode = '00000' WHERE zipcode IS NULL OR zipcode = ''")
    execute("UPDATE vehicle_price_queries SET zipcode = '00000' WHERE zipcode IS NULL OR zipcode = ''")

    execute("DROP INDEX IF EXISTS vehicle_price_queries_user_vehicle_unique")

    execute("""
    CREATE UNIQUE INDEX vehicle_price_queries_user_vehicle_unique
    ON vehicle_price_queries (user_id, make, model, year, miles, coalesce(vin, ''), zipcode)
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS vehicle_price_queries_user_vehicle_unique")

    execute("""
    CREATE UNIQUE INDEX vehicle_price_queries_user_vehicle_unique
    ON vehicle_price_queries (user_id, make, model, year, miles, coalesce(vin, ''))
    """)

    alter table(:vehicle_price_queries) do
      remove :zipcode
    end

    alter table(:vehicle_market_prices) do
      remove :zipcode
    end
  end
end
