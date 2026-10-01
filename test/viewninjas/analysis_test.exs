defmodule ViewNinjas.AnalysisTest do
  @moduledoc """
  The anomaly checks and the weekly digest (build-plan.md M10, scope.md §11).
  """

  use ViewNinjas.DataCase, async: true

  import Ecto.Query
  import Swoosh.TestAssertions
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures
  import ViewNinjas.PricingFixtures

  alias ViewNinjas.{Analysis, Digest, Orders, Payments, Repo}
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Sms.SmsMessage

  describe "anomalies/1" do
    test "is empty when nothing is wrong" do
      assert Analysis.anomalies() == []
    end

    test "flags a settled-rate drop past a floor of attempts" do
      Enum.each(1..5, fn _ -> failed_payment("customer_timeout") end)

      {:ok, pending} = paid_payment() |> Payments.mark_pending("malipo-ok")
      {:ok, _settled} = Payments.settle(pending, "RCPTOK")

      anomalies = Analysis.anomalies()

      assert Enum.any?(anomalies, fn
               {:settled_rate_drop, message} -> message =~ "settled in the last day"
               _ -> false
             end)
    end

    test "flags a spike in one failure kind" do
      Enum.each(1..5, fn _ -> failed_payment("insufficient_funds") end)

      kinds = Analysis.anomalies() |> Enum.map(&elem(&1, 0))
      assert :failure_spike in kinds
    end

    test "flags an SMS volume spike" do
      Enum.each(1..20, fn _ -> sms() end)

      kinds = Analysis.anomalies() |> Enum.map(&elem(&1, 0))
      assert :sms_spike in kinds
    end

    test "flags a lane sold below cost" do
      fx_rate_fixture(%{rate_ppm: 129_400_000})
      order = supplier_order_fixture()

      {:ok, _} =
        Orders.apply_supplier_status(Orders.get_order!(order.id), %{
          status: "Completed",
          charge_usd_micros: 10_000_000,
          currency: "USD"
        })

      kinds = Analysis.anomalies() |> Enum.map(&elem(&1, 0))
      assert :negative_margin in kinds
    end
  end

  describe "the digest" do
    test "reads the week's numbers into one body" do
      _order = paid_order_with_lane_fixture()

      body = Analysis.digest() |> Digest.body()

      assert body =~ "Tangi — week to"
      assert body =~ "Net profit:"
      assert body =~ "Orders:       1"
      assert body =~ "Nothing alerted."
    end

    test "goes to every super-admin and no one else" do
      super_admin_fixture(%{email: "boss@viewninjas.test"})
      _admin = admin_fixture()
      _customer = user_fixture()

      assert Digest.deliver() == 1
      assert_email_sent(fn email -> email.to == [{"", "boss@viewninjas.test"}] end)
    end
  end

  defp sms do
    Repo.insert!(%SmsMessage{
      to: "254712345678",
      template: "order_paid",
      provider: "test",
      status: :queued
    })
  end

  defp paid_payment do
    order = paid_order_with_lane_fixture()
    payment_fixture(%{order: order}) |> backdate()
  end

  defp failed_payment(failure_kind) do
    socket = System.unique_integer([:positive])
    user = user_fixture()

    %Payment{
      user_id: user.id,
      purpose: :order,
      amount_cents: 1_000,
      idempotency_key: "failed-#{socket}",
      status: :failed,
      failure_kind: failure_kind
    }
    |> Repo.insert!()
    |> backdate()
  end

  # An hour ago, so it is unambiguously inside the last day rather than the same
  # truncated second as the query.
  defp backdate(%Payment{} = payment) do
    Repo.update_all(
      from(p in Payment, where: p.id == ^payment.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(:second), -3_600)]
    )

    Repo.get!(Payment, payment.id)
  end
end
