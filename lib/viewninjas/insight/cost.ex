defmodule ViewNinjas.Insight.Cost do
  @moduledoc """
  A cost that belongs to no customer (scope.md §6, §10): hosting, a domain,
  anything else the shop pays for. SMS and the payment fee already live on their
  own rows, so they are derived, never re-entered here.

  Append-only-ish: a wrong line is corrected by adding another, and the P&L reads
  every row in the period.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User

  @type t :: %__MODULE__{}

  @kinds ~w(hosting domain other)a

  schema "costs" do
    belongs_to :actor, User

    field :kind, Ecto.Enum, values: @kinds
    field :amount_cents, :integer
    field :incurred_on, :date
    field :note, :string

    timestamps(type: :utc_datetime)
  end

  @doc "The kinds of cost the shop records."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  def changeset(cost, attrs) do
    cost
    |> cast(attrs, [:kind, :amount_cents, :incurred_on, :note, :actor_id])
    |> validate_required([:kind, :amount_cents, :incurred_on])
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:actor_id)
  end
end
