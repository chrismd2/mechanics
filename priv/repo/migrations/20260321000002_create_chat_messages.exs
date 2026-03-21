defmodule Mechanics.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false

      add :chat_id,
          references(:chats, type: :binary_id, on_delete: :delete_all),
          null: false

      add :sender_user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:chat_messages, [:chat_id])
    create index(:chat_messages, [:sender_user_id])
  end
end
