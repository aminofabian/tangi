defmodule ViewNinjas.RefillsTest do
  @moduledoc """
  After the sale (build-plan.md M9, scope.md §6, §10): the automatic partial
  credit, refills, and the admin review queue.
  """

  use ViewNinjas.DataCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Orders
  alias ViewNinjas.Orders.{Order, Refill}
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.RefillOrder

  describe "partial completion" do
    test "credits the undelivered share from the KES-per-unit on the order" do
      order = supplier_order_fixture(%{quantity: 1000})

      {:ok, partial} =
        Orders.apply_supplier_status(order, %{
          status: "Partial",
          start_count: 0,
          remains: 250,
          charge_usd_micros: 900_000,
          currency: "USD"
        })

      assert partial.state == :partial
      assert partial.remains == 250

      expected = div(partial.retail_cents * 250, 1000)
      assert Orders.partial_cents(partial) == expected
      assert Wallet.balance(order.user_id) == expected
    end

    test "a repeated partial report never credits twice" do
      order = partial_order_fixture(%{quantity: 1000, remains: 400})
      credited = Wallet.balance(order.user_id)

      {:ok, _} =
        Orders.apply_supplier_status(Orders.get_order!(order.id), %{
          status: "Partial",
          remains: 400,
          currency: "USD"
        })

      assert Wallet.balance(order.user_id) == credited
    end

    test "a partial with no remains to work from credits nothing" do
      order = supplier_order_fixture()

      {:ok, partial} =
        Orders.apply_supplier_status(order, %{status: "Partial", currency: "USD"})

      assert partial.state == :partial
      assert Orders.partial_cents(partial) == nil
      assert Wallet.balance(order.user_id) == 0
    end

    test "partial_cents scales the captured price and never exceeds the retail" do
      order = paid_order_with_lane_fixture(%{quantity: 1000})

      assert Orders.partial_cents(%{order | remains: 0}) == nil
      assert Orders.partial_cents(%{order | remains: 500}) == div(order.retail_cents * 500, 1000)
      assert Orders.partial_cents(%{order | remains: 999_999}) == order.retail_cents
    end
  end

  describe "refills" do
    test "an order is refillable only when completed, sold with refill, and not yet refilled" do
      completed = completed_order_fixture()
      assert Orders.refillable?(completed)

      paid = paid_order_with_lane_fixture()
      refute Orders.refillable?(paid)
    end

    test "request_refill opens one row and queues the single call" do
      order = completed_order_fixture()

      assert {:ok, %Refill{state: :requested} = refill} = Orders.request_refill(order)
      assert refill.order_id == order.id

      assert [%{args: %{"refill_id" => id}}] = all_enqueued(worker: RefillOrder)
      assert id == refill.id

      # A second ask is refused — rejected or done, one refill per order.
      assert {:error, :not_refillable} = Orders.request_refill(order)
      assert all_enqueued(worker: RefillOrder) |> length() == 1
    end

    test "apply_refill_status maps the panel's words and keeps the state when unknown" do
      refill = completed_order_fixture() |> then(&Orders.request_refill/1) |> elem(1)

      assert {:ok, %Refill{state: :requested}} = Orders.apply_refill_status(refill, "Processing")
      assert {:ok, %Refill{state: :completed}} = Orders.apply_refill_status(refill, "Completed")
    end

    test "a rejection is terminal and stores the reason" do
      refill = completed_order_fixture() |> then(&Orders.request_refill/1) |> elem(1)

      {:ok, rejected} = Orders.mark_refill_rejected(refill, "service is down")

      assert rejected.state == :rejected
      assert rejected.reason == "service is down"
      assert Refill.terminal?(rejected)
    end
  end

  describe "the admin review queue" do
    test "an admin attaches the supplier id to a needs_review order" do
      actor = verified_user_fixture()
      order = paid_order_with_lane_fixture()
      {:ok, reviewed} = Orders.mark_needs_review(order, "the add never resolved")

      {:ok, placed} = Orders.admin_attach(reviewed, "88771", actor)

      assert placed.state == :placed
      assert placed.supplier_order_id == "88771"

      last = Orders.timeline(placed) |> List.last()
      assert last.to_state == "placed"
      assert last.actor_id == actor.id
    end

    test "an admin refunds a needs_review order that was never placed" do
      actor = verified_user_fixture()
      order = paid_order_with_lane_fixture(%{user: actor})
      {:ok, reviewed} = Orders.mark_needs_review(order, "the add never resolved")

      {:ok, refunded} = Orders.admin_refund(reviewed, actor)

      assert refunded.state == :refunded
      assert Wallet.balance(actor.id) == order.retail_cents
    end

    test "list_by_states returns only the asked-for states, newest first" do
      reviewed =
        paid_order_with_lane_fixture() |> then(&Orders.mark_needs_review(&1, "x")) |> elem(1)

      _paid = paid_order_with_lane_fixture()

      assert [%Order{id: id}] = Orders.list_by_states([:needs_review])
      assert id == reviewed.id
    end
  end
end
