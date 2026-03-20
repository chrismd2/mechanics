defmodule Mechanics.Repo.Migrations.ForceProfilesUserOnlySchema do
  use Ecto.Migration

  def up do
    create_if_not_exists table(:profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :headline, :string, null: false
      add :bio, :text, null: false
      add :city, :string, null: false
      add :state, :string, null: false
      add :is_public, :boolean, null: false, default: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    execute("DROP INDEX IF EXISTS profiles_customer_id_index", "")
    execute("ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_customer_id_fkey", "")
    execute("ALTER TABLE profiles DROP COLUMN IF EXISTS customer_id", "")

    create_if_not_exists unique_index(:profiles, [:user_id])
    create_if_not_exists index(:profiles, [:is_public, :inserted_at])
  end

  def down do
    :ok
  end
end
