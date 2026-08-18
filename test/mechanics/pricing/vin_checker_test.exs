defmodule Mechanics.Pricing.VinCheckerTest do
  use Mechanics.DataCase, async: true

  alias Mechanics.Pricing
  alias Mechanics.Pricing.VinChecker

  test "normalize uppercases and strips spaces" do
    assert VinChecker.normalize(" 1hg cm82633a004352 ") == "1HGCM82633A004352"
  end

  test "valid_vin?/1 requires 17 chars without I/O/Q" do
    assert VinChecker.valid_vin?("1HGCM82633A004352")
    refute VinChecker.valid_vin?("SHORT")
    refute VinChecker.valid_vin?("1HGCM82633A00435I")
  end

  test "check/2 uses market price when VIN matches" do
    user = pricing_user!()
    vin = "1HGCM82633A111111"

    {:ok, _} =
      Pricing.create_market_price(user, %{
        "make" => "Honda",
        "model" => "Accord",
        "year" => 2003,
        "miles" => 120_000,
        "price_cents" => 500_000,
        "price_type" => "sale",
        "vin" => vin,
        "source_url" => "https://example.com/vin-check-#{System.unique_integer([:positive])}"
      })

    assert {:ok, attrs} = VinChecker.check(vin)
    assert attrs["make"] == "Honda"
    assert attrs["model"] == "Accord"
    assert attrs["year"] == 2003
    assert attrs["miles"] == 120_000
  end

  test "check/2 uses injectable http client for NHTSA fallback" do
    vin = "1HGCM82633A222222"

    http = fn _url ->
      body =
        Jason.encode!(%{
          "Results" => [
            %{
              "Make" => "Honda",
              "Model" => "Accord",
              "ModelYear" => "2003"
            }
          ]
        })

      {:ok, %{status: 200, body: body}}
    end

    assert {:ok, attrs} = VinChecker.check(vin, http_client: http)
    assert attrs["make"] == "Honda"
    assert attrs["model"] == "Accord"
    assert attrs["year"] == 2003
    refute Map.has_key?(attrs, "miles")
  end

  defp pricing_user! do
    suffix = System.unique_integer([:positive])

    {:ok, user} =
      Mechanics.Accounts.create_user(%{
        "email" => "vin-check-#{suffix}@example.com",
        "name" => "VIN Check User",
        "roles" => ["customer", "pricing_user"],
        "password" => "securepw123",
        "password_confirmation" => "securepw123"
      })

    user
  end
end
