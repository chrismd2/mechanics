defmodule Mechanics.Repo.Migrations.ConvertUsersToBinaryIds do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "")

    execute("""
    ALTER TABLE users
    ADD COLUMN uuid_id uuid DEFAULT gen_random_uuid() NOT NULL
    """)

    execute("ALTER TABLE users DROP CONSTRAINT users_pkey", "")
    execute("ALTER TABLE users RENAME COLUMN id TO legacy_id", "")
    execute("ALTER TABLE users RENAME COLUMN uuid_id TO id", "")
    execute("ALTER TABLE users ADD PRIMARY KEY (id)", "")
    execute("ALTER TABLE users DROP COLUMN legacy_id", "")
    execute("DROP SEQUENCE IF EXISTS users_id_seq", "")
  end

  def down do
    execute("CREATE SEQUENCE IF NOT EXISTS users_id_seq", "")

    execute("""
    ALTER TABLE users
    ADD COLUMN integer_id bigint DEFAULT nextval('users_id_seq') NOT NULL
    """)

    execute("ALTER TABLE users DROP CONSTRAINT users_pkey", "")
    execute("ALTER TABLE users RENAME COLUMN id TO uuid_id", "")
    execute("ALTER TABLE users RENAME COLUMN integer_id TO id", "")
    execute("ALTER TABLE users ALTER COLUMN id SET DEFAULT nextval('users_id_seq')", "")
    execute("ALTER SEQUENCE users_id_seq OWNED BY users.id", "")
    execute("ALTER TABLE users ADD PRIMARY KEY (id)", "")
    execute("ALTER TABLE users DROP COLUMN uuid_id", "")
  end
end
