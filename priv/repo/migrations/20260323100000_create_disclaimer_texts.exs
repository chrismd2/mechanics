defmodule Mechanics.Repo.Migrations.CreateDisclaimerTexts do
  use Ecto.Migration

  def change do
    create table(:disclaimer_texts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :disclaimer_type, :string, null: false
      add :text, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(
             :disclaimer_texts,
             [:disclaimer_type, :text],
             name: :disclaimer_texts_type_text_unique
           )

    create index(:disclaimer_texts, [:disclaimer_type])
  end
end

