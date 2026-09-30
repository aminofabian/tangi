defmodule ViewNinjas.ProfitTest do
  @moduledoc """
  The P&L (build-plan.md M10, scope.md §10): revenue recognised once, costs at each
  order's own rate, and the net left over.
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.OrdersFixtures
  import ViewNinjas.PricingFixtures

  alias ViewNinjas.{Costs, Orders, Payments, Profit, Repo}
  alias ViewNinjas.Sms.SmsMessage

  describe "revenue" do
    test "counts a captured order once, whichever way it was paid" do
      order = paid_order_with_lane_fixture()

      assert Profit.for_period(:day).revenue_cents == order.retail_cents
    end

    test "a partial earns on the delivered share only" do
      order = paid_order_with_lane_fixture(%{quantity: 1000})

      {:ok, _} =
        Orders.apply_supplier_status(order, %{
          status: "Partial",
          remains: 250,
          currency: "USD"
        })

      credit = div(order.retail_cents * 250, 1000)
      assert Profit.for_period(:day).revenue_cents == order.retail_cents - credit
    end

    test "an order that never captured is not revenue" do
      _order = order_fixture()

      assert Profit.for_period(:day).revenue_cents == 0
    end
  end

  describe "cost of goods" do
    test "uses the panel's real charge at the order's snapshot FX" do
      fx_rate_fixture(%{rate_ppm: 129_400_000})
      order = supplier_order_fixture()

      {:ok, _} =
        Orders.apply_supplier_status(order, %{
          status: "Completed",
          charge_usd_micros: 1_080_000,
          currency: "USD"
        })

      p = Profit.for_period(:day)
      assert p.cogs_cents == 13_975
      assert p.gross_cents == p.revenue_cents - 13_975
    end

    test "falls back to the priced estimate before a charge lands" do
      fx_rate_fixture(%{rate_ppm: 129_400_000})
      _order = paid_order_with_lane_fixture()

      # No charge yet: the order's own snapshot cost at its FX is the placeholder.
      # 900_000 micros USD at 129.4 KES/USD is 11_646 cents.
      assert Profit.for_period(:day).cogs_cents == 11_646
    end
  end

  describe "the net" do
    test "takes out the fee, the SMS and the fixed costs" do
      order = paid_order_with_lane_fixture()

      payment = payment_fixture(%{order: order})
      {:ok, _} = Payments.record_fee(payment, 1_200)

      Repo.insert!(%SmsMessage{
        to: "254712345678",
        template: "otp",
        provider: "test",
        cost_micros: 800_000
      })

      {:ok, _cost} =
        Costs.create_cost(
          %{"kind" => "hosting", "amount_cents" => 5_000, "incurred_on" => Date.utc_today()},
          nil
        )

      p = Profit.for_period(:day)
      assert p.fees_cents == 1_200
      assert p.sms_cents == 80
      assert p.other_cents == 5_000
      assert p.cost_cents == p.cogs_cents + 1_200 + 80 + 5_000
      assert p.net_cents == p.revenue_cents - p.cost_cents
    end
  end

  describe "break_even/2" do
    test "says how many orders cover the fixed costs at this margin" do
      fx_rate_fixture(%{rate_ppm: 129_400_000})
      order = paid_order_with_lane_fixture()

      {:ok, _} =
        Orders.apply_supplier_status(
          Orders.get_order_with_lane(order.id),
          %{status: "Completed", charge_usd_micros: 100_000, currency: "USD"}
        )

      {:ok, _cost} =
        Costs.create_cost(
          %{"kind" => "hosting", "amount_cents" => 10_000, "incurred_on" => Date.utc_today()},
          nil
        )

      result = Profit.break_even(:day)
      assert result.fixed_cents == 10_000
      assert result.margin_per_order_cents > 0

      expected = div(10_000 + result.margin_per_order_cents - 1, result.margin_per_order_cents)
      assert result.orders_needed == expected
    end

    test "is nil without a margin to divide by" do
      assert %{orders_needed: nil, margin_per_order_cents: nil} = Profit.break_even(:day)
    end
  end
end
