defmodule ViewNinjas.ProgressTest do
  @moduledoc """
  Goals against reality (build-plan.md M10, scope.md §11): targets, the streak and
  the 30-day repeat rate.
  """

  use ViewNinjas.DataCase, async: true

  import Ecto.Query

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Progress
  alias ViewNinjas.Repo

  describe "targets" do
    test "the newest target for a metric and period wins" do
      {:ok, _old} =
        Progress.create_target(
          %{
            "metric" => "revenue",
            "period" => "month",
            "value_cents" => 100_000,
            "effective_at" => ~U[2026-09-01 00:00:00Z]
          },
          nil
        )

      {:ok, newer} =
        Progress.create_target(
          %{
            "metric" => "revenue",
            "period" => "month",
            "value_cents" => 200_000,
            "effective_at" => ~U[2026-09-15 00:00:00Z]
          },
          nil
        )

      assert [%{id: id}] = Progress.current_targets()
      assert id == newer.id
    end

    test "status reports the actual, the delta and the days left" do
      order = paid_order_with_lane_fixture()
      today = Date.utc_today()

      {:ok, _target} =
        Progress.create_target(
          %{"metric" => "revenue", "period" => "day", "value_cents" => 10_000},
          nil
        )

      assert [%{actual: actual, goal: 10_000, delta: delta, days_left: 0}] =
               Progress.status(today)

      assert actual == order.retail_cents
      assert delta == order.retail_cents - 10_000
    end

    test "days_left counts down the period" do
      assert Progress.days_left(:day, ~D[2026-09-15]) == 0
      assert Progress.days_left(:month, ~D[2026-09-15]) == 15
      assert Progress.days_left(:week, ~D[2026-09-16]) == 4
    end
  end

  describe "streak/1" do
    test "counts consecutive days with a settled order, ending today or yesterday" do
      today = Date.utc_today()
      settled_on(today)
      settled_on(Date.add(today, -1))
      settled_on(Date.add(today, -2))
      # A gap, then an older run that must not be counted.
      settled_on(Date.add(today, -5))

      assert Progress.streak(today) == 3
    end

    test "is zero with nothing settled" do
      assert Progress.streak(Date.utc_today()) == 0
    end
  end

  describe "repeat_rate/0" do
    test "is the share of customers who ordered again within 30 days" do
      user = verified_user_fixture()
      _first = order_fixture(%{user: user})
      _second = order_fixture(%{user: user})
      _one_off = order_fixture()

      %{repeat: repeat, total: total, rate: rate} = Progress.repeat_rate()

      assert total == 2
      assert repeat == 1
      assert rate == 0.5
    end
  end

  defp settled_on(date) do
    user = user_fixture()
    socket = System.unique_integer([:positive])

    {:ok, payment} =
      Repo.insert(%Payment{
        user_id: user.id,
        purpose: :order,
        amount_cents: 1_000,
        idempotency_key: "streak-#{socket}",
        malipo_payment_id: "malipo-streak-#{socket}",
        receipt: "RCPT-#{socket}",
        status: :settled
      })

    Repo.update_all(
      from(p in Payment, where: p.id == ^payment.id),
      set: [inserted_at: DateTime.new!(date, ~T[12:00:00])]
    )
  end
end
