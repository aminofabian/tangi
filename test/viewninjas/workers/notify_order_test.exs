defmodule ViewNinjas.Workers.NotifyOrderTest do
  @moduledoc """
  The notification job (build-plan.md M11, scope.md §11): a text on the events
  that matter, an opt-out honoured, quiet hours snoozed, and a receipt emailed.
  """

  use ViewNinjas.DataCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import Swoosh.TestAssertions
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Accounts, Notifications, Payments}
  alias ViewNinjas.Sms.Providers.Test
  alias ViewNinjas.Workers.NotifyOrder

  setup do
    %{order: paid_order_with_lane_fixture()}
  end

  test "a paid order texts the customer its receipt", %{order: order} do
    user = Accounts.get_user!(order.user_id)
    payment = payment_fixture(%{order: order})
    {:ok, sent} = Payments.mark_pending(payment, "malipo-1")
    {:ok, _settled} = Payments.settle(sent, "QKH7XYZ123")

    assert :ok = perform_job(NotifyOrder, %{"order_id" => order.id, "event" => "paid"})

    assert {_ref, body} = Test.last_message(user.phone)
    assert body =~ "QKH7XYZ123"
    assert_email_sent(fn email -> email.subject == "Your Tangi receipt" end)
  end

  test "an opted-out customer is not texted", %{order: order} do
    user = Accounts.get_user!(order.user_id)

    {:ok, :saved} =
      Notifications.save_preferences(user, %{
        "sms_opted_in" => "false",
        "email_opted_in" => "false"
      })

    assert :ok = perform_job(NotifyOrder, %{"order_id" => order.id, "event" => "completed"})

    assert Test.last_message(user.phone) == nil
    refute_email_sent()
  end

  test "quiet hours snooze the text rather than dropping it", %{order: order} do
    user = Accounts.get_user!(order.user_id)

    {:ok, :saved} =
      Notifications.save_preferences(user, %{
        "sms_opted_in" => "true",
        "sms_quiet_hours" => quiet_now()
      })

    assert {:snooze, seconds} =
             perform_job(NotifyOrder, %{"order_id" => order.id, "event" => "paid"})

    assert seconds >= 60
    assert Test.last_message(user.phone) == nil
  end

  test "a completed order texts and a refunded order does too", %{order: order} do
    user = Accounts.get_user!(order.user_id)

    assert :ok = perform_job(NotifyOrder, %{"order_id" => order.id, "event" => "completed"})
    assert {_ref, completed} = Test.last_message(user.phone)
    assert completed =~ "complete"

    assert :ok = perform_job(NotifyOrder, %{"order_id" => order.id, "event" => "refunded"})
    assert {_ref, refunded} = Test.last_message(user.phone)
    assert refunded =~ "back in your wallet"
  end

  test "an unknown order is a no-op" do
    assert :ok = perform_job(NotifyOrder, %{"order_id" => -1, "event" => "paid"})
  end

  # A quiet window that contains the current local time, whenever the test runs.
  defp quiet_now do
    local = Notifications.local_time()
    start = local |> Time.add(-3_600) |> format_time()
    finish = local |> Time.add(3_600) |> format_time()
    "#{start}-#{finish}"
  end

  defp format_time(%Time{hour: hour, minute: minute}) do
    Enum.join([pad(hour), pad(minute)], ":")
  end

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
