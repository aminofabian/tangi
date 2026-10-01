defmodule ViewNinjas.Workers.ConfirmAirtime do
  @moduledoc """
  Where "delivered only when the status says Success" lives (scope:
  `docs/instalipa-airtime.md` §3.4, §6).

  Safe to run for a callback and for a poll: `unique` on the airtime order makes a
  second caller attach to the first job, and an order already terminal is a no-op.
  One `GET` per run, then `{:snooze, …}` while the rail is still pending, until the
  delivery window elapses.
  """

  use Oban.Worker,
    queue: :airtime,
    max_attempts: 50,
    unique: [
      period: 300,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:airtime_order_id]
    ]

  require Logger

  alias ViewNinjas.Airtime
  alias ViewNinjas.Airtime.AirtimeOrder
  alias ViewNinjas.Airtime.Instalipa
  alias ViewNinjas.Alerts

  @poll_interval 5
  # Airtime settles in seconds; a few minutes is generous before a person looks.
  @delivery_window 300

  @doc """
  Enqueues (or coalesces into) the confirmation for an airtime order.

  The deadline is stamped here, so a callback and a poller that arrive at different
  times still stop at the same wall clock.
  """
  def enqueue(airtime_order_id) do
    new(%{
      airtime_order_id: airtime_order_id,
      deadline: System.system_time(:second) + @delivery_window
    })
    |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"airtime_order_id" => id} = args}) do
    deadline = args["deadline"] || System.system_time(:second) + @delivery_window

    case Airtime.get_order(id) do
      nil ->
        {:discard, :unknown_airtime_order}

      %AirtimeOrder{} = order ->
        if AirtimeOrder.terminal?(order), do: :ok, else: confirm(order, deadline)
    end
  end

  defp confirm(%AirtimeOrder{state: :submitted, instalipa_id: id} = order, deadline)
       when is_binary(id) do
    case Instalipa.status(id) do
      {:ok, %{status: :success} = tx} -> Airtime.mark_delivered(order, tx)
      {:ok, %{status: :failed} = tx} -> fail_and_refund(order, tx)
      {:ok, %{status: :submitted}} -> poll_again(deadline)
      {:ok, %{status: :pending}} -> poll_again(deadline)
      {:error, _reason} -> {:error, :rail_unavailable}
    end
  end

  # Not yet submitted, or carrying no rail id: there is nothing to ask about.
  defp confirm(%AirtimeOrder{}, _deadline), do: :ok

  defp fail_and_refund(order, tx) do
    message = tx[:details] || "the rail reported a failure"

    # One transaction: the order fails and the wallet is credited back together.
    case Airtime.fail_and_refund(order, "failed", message) do
      {:ok, _refunded} ->
        :ok

      {:error, reason} ->
        # The rail said it failed and we could not give the money back. That is a
        # promise we are breaking until a person fixes it, so say so loudly.
        Logger.error("airtime #{order.id} refund failed after a rail failure: #{inspect(reason)}")

        Alerts.publish(
          :airtime_refund_failed,
          "airtime #{order.id} for #{order.phone} failed at the rail and the refund did not commit",
          %{airtime_order_id: order.id, phone: order.phone, amount_cents: order.amount_cents}
        )

        :ok
    end
  end

  # Still pending: come back in a few seconds until the window closes. We never
  # decide on our own clock — past the window the sweep parks the row for a person
  # rather than guessing.
  defp poll_again(deadline) do
    if System.system_time(:second) < deadline do
      {:snooze, @poll_interval}
    else
      {:cancel, :delivery_window_elapsed}
    end
  end
end
