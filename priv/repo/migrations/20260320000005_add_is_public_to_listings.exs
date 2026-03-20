defmodule Mechanics.Repo.Migrations.AddIsPublicToListings do
  use Ecto.Migration

  def change do
    alter table(:listings) do
      add :is_public, :boolean, null: false, default: false
    end

    create index(:listings, [:is_public, :inserted_at])
  end
end

