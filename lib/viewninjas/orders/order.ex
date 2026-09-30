defmodule ViewNinjas.Orders.Order do
  @moduledoc """
  One purchase: a lane, a link, a quantity, and the price frozen at the moment of
  payment (scope.md §6, §7).

  The margin, buffer, retail and FX the order was priced with are copied in and
  never recomputed, so a later change to the knobs or to the pinned service does
  not move a price a customer already paid. The supplier columns stay null until
  the order is placed (M8).
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Catalog.Lane
  alias ViewNinjas.Orders.OrderEvent
  alias ViewNinjas.Pricing.FxRate
  alias ViewNinjas.Suppliers.{Supplier, SupplierService}

  @type t :: %__MODULE__{}

  @states ~w(awaiting_payment abandoned paid placing placed failed needs_review
             in_progress completed partial canceled refunded)a

  # No further movement happens on its own once an order is here.
  @terminal_states ~w(completed refunded canceled abandoned)a

  # Money has been taken; the supplier still owes the work.
  @open_states ~w(paid placing placed needs_review in_progress partial)a

  # The states worth asking the panel about: placed, and moving.
  @pollable_states ~w(placed in_progress partial)a

  schema "orders" do
    belongs_to :user, User
    belongs_to :lane, Lane
    belongs_to :fx_rate, FxRate
    belongs_to :supplier, Supplier
    belongs_to :supplier_service, SupplierService

    has_many :events, OrderEvent, foreign_key: :order_id

    field :link, :string
    field :quantity, :integer
    field :retail_cents, :integer
    field :cost_usd_micros, :integer
    field :margin_bps, :integer
    field :buffer_bps, :integer
    field :supplier_order_id, :string
    field :state, Ecto.Enum, values: @states, default: :awaiting_payment

    # What the panel reports back after placement (scope.md §10).
    field :supplier_status, :string
    field :start_count, :integer
    field :remains, :integer
    field :charge_usd_micros, :integer
    field :currency, :string, default: "USD"

    timestamps(type: :utc_datetime)
  end

  @doc "Every state an order can hold."
  @spec states() :: [atom()]
  def states, do: @states

  @doc "The states an order never leaves on its own."
  @spec terminal_states() :: [atom()]
  def terminal_states, do: @terminal_states

  @doc "The states where money has been taken and work is still owed."
  @spec open_states() :: [atom()]
  def open_states, do: @open_states

  @doc "The states the status batch asks the panel about (scope.md §10)."
  @spec pollable_states() :: [atom()]
  def pollable_states, do: @pollable_states

  @doc "Whether the order has finished; nothing more happens without a person."
  @spec terminal?(t() | atom()) :: boolean()
  def terminal?(%__MODULE__{state: state}), do: terminal?(state)
  def terminal?(state), do: state in @terminal_states

  @doc "Whether money has been taken and the work is still owed."
  @spec open?(t() | atom()) :: boolean()
  def open?(%__MODULE__{state: state}), do: open?(state)
  def open?(state), do: state in @open_states

  @doc "Records a state change, refusing to move a finished order."
  @spec state_changeset(t(), atom(), keyword()) :: Ecto.Changeset.t()
  def state_changeset(%__MODULE__{} = order, to_state, opts \\ []) do
    changeset =
      order
      |> change()
      |> put_change(:state, to_state)

    if Keyword.get(opts, :force, false) do
      changeset
    else
      validate_change(changeset, :state, fn field, value ->
        finished_error(order, field, value)
      end)
    end
  end

  defp finished_error(order, :state, _value) do
    if terminal?(order), do: [state: "an order in #{order.state} is finished"], else: []
  end

  def changeset(order, attrs) do
    order
    |> cast(attrs, [
      :user_id,
      :lane_id,
      :link,
      :quantity,
      :retail_cents,
      :cost_usd_micros,
      :margin_bps,
      :buffer_bps,
      :fx_rate_id,
      :supplier_id,
      :supplier_service_id,
      :supplier_order_id,
      :supplier_status,
      :start_count,
      :remains,
      :charge_usd_micros,
      :currency,
      :state
    ])
    |> validate_required([
      :user_id,
      :lane_id,
      :link,
      :quantity,
      :retail_cents,
      :margin_bps,
      :buffer_bps,
      :state
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:retail_cents, greater_than: 0)
    |> foreign_key_constraint(:lane_id)
    |> foreign_key_constraint(:user_id)
  end
end
