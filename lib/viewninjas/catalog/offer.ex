defmodule ViewNinjas.Catalog.Offer do
  @moduledoc """
  What a customer browses (scope.md §6): a platform plus an outcome, with a
  buyer-facing title. Example: `instagram` + `followers` →
  "Instagram followers".

  An offer is only shown to buyers when it is published *and* carries at least
  one published lane; the market does that filtering, not this row.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Catalog.Lane

  @type t :: %__MODULE__{}

  schema "offers" do
    field :platform, :string
    field :outcome, :string
    field :title, :string
    field :description, :string
    field :sort, :integer, default: 0
    field :published, :boolean, default: false

    has_many :lanes, Lane

    timestamps(type: :utc_datetime)
  end

  def changeset(offer, attrs) do
    offer
    |> cast(attrs, [:platform, :outcome, :title, :description, :sort, :published])
    |> validate_required([:platform, :outcome, :title])
    |> validate_format(:platform, ~r/^[a-z0-9_]+$/, message: "must be lowercase letters or _")
    |> validate_format(:outcome, ~r/^[a-z0-9_]+$/, message: "must be lowercase letters or _")
    |> validate_length(:title, max: 80)
    |> unique_constraint([:platform, :outcome])
  end
end
