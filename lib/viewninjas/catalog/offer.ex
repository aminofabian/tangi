defmodule ViewNinjas.Catalog.Offer do
  @moduledoc """
  What a customer browses (scope.md §6): a platform, an outcome, and — where it
  is needed to tell two products apart — the thing the customer's link points at.

  Example: `instagram` + `followers` → "Instagram followers". But Facebook sells
  page likes and post likes as different services, and those are `facebook` +
  `likes` + `page` and `facebook` + `likes` + `post`: same platform, same outcome,
  different product. `ViewNinjas.Catalog.Target` owns that third dimension.

  An offer is only shown to buyers when it is published *and* carries at least
  one published lane; the market does that filtering, not this row.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Catalog.Lane
  alias ViewNinjas.Catalog.Target

  @type t :: %__MODULE__{}

  schema "offers" do
    field :platform, :string
    field :outcome, :string
    # What the link points at — "page", "post", "reel" and so on. Empty when the
    # platform and outcome already say enough on their own.
    field :target, :string, default: ""
    field :title, :string
    field :description, :string
    field :sort, :integer, default: 0
    field :published, :boolean, default: false

    has_many :lanes, Lane

    timestamps(type: :utc_datetime)
  end

  def changeset(offer, attrs) do
    offer
    |> cast(attrs, [:platform, :outcome, :target, :title, :description, :sort, :published])
    |> validate_required([:platform, :outcome, :title])
    |> validate_format(:platform, ~r/^[a-z0-9_]+$/, message: "must be lowercase letters or _")
    |> validate_format(:outcome, ~r/^[a-z0-9_]+$/, message: "must be lowercase letters or _")
    |> validate_target()
    |> validate_length(:title, max: 80)
    |> unique_constraint([:platform, :outcome, :target])
  end

  # An empty target is the common case and always allowed; anything else has to be
  # a target the back office knows, so the shop never renders a word nobody chose.
  defp validate_target(changeset) do
    case get_field(changeset, :target) do
      target when target in [nil, ""] ->
        put_change(changeset, :target, "")

      target ->
        if Target.valid?(target) do
          changeset
        else
          add_error(changeset, :target, "is not a known target")
        end
    end
  end
end
