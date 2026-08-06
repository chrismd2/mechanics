defmodule Mechanics.Repo.Migrations.CreateInvites do
  use Ecto.Migration

  def change do
    create table(:invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :subject_type, :string, null: false
      add :chat_id, references(:chats, type: :binary_id, on_delete: :delete_all)
      add :listing_id, references(:listings, type: :binary_id, on_delete: :delete_all)
      add :mechanic_user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :inviter_user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :accepted_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :expires_at, :utc_datetime, null: false
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invites, [:token])
    create index(:invites, [:inviter_user_id])
    create index(:invites, [:chat_id])
    create index(:invites, [:listing_id])
    create index(:invites, [:mechanic_user_id])
  end
end
