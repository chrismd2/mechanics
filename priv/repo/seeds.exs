# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
alias Mechanics.Accounts
alias Mechanics.Pricing
alias Mechanics.Repo
alias Mechanics.Accounts.User

# Optional: create demo users if none exist
# if Repo.aggregate(User, :count, :id) == 0 and System.get_env("ENV") != "prod" do
#   {:ok, _} = Accounts.create_user(%{
#     email: "mechanic@example.com",
#     name: "Demo Mechanic",
#     role: "mechanic",
#     password: "password123",
#     password_confirmation: "password123"
#   })
#
#   {:ok, _} = Accounts.create_user(%{
#     email: "customer@example.com",
#     name: "Demo Customer",
#     role: "customer",
#     password: "password123",
#     password_confirmation: "password123"
#   })
# end

if System.get_env("ENV") != "prod" do
  pricing_user =
    case Accounts.get_user_by_email("pricing@example.com") do
      %User{} = user ->
        {:ok, user} = Accounts.add_pricing_user_role(user)
        user

      nil ->
        {:ok, user} =
          Accounts.create_user(%{
            "email" => "pricing@example.com",
            "name" => "Demo Pricing User",
            "roles" => ["customer", "pricing_user"],
            "password" => "password123",
            "password_confirmation" => "password123"
          })

        user
        |> Ecto.Changeset.change(email_verified: true)
        |> Repo.update!()
    end

  if Pricing.list_market_prices(%{make: "Toyota", model: "Camry"}) == [] do
    Enum.each(
      [
        {"listing", 1_950_000, 42_000},
        {"listing", 1_880_000, 48_000},
        {"sale", 1_720_000, 45_000},
        {"sale", 1_650_000, 51_000}
      ],
      fn {price_type, price_cents, miles} ->
        {:ok, _} =
          Pricing.create_market_price(pricing_user, %{
            "make" => "Toyota",
            "model" => "Camry",
            "year" => 2019,
            "miles" => miles,
            "price_cents" => price_cents,
            "currency" => "USD",
            "price_type" => price_type,
            "source_url" => "https://example.com/seed/camry-#{price_type}-#{miles}"
          })
      end
    )
  end
end
