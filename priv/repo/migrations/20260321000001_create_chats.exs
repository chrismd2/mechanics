defmodule Mechanics.Repo.Migrations.CreateChats do
  use Ecto.Migration

  def change do
    create table(:chats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :topic, :string

      add :mechanic_user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :customer_user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :listing_id, references(:listings, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:chats, [:mechanic_user_id])
    create index(:chats, [:customer_user_id])
    create index(:chats, [:listing_id])

    create unique_index(:chats, [:mechanic_user_id, :customer_user_id],
             name: :chats_private_pm_participant_unique,
             where: "listing_id IS NULL"
           )

    create unique_index(:chats, [:listing_id, :mechanic_user_id],
             name: :chats_listing_mechanic_unique,
             where: "listing_id IS NOT NULL"
           )
  end
end
