defmodule Mechanics.Repo.Migrations.PasswordResetRateLimitFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :password_reset_count, :integer, null: false, default: 0
      add :password_reset_last_sent_at, :utc_datetime
    end
  end
end

