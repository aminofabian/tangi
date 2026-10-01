defmodule ViewNinjas.Workers.SendAirtime do
  @moduledoc """
  The one send to the rail (scope: `docs/instalipa-airtime.md` §3.2, §12).

  A send is not something we can take back, so it is made exactly once:

    * an accepted transaction → `submitted`, and the confirming job is queued
    * a duplicate, a timeout, a 5xx or a garbled body → `needs_review`, never a
      second send
    * a definite rejection (a bad number, no float, a 4xx) → `failed`, refunded

  The job is `unique` on the airtime order and only ever touches a `paid` order, so
  a duplicate job is a no-op rather than a second top-up.
  """

  use Oban.Worker,
    queue: :airtime,
    max_attempts: 1,
    unique: [
      period: 300,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:airtime_order_id]
    ]

  require Logger

  alias ViewNinjas.Airtime
  alias ViewNinjas.Airtime.AirtimeOrder
  alias ViewNinjas.Airtime.Instalipa
  alias ViewNinjas.Payments
  alias ViewNinjas.Workers.ConfirmAirtime

  @doc "Queues the send for a paid airtime order."
  def enqueue(airtime_order_id), do: new(%{airtime_order_id: airtime_order_id}) |> Oban.insert()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"airtime_order_id" => id}}) do
    case Airtime.get_order(id) do
      nil -> :ok
      %AirtimeOrder{state: :paid} = order -> order |> Airtime.mark_sending() |> dispatch()
      %AirtimeOrder{} -> :ok
    end
  end

  # Only a paid order is sent. Anything else — already sending, submitted, gone —
  # is left exactly as it is.
  defp dispatch({:ok, sending}), do: send_it(sending)
  defp dispatch({:error, _reason}), do: :ok

  defp send_it(sending) do
    case Instalipa.send_airtime(attrs(sending)) do
      {:ok, tx} ->
        {:ok, submitted} = Airtime.mark_submitted(sending, tx)
        _ = ConfirmAirtime.enqueue(submitted.id)
        :ok

      {:error, :duplicate} ->
        _ = Airtime.mark_needs_review(sending, "the rail called it a duplicate request")
        :ok

      {:error, reason} ->
        classify(sending, reason)
    end
  rescue
    # Anything unexpected after the request went out is ambiguous, so it becomes a
    # person's job — never a second send.
    error -> Airtime.mark_needs_review(sending, "unexpected error: #{inspect(error)}")
  end

  defp classify(sending, reason) do
    if definite?(reason) do
      Logger.warning("airtime #{sending.id} rejected: #{inspect(reason)}")

      {:ok, failed} =
        Airtime.mark_failed(sending, failure_kind(reason), Instalipa.error_message(reason))

      Airtime.refund(failed)
    else
      Logger.warning("airtime #{sending.id} left ambiguous: #{inspect(reason)}")
      Airtime.mark_needs_review(sending, Instalipa.error_message(reason))
    end

    :ok
  end

  defp attrs(order) do
    %{
      phone: order.phone,
      amount: Payments.amount_string(order.amount_cents),
      reference: order.reference,
      idempotency_key: order.idempotency_key
    }
  end

  # A 4xx is the rail refusing this request; a transport error, a 5xx or an
  # unreadable body might still have sent the airtime, so it is not a failure.
  defp definite?(:not_configured), do: true

  defp definite?({:instalipa, _code, _message, status}) when is_integer(status),
    do: status in 400..499

  defp definite?({:http_error, status}), do: status in 400..499
  defp definite?(_reason), do: false

  defp failure_kind({:instalipa, code, _message, _status}) when is_binary(code), do: code
  defp failure_kind({:http_error, status}), do: "http_#{status}"
  defp failure_kind(:not_configured), do: "not_configured"
  defp failure_kind(_reason), do: "unknown"
end
