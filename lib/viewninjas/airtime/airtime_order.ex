defmodule ViewNinjas.Airtime.AirtimeOrder do
  @moduledoc """
  One airtime top-up to one number (scope: `docs/instalipa-airtime.md` §5–§6).

  Unlike a social order there is no lane, grade or quantity: it is a phone and a
  shilling amount, and the rail's discount is the margin. The state machine is the
  order's, in airtime's words — `delivered`, not `completed`, and `refunded` means
  the wallet was credited back.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Airtime.AirtimeEvent

  @type t :: %__MODULE__{}

  @states ~w(awaiting_payment abandoned paid sending submitted needs_review
             delivered failed refunded)a

  # Nothing moves on its own once an airtime order is here.
  @terminal_states ~w(delivered refunded abandoned)a

  # Money has been taken and the airtime is not yet delivered.
  @open_states ~w(paid sending submitted needs_review)a

  # The states worth asking the rail about.
  @pollable_states ~w(submitted)a

  schema "airtime_orders" do
    belongs_to :user, User
    has_many :events, AirtimeEvent

    field :batch_id, :string
    field :phone, :string
    field :amount_cents, :integer
    field :state, Ecto.Enum, values: @states, default: :awaiting_payment
    field :reference, :string
    field :idempotency_key, :string
    field :instalipa_id, :string
    field :instalipa_status, :string
    field :discount_cents, :integer
    field :float_cents, :integer
    field :receipt, :string
    field :failure_kind, :string
    field :failure_message, :string

    timestamps(type: :utc_datetime)
  end

  @doc "Every state an airtime order can hold."
  @spec states() :: [atom()]
  def states, do: @states

  @doc "The states an airtime order never leaves on its own."
  @spec terminal_states() :: [atom()]
  def terminal_states, do: @terminal_states

  @doc "The states where money has been taken and the airtime is still owed."
  @spec open_states() :: [atom()]
  def open_states, do: @open_states

  @doc "The states the confirming job asks the rail about."
  @spec pollable_states() :: [atom()]
  def pollable_states, do: @pollable_states

  @doc "Whether the airtime order has finished; nothing more happens without a person."
  @spec terminal?(t() | atom()) :: boolean()
  def terminal?(%__MODULE__{state: state}), do: terminal?(state)
  def terminal?(state), do: state in @terminal_states

  @doc "Whether money has been taken and the airtime is still owed."
  @spec open?(t() | atom()) :: boolean()
  def open?(%__MODULE__{state: state}), do: open?(state)
  def open?(state), do: state in @open_states

  @doc "A changeset for the fields a caller may set directly."
  def changeset(airtime_order, attrs) do
    airtime_order
    |> cast(attrs, [
      :user_id,
      :batch_id,
      :phone,
      :amount_cents,
      :state,
      :reference,
      :idempotency_key,
      :instalipa_id,
      :instalipa_status,
      :discount_cents,
      :float_cents,
      :receipt,
      :failure_kind,
      :failure_message
    ])
    |> validate_required([:user_id, :phone, :amount_cents, :reference, :idempotency_key])
    |> validate_number(:amount_cents, greater_than: 0)
    |> unique_constraint(:reference)
    |> unique_constraint(:idempotency_key)
    |> unique_constraint(:instalipa_id)
    |> foreign_key_constraint(:user_id)
  end
end
