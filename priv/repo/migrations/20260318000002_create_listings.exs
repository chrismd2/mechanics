defmodule Mechanics.Repo.Migrations.CreateListings do
  use Ecto.Migration

  def change do
    create table(:listings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :description, :text, null: false
      add :price_cents, :integer, null: false
      add :currency, :string, null: false
      add :customer_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:listings, [:customer_id])
    create index(:listings, [:inserted_at])
  end
end
