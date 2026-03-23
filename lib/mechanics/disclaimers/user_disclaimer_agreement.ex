defmodule Mechanics.Disclaimers.UserDisclaimerAgreement do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_disclaimer_agreements" do
    belongs_to :user, User
    belongs_to :disclaimer_text, Mechanics.Disclaimers.DisclaimerText

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(user_id disclaimer_text_id)a

  @doc false
  def changeset(%__MODULE__{} = agreement, attrs \\ %{}) do
    agreement
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:disclaimer_text_id)
  end
end

