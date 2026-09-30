defmodule ViewNinjas.Workers.NotifyOrder do
  @moduledoc """
  Tells a customer their order moved (scope.md §11; build-plan.md M11).

  One job per order event, sent from here so no rendered page ever makes the call
  (scope.md §13). The SMS respects the customer's opt-out and quiet hours — during
  quiet hours it is **snoozed**, not dropped, so the message arrives when the
  window closes. The email receipt carries the M-Pesa code.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [
      period: 3_600,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:order_id, :event]
    ]

  require Logger

  alias ViewNinjas.{Accounts, Mailer, Notifications, Orders, Sms}
  alias ViewNinjas.Orders.Order

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id, "event" => event}}) do
    with %Order{} = order <- Orders.get_order_with_lane(order_id),
         atom when is_atom(atom) <- parse_event(event) do
      deliver(order, atom)
    else
      _ -> :ok
    end
  end

  defp deliver(%Order{} = order, event) do
    user = Accounts.get_user!(order.user_id)
    send_receipt(user, order, event)
    send_sms(user, order, event)
  end

  defp send_receipt(user, order, event) when event in [:paid, :completed] do
    if present?(user.email) and Notifications.opted_in?(user, :email) do
      case Mailer.deliver(Notifications.receipt_email(user, order)) do
        {:ok, _metadata} -> :ok
        {:error, reason} -> Logger.warning("receipt email failed: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp send_receipt(_user, _order, _event), do: :ok

  defp send_sms(user, order, event) do
    cond do
      not Notifications.opted_in?(user, :sms) ->
        :ok

      Notifications.in_quiet_hours?(Notifications.quiet_hours(user, :sms)) ->
        {:snooze, Notifications.snooze_seconds(user, :sms)}

      true ->
        deliver_sms(user, order, event)
    end
  end

  defp deliver_sms(user, order, event) do
    {template, body} = Notifications.sms(order, event)

    case Sms.send_message(%{to: user.phone, template: template, body: body}) do
      {:ok, _message} ->
        :ok

      {:error, reason} when reason in [:spend_cap_reached, :sms_not_configured] ->
        # Retrying will not help: the cap resets tomorrow, a missing key is a
        # deployment problem. Log once and let the app be the record.
        Logger.warning("order notification not sent: #{reason}")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_event(event) when is_binary(event) do
    String.to_existing_atom(event)
  rescue
    ArgumentError -> nil
  end

  defp parse_event(_event), do: nil

  defp present?(value), do: is_binary(value) and value != ""
end
