defmodule ViewNinjas.Orders.Refill do
  @moduledoc """
  One refill attempt for a completed order (scope.md §6, §10).

  A lane sold with `refill: true` earns the customer one refill. There is at most
  one row per order — the database enforces it — because "Rejected stays rejected
  and does not automatically open a second refill" (scope.md §10).

  `requested` is the row as it is created, before the one supplier call has
  answered; `supplier_refill_id` is filled in when it does. `completed` and
  `rejected` are terminal.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Orders.Order

  @type t :: %__MODULE__{}

  @states ~w(requested completed rejected)a

  schema "refills" do
    belongs_to :order, Order

    field :supplier_refill_id, :string
    field :state, Ecto.Enum, values: @states, default: :requested
    field :reason, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Every state a refill can hold."
  @spec states() :: [atom()]
  def states, do: @states

  @doc "Whether nothing more happens on its own."
  @spec terminal?(t() | atom()) :: boolean()
  def terminal?(%__MODULE__{state: state}), do: terminal?(state)
  def terminal?(state), do: state in [:completed, :rejected]

  @doc """
  Maps the panel's refill word onto our state, or nil to keep the one we have
  (scope.md §10). A panel that says anything other than Completed or Rejected is
  still working.
  """
  @spec status_from(String.t() | nil) :: atom() | nil
  def status_from(raw) when is_binary(raw) do
    case raw |> String.trim() |> String.downcase() do
      "completed" -> :completed
      "complete" -> :completed
      "rejected" -> :rejected
      "reject" -> :rejected
      _ -> nil
    end
  end

  def status_from(_raw), do: nil

  def changeset(refill, attrs) do
    refill
    |> cast(attrs, [:order_id, :supplier_refill_id, :state, :reason])
    |> validate_required([:order_id, :state])
    |> foreign_key_constraint(:order_id)
    |> unique_constraint(:order_id)
  end
end
