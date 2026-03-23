defmodule Mechanics.Disclaimers.DisclaimerText do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "disclaimer_texts" do
    field :disclaimer_type, :string
    field :text, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(disclaimer_type text)a

  @doc false
  def changeset(%__MODULE__{} = disclaimer_text, attrs \\ %{}) do
    disclaimer_text
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
  end
end

