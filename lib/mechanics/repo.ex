defmodule Mechanics.Repo do
  use Ecto.Repo,
    otp_app: :mechanics,
    adapter: Ecto.Adapters.Postgres
end
