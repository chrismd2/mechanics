defmodule Mechanics.Repo.Migrations.CreateUserDisclaimerAgreements do
  use Ecto.Migration

  def change do
    create table(:user_disclaimer_agreements, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :disclaimer_text_id,
          references(:disclaimer_texts, type: :binary_id, on_delete: :delete_all),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:user_disclaimer_agreements, [:user_id])
    create index(:user_disclaimer_agreements, [:disclaimer_text_id])
  end
end

