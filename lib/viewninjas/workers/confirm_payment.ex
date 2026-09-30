defmodule ViewNinjas.Workers.ConfirmPayment do
  @moduledoc """
  Where "paid only when the GET says `settled`" lives (scope.md §8,
  `docs/malipo-connect.md` §9).

  Safe to run for a callback and for a poll: `unique` on the payment id makes the
  second caller attach to the first job instead of starting a second one, and a
  payment whose row is already terminal is a no-op.

  Two rules hold it together:

    * **Settled is the only way money moves.** A transport error retries with
      backoff; it never guesses.
    * **We never fail a payment on our own clock.** Past the deadline the job
      cancels without deciding, because only the rail knows the outcome; the
      order simply stays `awaiting_payment` and stays retryable.
  """

  use Oban.Worker,
    queue: :payments,
    max_attempts: 50,
    unique: [
      period: 300,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:payment_id]
    ]

  alias ViewNinjas.Alerts
  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.Payment

  @poll_interval 3
  # The prompt lives about 90 seconds; a little past that is enough.
  @prompt_window 120

  @doc """
  Enqueues (or coalesces into) the confirmation for a payment.

  The deadline is stamped here, so a callback and a poller that arrive at
  different times still stop at the same wall clock.
  """
  def enqueue(payment_id) do
    new(%{payment_id: payment_id, deadline: System.system_time(:second) + @prompt_window})
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id} = args}) do
    deadline = args["deadline"] || System.system_time(:second) + @prompt_window

    case Payments.get_payment(payment_id) do
      nil ->
        {:discard, :unknown_payment}

      %Payment{} = payment ->
        if Payment.terminal?(payment), do: :ok, else: confirm(payment, deadline)
    end
  end

  # Money moves on exactly one signal: the rail saying settled — and only when
  # its answer still describes the attempt we made (scope.md §13).
  defp confirm(%Payment{malipo_payment_id: nil}, deadline), do: poll_again(deadline)

  defp confirm(payment, deadline) do
    case Payments.provider().get(payment.malipo_payment_id) do
      {:ok, %{status: :settled} = fresh} ->
        settle(payment, fresh)

      {:ok, %{status: :failed} = fresh} ->
        fail(payment, fresh)

      {:ok, %{status: :pending}} ->
        poll_again(deadline)

      {:error, _reason} ->
        {:error, :rail_unavailable}
    end
  end

  defp settle(payment, fresh) do
    case Payments.verify_attempt(payment, fresh) do
      :ok ->
        case Payments.apply_settlement(payment, fresh.receipt) do
          {:ok, _result} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, kind} ->
        mismatch(payment, kind)
    end
  end

  # The rail says settled, but for a payment that is not the one we made. Do not
  # move money: fail it, raise it, and let a person reconcile with the rail.
  defp mismatch(payment, :amount_mismatch), do: mismatch(payment, :amount_mismatch, "amount")

  defp mismatch(payment, :phone_mismatch),
    do: mismatch(payment, :phone_mismatch, "phone number")

  defp mismatch(payment, kind, field) do
    Alerts.publish(
      :payment_mismatch,
      "payment #{payment.id} settled at the rail but the #{field} did not match the attempt",
      %{payment_id: payment.id}
    )

    Payments.mark_failed(payment, %{
      failure_kind: to_string(kind),
      failure_message: "the rail's answer did not match the attempt"
    })

    :ok
  end

  defp fail(payment, fresh) do
    case Payments.mark_failed(payment, %{
           failure_kind: fresh.failure_kind,
           failure_message: fresh.failure_message
         }) do
      {:ok, _payment} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp poll_again(deadline) do
    if System.system_time(:second) < deadline do
      {:snooze, @poll_interval}
    else
      {:cancel, :prompt_window_elapsed}
    end
  end
end
