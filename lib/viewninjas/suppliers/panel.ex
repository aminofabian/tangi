defmodule ViewNinjas.Suppliers.Panel do
  @moduledoc """
  The wholesale panel boundary (scope.md §5): three keys in, one client out.

  @doc \"""
  Only the calls a milestone needs are declared here; `add` and `status` arrived
  with M8, and `refill`/`refill_status`/`cancel` join with M9. `add` is never
  called from a rendered page and never retried automatically (scope.md §5).
  """

  alias ViewNinjas.Suppliers.Supplier

  @typedoc "One raw service as the panel describes it."
  @type service :: %{
          external_id: String.t(),
          name: String.t() | nil,
          category: String.t() | nil,
          type: String.t() | nil,
          rate_micros: non_neg_integer() | nil,
          min: non_neg_integer() | nil,
          max: non_neg_integer() | nil,
          refill: boolean(),
          cancel: boolean()
        }

  @doc "The panel's whole inventory."
  @callback services(supplier :: Supplier.t()) :: {:ok, [service()]} | {:error, term()}

  @doc "The panel's account balance, in micros of USD."
  @callback balance(supplier :: Supplier.t()) :: {:ok, non_neg_integer()} | {:error, term()}

  @typedoc "What a panel says about one of our orders (scope.md §10)."
  @type status :: %{
          external_order_id: String.t() | nil,
          status: String.t() | nil,
          start_count: non_neg_integer() | nil,
          remains: non_neg_integer() | nil,
          charge_usd_micros: non_neg_integer() | nil,
          currency: String.t() | nil
        }

  @doc """
  Places one order. **Not idempotent** (scope.md §5): send it once, from a job,
  with a short timeout, and never automatically retry. A timeout does not mean
  the order was not created.
  """
  @callback add(
              supplier :: Supplier.t(),
              service_external_id :: String.t(),
              link :: String.t(),
              quantity :: integer()
            ) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Reads the state of up to the panel's multi-status limit of orders."
  @callback status(supplier :: Supplier.t(), supplier_order_ids :: [String.t()]) ::
              {:ok, [status()]} | {:error, term()}

  @doc """
  Asks the panel to refill one of its orders and returns the panel's refill id.
  Like `add`, it is sent once from a job and never retried automatically.
  """
  @callback refill(supplier :: Supplier.t(), supplier_order_id :: String.t()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Reads the state of one refill: the panel's own word (Completed, Rejected, …)."
  @callback refill_status(supplier :: Supplier.t(), supplier_refill_id :: String.t()) ::
              {:ok, String.t()} | {:error, term()}
end
