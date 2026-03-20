defmodule Mechanics.Repo.Migrations.UsersRoleToRoles do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :roles, {:array, :string}, null: false, default: []
    end

    # Backfill: mechanic -> ["customer", "mechanic"], customer -> ["customer"]
    execute """
    UPDATE users
    SET roles = CASE
      WHEN role = 'mechanic' THEN ARRAY['customer', 'mechanic']::varchar[]
      ELSE ARRAY['customer']::varchar[]
    END
    """,
    ""

    drop index(:users, [:role])

    alter table(:users) do
      remove :role
    end
  end
end
