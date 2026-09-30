defmodule ViewNinjas.Payments.Provider do
  @moduledoc """
  The one behaviour a payment rail speaks (scope.md §8).

  `create/1` puts a prompt on a phone; `get/1` reads a payment's final state.
  Nothing is cached, and the caller owns the idempotency key. There is no
  `settle` here on purpose: only a confirming `get/1` may report `settled`.
  """

  @typedoc "A payment as the rail describes it."
  @type payment :: %{
          id: String.t(),
          status: :pending | :settled | :failed,
          amount: String.t(),
          currency: String.t(),
          receipt: String.t() | nil,
          failure_kind: String.t() | nil,
          failure_message: String.t() | nil,
          # The rail's view of who was prompted; compared against the attempt
          # when present (scope.md §13).
          customer_phone: String.t() | nil
        }

  @doc """
  Creates a payment and puts the prompt on the customer's phone.

  A repeated `:idempotency_key` returns the original payment instead of
  prompting again.
  """
  @callback create(attrs :: map()) :: {:ok, payment()} | {:error, term()}

  @doc "Reads a payment. Confirms a callback; this is the source of truth."
  @callback get(id :: String.t()) :: {:ok, payment()} | {:error, term()}
end
