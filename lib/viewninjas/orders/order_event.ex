defmodule ViewNinjas.Orders.OrderEvent do
  @moduledoc """
  One append-only line in an order's story (scope.md §6): where it moved from,
  where to, why, and who did it when it was a person.

  The order page's timeline is built from these rows, so support can see exactly
  how an order reached the state it is in.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Orders.Order

  @type t :: %__MODULE__{}

  schema "order_events" do
    belongs_to :order, Order
    belongs_to :actor, User
    field :from_state, :string
    field :to_state, :string
    field :reason, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:order_id, :from_state, :to_state, :reason, :actor_id])
    |> validate_required([:order_id, :to_state])
  end
end
