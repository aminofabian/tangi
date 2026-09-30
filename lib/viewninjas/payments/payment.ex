defmodule ViewNinjas.Payments.Payment do
  @moduledoc """
  One Malipo Connect attempt (scope.md §6, §8).

  A payment is `pending` until a confirming `GET` says otherwise, and then
  `settled` or `failed` — both terminal. A retry is a **new** row with a new
  idempotency key; the old row is kept. `malipo_payment_id` stays null until
  Malipo has answered, and a `topup` payment has no order.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Orders.Order

  @type t :: %__MODULE__{}

  @purposes ~w(order topup)a
  @statuses ~w(pending settled failed)a

  schema "payments" do
    belongs_to :user, User
    belongs_to :order, Order

    field :purpose, Ecto.Enum, values: @purposes
    field :amount_cents, :integer
    field :malipo_payment_id, :string
    field :idempotency_key, :string
    field :status, Ecto.Enum, values: @statuses, default: :pending
    field :receipt, :string
    field :failure_kind, :string
    field :failure_message, :string
    # What the money cost to collect, reconciled from the settlement statement.
    # Null until a statement names it — never assumed (scope.md §10).
    field :fee_cents, :integer

    timestamps(type: :utc_datetime)
  end

  @doc "The flows a payment can serve."
  @spec purposes() :: [atom()]
  def purposes, do: @purposes

  @doc "The statuses a payment can hold; all but `pending` are terminal."
  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  @doc "Whether the payment has stopped changing."
  @spec terminal?(t() | atom()) :: boolean()
  def terminal?(%__MODULE__{status: status}), do: terminal?(status)
  def terminal?(:settled), do: true
  def terminal?(:failed), do: true
  def terminal?(_), do: false

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :user_id,
      :order_id,
      :purpose,
      :amount_cents,
      :malipo_payment_id,
      :idempotency_key,
      :status,
      :receipt,
      :failure_kind,
      :failure_message,
      :fee_cents
    ])
    |> validate_required([:user_id, :purpose, :amount_cents, :idempotency_key])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_length(:idempotency_key, min: 8, max: 191)
    |> unique_constraint(:idempotency_key)
    |> unique_constraint(:malipo_payment_id)
    |> foreign_key_constraint(:order_id)
  end
end
