defmodule ViewNinjas.ObservabilityTest do
  @moduledoc """
  The four health questions (build-plan.md M12, scope.md §11): settled, delivered,
  placed, and how far behind the queue is.
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Observability, Orders, Payments, Repo}
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Sms.SmsMessage

  test "payments: the settled rate over attempts" do
    {from, to} = window()
    settled_payment()
    settled_payment()
    failed_payment()

    health = Observability.payment_health(from, to)
    assert health.settled == 2
    assert health.failed == 1
    assert_in_delta health.settled_rate, 2 / 3, 0.001
  end

  test "payments: no attempts is not a rate" do
    {from, to} = window()
    assert Observability.payment_health(from, to).settled_rate == nil
  end

  test "otp: the delivery rate" do
    {from, to} = window()
    sms(:delivered)
    sms(:delivered)
    sms(:failed)

    health = Observability.otp_health(from, to)
    assert health.sent == 3
    assert health.delivered == 2
    assert_in_delta health.delivery_rate, 2 / 3, 0.001
  end

  test "placement: what did not succeed" do
    {from, to} = window()
    _placed = supplier_order_fixture()
    reviewed = paid_order_with_lane_fixture()
    {:ok, _} = Orders.mark_needs_review(reviewed, "ambiguous")

    health = Observability.placement_health(from, to)
    assert health.placed == 1
    assert health.needs_review == 1
    assert_in_delta health.error_rate, 0.5, 0.001
  end

  test "queue: reports the lag" do
    assert %{available: available, lag_seconds: lag} = Observability.queue_lag()
    assert is_integer(available)
    assert is_integer(lag)
    assert lag >= 0
  end

  test "snapshot carries all four" do
    snapshot = Observability.snapshot()

    assert Map.keys(snapshot) |> Enum.sort() == [:otp, :payments, :placement, :queue]
  end

  # Wide enough to cover rows inserted in this test, without backdating them.
  defp window do
    now = DateTime.utc_now(:second)
    {DateTime.add(now, -3_600), DateTime.add(now, 3_600)}
  end

  defp settled_payment do
    order = paid_order_with_lane_fixture()
    payment = payment_fixture(%{order: order})
    {:ok, sent} = Payments.mark_pending(payment, "malipo-#{payment.id}")
    {:ok, _} = Payments.settle(sent, "RCPT#{payment.id}")
  end

  defp failed_payment do
    socket = System.unique_integer([:positive])

    Repo.insert!(%Payment{
      user_id: ViewNinjas.AccountsFixtures.user_fixture().id,
      purpose: :order,
      amount_cents: 1_000,
      idempotency_key: "obs-#{socket}",
      status: :failed,
      failure_kind: "customer_timeout"
    })
  end

  defp sms(status) do
    Repo.insert!(%SmsMessage{
      to: "254712345678",
      template: "order_paid",
      provider: "test",
      status: status
    })
  end
end
