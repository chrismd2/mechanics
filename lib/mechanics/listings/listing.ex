defmodule Mechanics.Listings.Listing do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mechanics.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "listings" do
    field :title, :string
    field :description, :string
    field :price_cents, :integer
    field :currency, :string

    belongs_to :customer, User

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(title description price_cents currency customer_id)a
  @editable_fields ~w(title description price_cents currency)a

  @doc false
  def create_changeset(listing, attrs) do
    listing
    |> cast(attrs, @required_fields)
    |> validate_listing()
    |> foreign_key_constraint(:customer_id)
  end

  @doc false
  def update_changeset(listing, attrs) do
    listing
    |> cast(attrs, @editable_fields)
    |> validate_required(@editable_fields)
    |> validate_listing()
  end

  defp validate_listing(changeset) do
    changeset
    |> validate_required(@required_fields -- [:customer_id])
    |> validate_number(:price_cents, greater_than_or_equal_to: 0)
    |> validate_length(:currency, min: 3, max: 3)
  end
end
