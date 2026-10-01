defmodule ViewNinjas.Wallet.LedgerEntry do
  @moduledoc """
  One append-only line in the wallet (scope.md §6). The balance is the sum of
  these rows, never a column someone updates in place, and a correction is a new
  entry — never an edit.

  `amount_cents` is signed: negative is a debit from the wallet. `reason` is one
  of the reasons the scope names; `payment_id`, `order_id`, `airtime_order_id` and
  `actor_id` record what caused it, and `actor_id` is null when the system wrote it.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Airtime.AirtimeOrder
  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Payments.Payment

  @type t :: %__MODULE__{}

  @reasons ~w(topup order_hold order_capture refund adjustment airtime airtime_refund)a

  schema "ledger_entries" do
    belongs_to :user, User
    belongs_to :payment, Payment
    belongs_to :order, Order
    belongs_to :airtime_order, AirtimeOrder
    belongs_to :actor, User

    field :amount_cents, :integer
    field :reason, Ecto.Enum, values: @reasons

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The reasons a ledger entry can carry."
  @spec reasons() :: [atom()]
  def reasons, do: @reasons

  @doc "The label shown to a customer for a reason."
  @spec label(atom() | String.t()) :: String.t()
  def label(:topup), do: "Top-up"
  def label(:order_hold), do: "Order hold"
  def label(:order_capture), do: "Order"
  def label(:refund), do: "Refund"
  def label(:adjustment), do: "Adjustment"
  def label(:airtime), do: "Airtime"
  def label(:airtime_refund), do: "Airtime refund"
  def label(other), do: to_string(other)

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [
      :user_id,
      :amount_cents,
      :reason,
      :payment_id,
      :order_id,
      :airtime_order_id,
      :actor_id
    ])
    |> validate_required([:user_id, :amount_cents, :reason])
    |> validate_number(:amount_cents, not_equal_to: 0)
    |> foreign_key_constraint(:user_id)
  end
end
