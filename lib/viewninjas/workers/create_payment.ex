defmodule ViewNinjas.Workers.CreatePayment do
  @moduledoc """
  Puts the M-Pesa prompt on the customer's phone (scope.md §8).

  The outbound call happens here, in a worker, never on a rendered page
  (scope.md §13). A transport error or a 5xx is retried with the **same**
  idempotency key, which is safe: the rail returns the original payment rather
  than prompting twice. A definite rejection is recorded and not retried.
  """

  use Oban.Worker, queue: :payments, max_attempts: 5

  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.{Malipo, Payment}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"payment_id" => payment_id}, attempt: attempt, max_attempts: max}) do
    payment = Payments.get_payment(payment_id)

    cond do
      is_nil(payment) -> :ok
      Payment.terminal?(payment) -> :ok
      payment.malipo_payment_id -> :ok
      true -> request(payment, attempt, max)
    end
  end

  defp request(payment, attempt, max) do
    case Payments.provider().create(create_attrs(payment)) do
      {:ok, %{id: malipo_id}} ->
        {:ok, payment} = Payments.mark_pending(payment, malipo_id)
        _ = ViewNinjas.Workers.ConfirmPayment.enqueue(payment.id)
        :ok

      {:error, reason} ->
        if retryable?(reason) and attempt < max do
          {:error, reason}
        else
          {:ok, _payment} = Payments.mark_failed(payment, failure_attrs(reason))
          :ok
        end
    end
  end

  defp create_attrs(payment) do
    %{
      amount: Payments.amount_string(payment.amount_cents),
      customer_phone: phone(payment),
      idempotency_key: payment.idempotency_key,
      reference: reference(payment)
    }
  end

  # The number the attempt recorded, or the account's own when it recorded none.
  defp phone(payment), do: Payments.prompted_phone(payment)

  defp reference(%{order_id: nil} = payment), do: "topup-#{payment.id}"
  defp reference(%{order_id: order_id}), do: "order-#{order_id}"

  defp failure_attrs(reason) do
    %{failure_kind: failure_kind(reason), failure_message: Malipo.error_message(reason)}
  end

  defp failure_kind({:malipo, code, _message, _status}), do: code
  defp failure_kind(:not_configured), do: "not_configured"
  defp failure_kind(:client_id), do: "client_id"
  defp failure_kind({:transport, _reason}), do: "transport"
  defp failure_kind({:http_error, status}), do: "http_#{status}"
  defp failure_kind({:invalid_response, _raw}), do: "invalid_response"
  defp failure_kind(_other), do: "unknown"

  # A transport error or a 5xx might fix itself; a rejected key will not.
  defp retryable?({:transport, _reason}), do: true
  defp retryable?({:http_error, status}) when status >= 500, do: true
  defp retryable?(_reason), do: false
end
