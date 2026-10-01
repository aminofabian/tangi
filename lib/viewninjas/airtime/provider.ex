defmodule ViewNinjas.Airtime.Provider do
  @moduledoc """
  The one behaviour an airtime rail speaks (scope: `docs/instalipa-airtime.md` §4).

  `send_airtime/1` asks the rail to put airtime on a number; `status/1` reads a
  transaction's final state and is the **source of truth**. Nothing is cached here,
  and the caller owns the idempotency key. There is no "delivered" callback on
  purpose: only a confirming `status/1` may report a send succeeded.
  """

  @typedoc "One airtime transaction as the rail describes it."
  @type transaction :: %{
          id: String.t() | nil,
          status: :submitted | :pending | :success | :failed,
          details: String.t() | nil,
          phone: String.t() | nil,
          amount: String.t() | nil,
          discount: String.t() | nil,
          balance: String.t() | nil,
          reference: String.t() | nil,
          receipt: String.t() | nil
        }

  @doc """
  Sends airtime and returns the rail's transaction.

  `attrs`:

    * `:phone` — the recipient, canonical `254…`
    * `:amount` — whole shillings as a decimal string, e.g. `"100"`
    * `:reference` — our airtime order id, echoed on the callback and the status
    * `:idempotency_key` — per **intent**: a retry reuses it, a genuine second
      purchase uses a new one, because the rail dedupes on reference + key

  A `:submitted` or `:pending` status is an accepted request, not a delivered
  top-up — the rail confirms later.
  """
  @callback send_airtime(attrs :: map()) :: {:ok, transaction()} | {:error, term()}

  @doc "Reads a transaction's final state. Confirms a callback; this is the truth."
  @callback status(transaction_id :: String.t()) :: {:ok, transaction()} | {:error, term()}
end
