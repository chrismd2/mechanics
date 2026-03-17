# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias Mechanics.Accounts
alias Mechanics.Repo
alias Mechanics.Accounts.User

# Optional: create demo users if none exist
if Repo.aggregate(User, :count, :id) == 0 and System.get_env("ENV") != "prod" do
  {:ok, _} = Accounts.create_user(%{
    email: "mechanic@example.com",
    name: "Demo Mechanic",
    role: "mechanic",
    password: "password123",
    password_confirmation: "password123"
  })

  {:ok, _} = Accounts.create_user(%{
    email: "customer@example.com",
    name: "Demo Customer",
    role: "customer",
    password: "password123",
    password_confirmation: "password123"
  })
end
