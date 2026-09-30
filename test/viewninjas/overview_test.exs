defmodule ViewNinjas.OverviewTest do
  @moduledoc """
  The first admin overview and the margin report (build-plan.md M9, scope.md §10).
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.OrdersFixtures
  import ViewNinjas.PricingFixtures

  alias ViewNinjas.{Margin, Orders, Overview}

  describe "funnel/0" do
    test "counts the order's journey from paid to completed, in order" do
      _paid = paid_order_with_lane_fixture()
      _completed = completed_order_fixture()
      _completed_2 = completed_order_fixture()

      assert Overview.funnel() == [
               paid: 1,
               placing: 0,
               placed: 0,
               in_progress: 0,
               partial: 0,
               completed: 2
             ]
    end
  end

  describe "payment and risk" do
    test "money at risk is the retail of every order still owed" do
      paid = paid_order_with_lane_fixture()
      _completed = completed_order_fixture()

      assert Overview.money_at_risk_cents() == paid.retail_cents
    end

    test "review counts the orders waiting on a person" do
      order = paid_order_with_lane_fixture()
      {:ok, _} = Orders.mark_needs_review(order, "ambiguous")
      _partial = partial_order_fixture()

      assert Overview.review_counts() == %{needs_review: 1, partial: 1}
    end
  end

  describe "Margin" do
    test "cost is the panel's real charge at the order's snapshot rate" do
      fx_rate_fixture(%{rate_ppm: 129_400_000})
      order = supplier_order_fixture()

      {:ok, charged} =
        Orders.apply_supplier_status(order, %{
          status: "Completed",
          charge_usd_micros: 1_080_000,
          currency: "USD"
        })

      loaded = charged.id |> Orders.get_order!() |> ViewNinjas.Repo.preload(:fx_rate)
      assert Margin.cost_kes_cents(loaded) == 13_975
    end

    test "by_order, by_lane and by_week all add up to the same profit" do
      fx_rate_fixture(%{rate_ppm: 129_400_000})
      order = supplier_order_fixture()

      {:ok, _charged} =
        Orders.apply_supplier_status(order, %{
          status: "Completed",
          charge_usd_micros: 1_080_000,
          currency: "USD"
        })

      [row] = Margin.by_order()
      assert row.cost_cents == 13_975
      assert row.profit_cents == order.retail_cents - 13_975

      assert [lane] = Margin.by_lane()
      assert lane.orders == 1
      assert lane.profit_cents == row.profit_cents

      assert [week] = Margin.by_week()
      assert week.week =~ ~r/^\d{4}-W\d{2}$/
      assert week.profit_cents == row.profit_cents
    end

    test "an order with no charge yet has no realised margin" do
      fx_rate_fixture()
      _order = supplier_order_fixture()

      assert Margin.by_order() == []
      assert Margin.by_week() == []
    end
  end
end
