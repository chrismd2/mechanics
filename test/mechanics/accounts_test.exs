defmodule Mechanics.AccountsTest do
  use Mechanics.DataCase, async: false

  import Swoosh.TestAssertions

  alias Mechanics.Accounts

  @valid_attrs %{
    "email" => "user@example.com",
    "name" => "Test User",
    "password" => "secret123",
    "password_confirmation" => "secret123",
    "roles" => ["mechanic"]
  }

  describe "database roles" do
    test "a user can be both mechanic and customer" do
      {:ok, both} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "both@example.com",
            "roles" => ["mechanic", "customer"]
        })

      mechanics = Accounts.list_mechanics()
      customers = Accounts.list_customers()

      assert Enum.any?(mechanics, &(&1.id == both.id))
      assert Enum.any?(customers, &(&1.id == both.id))

      assert "mechanic" in both.roles
      assert "customer" in both.roles
    end

    test "list_mechanics returns only users with role mechanic" do
      {:ok, mechanic} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "m1@example.com",
            "roles" => ["mechanic"]
        })

      {:ok, _customer} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "c1@example.com",
            "roles" => ["customer"]
        })

      mechanics = Accounts.list_mechanics()

      assert length(mechanics) == 1
      assert hd(mechanics).id == mechanic.id
      assert "mechanic" in hd(mechanics).roles
    end

    test "list_customers returns only users with role customer" do
      {:ok, _mechanic} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "m2@example.com",
            "roles" => ["mechanic"]
        })

      {:ok, customer} =
        Accounts.create_user(%{
          @valid_attrs
          | "email" => "c2@example.com",
            "roles" => ["customer"]
        })

      customers = Accounts.list_customers()

      assert length(customers) == 1
      assert hd(customers).id == customer.id
      assert "customer" in hd(customers).roles
    end

    test "list_mechanics orders by inserted_at descending" do
      first_inserted_at = DateTime.utc_now()

      first =
        insert_user!(%{
          email: "old@example.com",
          roles: ["mechanic"],
          inserted_at: first_inserted_at,
          updated_at: first_inserted_at
        })

      second_inserted_at = DateTime.add(first.inserted_at, 1, :second)

      second =
        insert_user!(%{
          email: "new@example.com",
          roles: ["mechanic"],
          inserted_at: second_inserted_at,
          updated_at: second_inserted_at
        })

      mechanics = Accounts.list_mechanics()

      assert length(mechanics) == 2
      assert hd(mechanics).id == second.id
      assert Enum.at(mechanics, 1).id == first.id
    end

    test "list_customers orders by inserted_at descending" do
      first_inserted_at = DateTime.utc_now()

      first =
        insert_user!(%{
          email: "oldc@example.com",
          roles: ["customer"],
          inserted_at: first_inserted_at,
          updated_at: first_inserted_at
        })

      second_inserted_at = DateTime.add(first.inserted_at, 1, :second)

      second =
        insert_user!(%{
          email: "newc@example.com",
          roles: ["customer"],
          inserted_at: second_inserted_at,
          updated_at: second_inserted_at
        })

      customers = Accounts.list_customers()

      assert length(customers) == 2
      assert hd(customers).id == second.id
      assert Enum.at(customers, 1).id == first.id
    end

    test "list_mechanics returns empty when no mechanics exist" do
      assert Accounts.list_mechanics() == []
    end

    test "list_customers returns empty when no customers exist" do
      assert Accounts.list_customers() == []
    end
  end

  describe "password reset throttling" do
    @password "secret123"
    setup :set_swoosh_global

    test "sends email and increments reset count when under limit" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, user} =
        Accounts.create_user(%{
          "email" => "reset1@example.com",
          "name" => "Reset User 1",
          "roles" => ["customer"],
          "password" => @password,
          "password_confirmation" => @password
        })

      assert {:ok, :sent} = Accounts.request_password_reset(user.email, now)

      assert_receive {:email, sent_email}
      assert sent_email.text_body =~ "/password/reset?token="

      [_, token] = Regex.run(~r/token=([^\s]+)/, sent_email.text_body)

      reset_token = Repo.get_by(Mechanics.Accounts.PasswordResetToken, token: token)
      assert reset_token
      assert reset_token.user_id == user.id
      assert reset_token.expires_at == DateTime.add(now, 60 * 60, :second)

      updated = Accounts.get_user_by_email(user.email)
      assert updated.password_reset_count == 1
      assert updated.password_reset_last_sent_at == now
    end

    test "blocks the 4th reset within 6 hours and does not send email" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      last_sent_at = DateTime.add(now, -1, :hour) |> DateTime.truncate(:second)

      {:ok, user} =
        Accounts.create_user(%{
          "email" => "reset2@example.com",
          "name" => "Reset User 2",
          "roles" => ["customer"],
          "password" => @password,
          "password_confirmation" => @password
        })

      Repo.update!(
        Ecto.Changeset.change(user, %{
          password_reset_count: 3,
          password_reset_last_sent_at: last_sent_at
        })
      )

      assert {:ok, :not_sent} = Accounts.request_password_reset(user.email, now)
      refute_email_sent()

      assert Repo.get_by(Mechanics.Accounts.PasswordResetToken, user_id: user.id) == nil

      updated = Accounts.get_user_by_email(user.email)
      assert updated.password_reset_count == 3
      assert updated.password_reset_last_sent_at == last_sent_at
    end

    test "allows a new reset after 6+ hours since last reset" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      last_sent_at = DateTime.add(now, -7, :hour) |> DateTime.truncate(:second)

      {:ok, user} =
        Accounts.create_user(%{
          "email" => "reset3@example.com",
          "name" => "Reset User 3",
          "roles" => ["customer"],
          "password" => @password,
          "password_confirmation" => @password
        })

      Repo.update!(
        Ecto.Changeset.change(user, %{
          password_reset_count: 3,
          password_reset_last_sent_at: last_sent_at
        })
      )

      assert {:ok, :sent} = Accounts.request_password_reset(user.email, now)
      assert_receive {:email, sent_email}
      assert sent_email.text_body =~ "/password/reset?token="

      [_, token] = Regex.run(~r/token=([^\s]+)/, sent_email.text_body)

      reset_token = Repo.get_by(Mechanics.Accounts.PasswordResetToken, token: token)
      assert reset_token
      assert reset_token.user_id == user.id
      assert reset_token.expires_at == DateTime.add(now, 60 * 60, :second)

      updated = Accounts.get_user_by_email(user.email)
      assert updated.password_reset_count == 1
      assert updated.password_reset_last_sent_at == now
    end

    test "clears reset counters on successful sign-in" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, user} =
        Accounts.create_user(%{
          "email" => "reset4@example.com",
          "name" => "Reset User 4",
          "roles" => ["customer"],
          "password" => @password,
          "password_confirmation" => @password
        })

      Repo.update!(
        Ecto.Changeset.change(user, %{
          password_reset_count: 2,
          password_reset_last_sent_at: now
        })
      )

      {:ok, cleared_user} = Accounts.authenticate_user(user.email, @password)
      assert cleared_user.password_reset_count == 0
      assert cleared_user.password_reset_last_sent_at == nil
    end
  end
end
