defmodule ViewNinjas.Payments do
  @moduledoc """
  Payment attempts against Malipo Connect (scope.md §8, `docs/malipo-connect.md`).

  A `Payment` row exists from the moment an attempt starts — before Malipo has
  answered — so there is always an id to watch. One attempt carries one
  idempotency key; a retry is a new row with a new key.

  **One rule holds the whole milestone together:** money moves only when a
  confirming `get/1` says `settled`. A callback is a hint, and a row is only ever
  settled here, in `apply_settlement/2` — the single funnel where a settled
  payment becomes a paid order or a credited wallet.
  """

  import Ecto.Query

  require Logger

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Orders
  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Repo
  alias ViewNinjas.Wallet

  @pubsub ViewNinjas.PubSub

  @doc "The configured payment rail. Malipo in development and production."
  @spec provider() :: module()
  def provider do
    :viewninjas
    |> Application.get_env(:payments, [])
    |> Keyword.get(:provider, ViewNinjas.Payments.Malipo)
  end

  @doc "Whether the rail is configured well enough to try."
  def configured?, do: provider() != ViewNinjas.Payments.Malipo or malipo_configured?()

  defp malipo_configured?, do: ViewNinjas.Payments.Malipo.ready?()

  # -- reading -----------------------------------------------------------

  def get_payment(id), do: Repo.get(Payment, id)
  def get_payment!(id), do: Repo.get!(Payment, id)

  @doc "The payment Malipo knows by this id, or nil."
  def get_payment_by_malipo_id(id) when is_binary(id),
    do: Repo.get_by(Payment, malipo_payment_id: id)

  def get_payment_by_malipo_id(_id), do: nil

  @doc """
  The settled payment carrying this M-Pesa receipt, matched **inside a window**.

  Never global: a receipt reused years apart must not collide, so the window is
  the statement's own period plus a business-day margin (docs/malipo-connect.md §10).
  """
  def get_by_receipt(receipt, {from, to}) when is_binary(receipt) do
    Payment
    |> where(
      [p],
      p.receipt == ^receipt and p.status == :settled and p.inserted_at >= ^from and
        p.inserted_at < ^to
    )
    |> order_by([p], desc: p.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def get_by_receipt(_receipt, _window), do: nil

  @doc "Every settled payment inside a window, for the local-only pass."
  def settled_between(from, to) do
    Payment
    |> where([p], p.status == :settled and p.inserted_at >= ^from and p.inserted_at < ^to)
    |> Repo.all()
  end

  @doc """
  Writes the reconciled Malipo fee onto a payment (scope.md §10).

  Only a settlement statement names the fee; it is never fitted from a rate.
  """
  @spec record_fee(Payment.t(), integer() | nil) :: {:ok, Payment.t()} | {:error, term()}
  def record_fee(%Payment{} = payment, fee_cents) when is_integer(fee_cents) do
    payment |> Ecto.Changeset.change(fee_cents: fee_cents) |> Repo.update()
  end

  def record_fee(%Payment{} = payment, _fee_cents), do: {:ok, payment}

  @doc "Every attempt for an order, newest first."
  def list_for_order(%Order{id: order_id}) do
    Payment
    |> where([p], p.order_id == ^order_id)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> Repo.all()
  end

  @doc "The attempt still waiting on an order, if any."
  def pending_for_order(%Order{id: order_id}) do
    Payment
    |> where([p], p.order_id == ^order_id and p.status == :pending)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc "The top-up still waiting for a customer, if any."
  def pending_topup(%User{id: user_id}) do
    Payment
    |> where([p], p.user_id == ^user_id and p.purpose == :topup and p.status == :pending)
    |> order_by([p], desc: p.inserted_at, desc: p.id)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Pending payments with a Malipo id, started within a window — the sweep's query.

  The lower bound is what keeps the sweep honest: past an hour a payment Malipo
  never resolved is a job for a human, not for the poller.
  """
  def list_stale_pending(from, to, opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    Payment
    |> where(
      [p],
      p.status == :pending and not is_nil(p.malipo_payment_id) and
        p.inserted_at >= ^from and p.inserted_at < ^to
    )
    |> order_by([p], asc: p.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  # -- starting an attempt -----------------------------------------------

  @doc """
  Starts a local attempt. Idempotent on the key: a repeated key returns the row
  that is already there, so a double-submit never prompts twice.
  """
  @spec start_attempt(map()) :: {:ok, Payment.t()} | {:error, Ecto.Changeset.t()}
  def start_attempt(attrs) do
    case Repo.get_by(Payment, idempotency_key: attrs.idempotency_key) do
      nil -> %Payment{} |> Payment.changeset(attrs) |> Repo.insert()
      existing -> {:ok, existing}
    end
  end

  @doc "The next attempt key for an order: `order-<id>-<n>` (scope.md §8)."
  def order_attempt_key(%Order{id: id}) do
    "order-#{id}-#{attempt_count(:order, id)}"
  end

  @doc "The next attempt key for a wallet top-up."
  def topup_attempt_key(%User{id: id}) do
    "topup-#{id}-#{attempt_count(:topup, id)}"
  end

  defp attempt_count(:order, order_id) do
    Repo.aggregate(from(p in Payment, where: p.order_id == ^order_id), :count) + 1
  end

  defp attempt_count(:topup, user_id) do
    Repo.aggregate(
      from(p in Payment, where: p.user_id == ^user_id and p.purpose == :topup),
      :count
    ) + 1
  end

  @doc "Starts the attempt that pays an order in full."
  @spec start_order_payment(Order.t(), String.t() | nil) ::
          {:ok, Payment.t()} | {:error, Ecto.Changeset.t()}
  def start_order_payment(%Order{} = order, phone \\ nil) do
    start_attempt(%{
      user_id: order.user_id,
      order_id: order.id,
      purpose: :order,
      amount_cents: order.retail_cents,
      phone: phone,
      idempotency_key: order_attempt_key(order)
    })
  end

  @doc """
  Starts an attempt that tops up a wallet.

  `phone` is the number to prompt; a customer may pay from a second phone, so it
  is stored on the attempt and checked at settlement. Nil means the account's own.
  """
  @spec start_topup_payment(User.t(), integer(), String.t() | nil) ::
          {:ok, Payment.t()} | {:error, Ecto.Changeset.t()}
  def start_topup_payment(%User{} = user, amount_cents, phone \\ nil) do
    start_attempt(%{
      user_id: user.id,
      purpose: :topup,
      amount_cents: amount_cents,
      phone: phone,
      idempotency_key: topup_attempt_key(user)
    })
  end

  @doc "Whole shillings as the decimal string Malipo wants: 27_600 -> `\"276.00\"`."
  def amount_string(cents) when is_integer(cents), do: "#{div(cents, 100)}.00"

  @doc """
  Whether a settled `GET` actually describes the attempt we made (scope.md §13).

  The id matched, but the amount — and the phone, when the rail reports one — must
  too. A rail that tells us nothing about a field is trusted; one that contradicts
  us is not, and the settlement stops for a person.
  """
  @spec verify_attempt(Payment.t(), map()) :: :ok | {:error, :amount_mismatch | :phone_mismatch}
  def verify_attempt(%Payment{} = payment, fresh) do
    with :ok <- verify_amount(payment, fresh) do
      verify_phone(payment, fresh)
    end
  end

  defp verify_amount(payment, fresh) do
    case amount_cents(fresh) do
      nil -> :ok
      cents when cents == payment.amount_cents -> :ok
      _other -> {:error, :amount_mismatch}
    end
  end

  defp verify_phone(%Payment{} = payment, fresh) do
    case Map.get(fresh, :customer_phone) do
      nil -> :ok
      phone -> if phone == prompted_phone(payment), do: :ok, else: {:error, :phone_mismatch}
    end
  end

  @doc """
  The number a payment's prompt actually went to.

  The attempt records the MSISDN it prompted; a row written before that column
  existed — or one that used the account phone — falls back to the account's own,
  which is where those prompts went.
  """
  @spec prompted_phone(Payment.t()) :: String.t() | nil
  def prompted_phone(%Payment{phone: phone}) when is_binary(phone), do: phone
  def prompted_phone(%Payment{user_id: user_id}), do: account_phone(user_id)

  defp account_phone(user_id) do
    case Repo.get(User, user_id) do
      %User{phone: phone} -> phone
      _ -> nil
    end
  end

  defp amount_cents(%{amount: value}) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} ->
        decimal |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_integer()

      _ ->
        nil
    end
  end

  defp amount_cents(%{amount: value}) when is_integer(value), do: value
  defp amount_cents(_fresh), do: nil

  @doc """
  Customer copy for a failed prompt (scope.md §8).

  The kind when we know it — the customer's to fix, or ours to retry — and the
  rail's own message otherwise. Either way the order stays `awaiting_payment` and
  the customer can try again with a new attempt.
  """
  @spec failure_copy(String.t() | nil, String.t() | nil) :: String.t()
  def failure_copy(kind, message)

  def failure_copy("customer_declined", _message), do: "You declined the prompt on your phone."
  def failure_copy("subscriber_cancelled", _message), do: "The prompt was cancelled."
  def failure_copy("customer_timeout", _message), do: "The PIN was not entered in time."
  def failure_copy("wrong_pin", _message), do: "The M-Pesa PIN was wrong."
  def failure_copy("insufficient_funds", _message), do: "There was not enough money on the phone."

  def failure_copy("timeout", _message),
    do: "M-Pesa did not finish in time. Nothing was charged — try again."

  def failure_copy("expired", _message),
    do: "The prompt window closed. Nothing was charged — try again."

  def failure_copy(_kind, message) when is_binary(message), do: message
  def failure_copy(_kind, _message), do: "The payment did not go through."

  # -- recording what Malipo said ----------------------------------------

  @doc "Records the Malipo payment id once `create/1` has answered."
  def mark_pending(%Payment{} = payment, malipo_payment_id) do
    payment
    |> Payment.changeset(%{malipo_payment_id: malipo_payment_id, status: :pending})
    |> Repo.update()
    |> tap_broadcast()
  end

  @doc "Records a failure — the prompt was declined, timed out, or never sent."
  def mark_failed(%Payment{} = payment, attrs) do
    payment
    |> Payment.changeset(Map.merge(%{status: :failed}, attrs))
    |> Repo.update()
    |> tap_broadcast()
  end

  @doc """
  The single funnel: a settled payment becomes money.

  `topup` credits the wallet; `order` marks the order paid. Both run inside one
  transaction, and both are idempotent — a replayed settlement writes nothing a
  second time.
  """
  @spec apply_settlement(Payment.t(), String.t() | nil) :: {:ok, term()} | {:error, term()}
  def apply_settlement(%Payment{status: :settled} = payment, _receipt) do
    # Already settled and applied; nothing to do.
    broadcast(payment)
    {:ok, {:already_settled, payment}}
  end

  def apply_settlement(%Payment{} = payment, receipt) do
    result =
      Repo.transact(fn ->
        case settle(payment, receipt) do
          {:ok, settled} -> apply_consequence(settled)
          {:error, _} = error -> error
        end
      end)

    broadcast_fresh(payment.id)
    log_failure(payment, result)
    enqueue_placement(result)
    result
  end

  # Only once the settlement has committed does placement become a job (M8).
  defp enqueue_placement({:ok, {:paid, order}}), do: Orders.enqueue_placement(order)
  defp enqueue_placement(_result), do: :ok

  @doc "Marks a payment settled. Callers wrap this in a transaction."
  def settle(%Payment{} = payment, receipt) do
    payment
    |> Payment.changeset(%{
      status: :settled,
      receipt: receipt,
      failure_kind: nil,
      failure_message: nil
    })
    |> Repo.update()
  end

  defp apply_consequence(%Payment{purpose: :topup} = payment) do
    case Wallet.topup(payment) do
      {:ok, entry} -> {:ok, {:credited, entry}}
      {:error, :already_recorded} -> {:ok, :already_credited}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp apply_consequence(%Payment{purpose: :order} = payment) do
    case Orders.mark_paid(payment) do
      {:ok, order} -> {:ok, {:paid, order}}
      error -> error
    end
  end

  # -- pubsub ------------------------------------------------------------

  @doc "Subscribes the caller to one payment, so a sheet can watch it."
  def subscribe(payment_id), do: Phoenix.PubSub.subscribe(@pubsub, topic(payment_id))

  @doc """
  Tells watchers that a payment changed, carrying the fresh row.

  The row travels in the message so a sheet can render it without a second read —
  the flash after a settlement is a pure assign, not a query.
  """
  def broadcast(%Payment{} = payment) do
    Phoenix.PubSub.broadcast(@pubsub, topic(payment.id), {:payment, payment})
  end

  defp topic(payment_id), do: "payments:#{payment_id}"

  # The caller's struct may be stale after a settlement, so send the committed row.
  defp broadcast_fresh(payment_id) do
    case Repo.get(Payment, payment_id) do
      nil -> :ok
      payment -> broadcast(payment)
    end
  end

  defp tap_broadcast({:ok, payment} = ok) do
    broadcast(payment)
    ok
  end

  defp tap_broadcast(error), do: error

  defp log_failure(payment, {:error, reason}) do
    Logger.warning("payment #{payment.id} settlement failed: #{inspect(reason)}")
  end

  defp log_failure(_payment, _result), do: :ok
end
