defmodule ViewNinjas.OrdersTest do
  @moduledoc """
  Orders and their state machine (build-plan.md M7, scope.md §6, §7).
  """

  use ViewNinjas.DataCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.CatalogFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Orders
  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Pricing
  alias ViewNinjas.Workers.{NotifyOrder, PlaceOrder}

  describe "create_order/1" do
    test "freezes the price it was quoted at" do
      offer = published_offer_fixture()
      lane = List.first(offer.lanes)
      user = verified_user_fixture()

      {:ok, order} =
        Orders.create_order(%{
          user: user,
          lane: lane,
          link: "https://instagram.com/x",
          quantity: 1000
        })

      assert order.state == :awaiting_payment
      assert order.retail_cents == Pricing.retail_kes_cents(900_000)
      assert order.cost_usd_micros == 900_000
      assert order.margin_bps == Pricing.current().margin_bps
      assert order.buffer_bps == Pricing.current().buffer_bps
      # The supplier columns stay null until placement (M8).
      assert order.supplier_id == nil
      assert order.supplier_service_id == nil
    end

    test "a later change to the knobs does not move an order's price" do
      order = order_fixture()

      {:ok, _version} =
        ViewNinjas.Pricing.append_settings(%{margin_bps: 20_000, buffer_bps: 900}, nil)

      unchanged = Orders.get_order!(order.id)

      # The order kept the margin, buffer and retail it was priced with (scope.md §7).
      assert unchanged.margin_bps == 13_000
      assert unchanged.buffer_bps == 300
      assert unchanged.retail_cents == order.retail_cents
      # The catalog would now quote this lane differently, but the order does not move.
      refute unchanged.retail_cents ==
               ViewNinjas.Pricing.retail_kes_cents(900_000, 1000, ViewNinjas.Pricing.current())
    end

    test "logs a creation event" do
      order = order_fixture()

      assert [%{to_state: "awaiting_payment", from_state: nil, reason: "created"}] =
               Orders.timeline(order)
    end

    test "scales with the quantity" do
      offer = published_offer_fixture()
      lane = List.first(offer.lanes)

      {:ok, order} =
        Orders.create_order(%{
          user: verified_user_fixture(),
          lane: lane,
          link: "https://instagram.com/x",
          quantity: 2000
        })

      assert order.retail_cents == Pricing.retail_kes_cents(900_000, 2000)
      assert order.cost_usd_micros == 1_800_000
    end

    test "refuses a link that is not a link" do
      offer = published_offer_fixture()
      lane = List.first(offer.lanes)

      assert {:error, changeset} =
               Orders.create_order(%{
                 user: verified_user_fixture(),
                 lane: lane,
                 link: "",
                 quantity: 1000
               })

      assert changeset.errors[:link]
    end
  end

  describe "one order of a service at a time" do
    setup do
      offer = published_offer_fixture()
      %{user: verified_user_fixture(), offer: offer, lane: List.first(offer.lanes)}
    end

    test "an order already on its way refuses a second one of the same lane", %{
      user: user,
      lane: lane
    } do
      supplier_order_fixture(%{user: user, lane: lane})

      assert {:error, :service_in_progress} =
               Orders.create_order(%{
                 user: user,
                 lane: lane,
                 link: "https://x.test",
                 quantity: 500
               })

      # Only the one that is already out.
      assert Orders.list_orders(user) |> length() == 1
    end

    test "a different lane is not blocked — the rule is per service", %{
      user: user,
      offer: offer,
      lane: lane
    } do
      supplier_order_fixture(%{user: user, lane: lane})

      other =
        lane_fixture(%{
          offer: offer,
          grade: :quality,
          service: service_fixture(%{supplier: lane.supplier_service.supplier})
        })

      assert {:ok, _fresh} =
               Orders.create_order(%{
                 user: user,
                 lane: other,
                 link: "https://x.test",
                 quantity: 500
               })
    end

    test "another customer's order on the same lane does not block", %{user: user, lane: lane} do
      supplier_order_fixture(%{user: verified_user_fixture(), lane: lane})

      assert {:ok, _fresh} =
               Orders.create_order(%{
                 user: user,
                 lane: lane,
                 link: "https://x.test",
                 quantity: 500
               })
    end

    test "a finished order frees the lane again", %{user: user, lane: lane} do
      completed_order_fixture(%{user: user, lane: lane})

      assert {:ok, fresh} =
               Orders.create_order(%{
                 user: user,
                 lane: lane,
                 link: "https://x.test",
                 quantity: 500
               })

      assert fresh.state == :awaiting_payment
    end

    test "an unpaid order does not block, so an abandoned checkout is not a trap", %{
      user: user,
      lane: lane
    } do
      # Nothing expires an `awaiting_payment` order — `ConfirmPayment` leaves a
      # cancelled prompt there on purpose. Blocking on it would lock the customer out
      # of the lane for good after one abandoned checkout.
      order_fixture(%{user: user, lane: lane})

      assert {:ok, _fresh} =
               Orders.create_order(%{
                 user: user,
                 lane: lane,
                 link: "https://x.test",
                 quantity: 500
               })
    end

    test "every still-owed state blocks", %{user: user, lane: lane} do
      for state <- Order.blocking_states() do
        # The *same* customer holds the lane: the rule is one order per service per
        # customer, not one per shop.
        order = supplier_order_fixture(%{user: user, lane: lane})
        {:ok, _moved} = Orders.transition(order, state, reason: "test")

        assert Orders.get_order!(order.id).state == state
        assert Orders.in_progress?(user.id, lane.id), "expected #{state} to hold the lane"

        assert {:error, :service_in_progress} =
                 Orders.create_order(%{
                   user: user,
                   lane: lane,
                   link: "https://x.test",
                   quantity: 500
                 }),
               "expected #{state} to hold the lane"

        # Release it again so the next state starts from a clean lane.
        {:ok, _done} = Orders.transition(Orders.get_order!(order.id), :completed, reason: "test")
        refute Orders.in_progress?(user.id, lane.id)
      end
    end

    test "in_progress?/2 and in_progress_order/2 read the same answer", %{user: user, lane: lane} do
      refute Orders.in_progress?(user.id, lane.id)
      assert Orders.in_progress_order(user, lane.id) == nil

      blocked = supplier_order_fixture(%{user: user, lane: lane})

      assert Orders.in_progress?(user.id, lane.id)
      assert Orders.in_progress_order(user, lane.id).id == blocked.id
    end

    test "repeating an order still on its way is refused", %{user: user, lane: lane} do
      placed = supplier_order_fixture(%{user: user, lane: lane})

      assert {:error, :service_in_progress} = Orders.repeat_order(user, placed)
    end

    test "repeating a finished order works", %{user: user, lane: lane} do
      done = completed_order_fixture(%{user: user, lane: lane})

      assert {:ok, fresh} = Orders.repeat_order(user, done)
      assert fresh.lane_id == done.lane_id
    end
  end

  describe "reads" do
    test "list_orders/2 and count_open/1 stay inside one customer" do
      mine = verified_user_fixture()
      theirs = verified_user_fixture()

      open = order_fixture(%{user: mine})
      order_fixture(%{user: theirs})
      paid = order_fixture(%{user: mine, paid: true})

      assert Orders.list_orders(mine) |> Enum.map(& &1.id) |> Enum.sort() ==
               Enum.sort([open.id, paid.id])

      # `paid` is work still owed; `awaiting_payment` has taken no money yet.
      assert Orders.count_open(mine) == 1
      assert Orders.count_open(theirs) == 0
    end

    test "get_order_for_user/2 will not hand over someone else's order" do
      owner = verified_user_fixture()
      intruder = verified_user_fixture()
      order = order_fixture(%{user: owner})

      assert Orders.get_order_for_user(owner, order.id).id == order.id
      assert Orders.get_order_for_user(intruder, order.id) == nil
    end
  end

  describe "the state machine" do
    test "moves an order and logs the move" do
      order = order_fixture()

      assert {:ok, paid} = Orders.mark_paid(order, "QKH7XYZ123")
      assert paid.state == :paid

      states = Orders.timeline(order) |> Enum.map(& &1.to_state)
      assert states == ["awaiting_payment", "paid"]
      assert Orders.timeline(order) |> List.last() |> Map.fetch!(:reason) =~ "QKH7XYZ123"
    end

    test "mark_paid/2 is idempotent" do
      order = order_fixture()

      {:ok, paid} = Orders.mark_paid(order, "R1")
      assert {:ok, ^paid} = Orders.mark_paid(paid, "R2")
      assert Orders.timeline(order) |> Enum.count() == 2
    end

    test "a finished order refuses to move" do
      order = order_fixture(%{paid: true})
      {:ok, completed} = Orders.transition(order, :completed)

      assert {:error, changeset} = Orders.transition(completed, :placing)
      assert changeset.errors[:state]
    end

    test "transition/3 records who did it" do
      order = order_fixture()
      admin = admin_fixture()

      {:ok, _moved} = Orders.transition(order, :placing, reason: "manual", actor: admin)

      assert Orders.timeline(order) |> List.last() |> Map.fetch!(:actor_id) == admin.id
    end
  end

  describe "Order helpers" do
    test "terminal?/1 and open?/1 read the state" do
      assert Order.terminal?(:completed)
      assert Order.terminal?(:refunded)
      refute Order.terminal?(:paid)
      assert Order.open?(:paid)
      assert Order.open?(:partial)
      refute Order.open?(:awaiting_payment)
    end

    test "pollable_states/0 is what the status batch asks about" do
      assert Order.pollable_states() == [:placed, :in_progress, :partial]
    end
  end

  describe "fulfilment" do
    test "mark_placing/3 persists the supplier, the service and the intent" do
      order = paid_order_with_lane_fixture()
      service = order.lane.supplier_service

      {:ok, placing} = Orders.mark_placing(order, service.supplier_id, service.id)

      assert placing.state == :placing
      assert placing.supplier_id == service.supplier_id
      assert placing.supplier_service_id == service.id
      assert Orders.timeline(placing) |> List.last() |> Map.fetch!(:to_state) == "placing"
    end

    test "mark_placed/2 stores the panel's id" do
      order = paid_order_with_lane_fixture()
      service = order.lane.supplier_service
      {:ok, placing} = Orders.mark_placing(order, service.supplier_id, service.id)

      {:ok, placed} = Orders.mark_placed(placing, 43_210)

      assert placed.state == :placed
      assert placed.supplier_order_id == "43210"
    end

    test "mark_needs_review/2 also catches an order we could not even try" do
      order = paid_order_with_lane_fixture()

      {:ok, reviewed} = Orders.mark_needs_review(order, "no usable pinned service")

      assert reviewed.state == :needs_review
      assert reviewed.supplier_order_id == nil
    end

    test "mark_failed_and_refund/2 credits the wallet exactly once" do
      order = paid_order_with_lane_fixture()
      service = order.lane.supplier_service
      {:ok, placing} = Orders.mark_placing(order, service.supplier_id, service.id)

      {:ok, refunded} = Orders.mark_failed_and_refund(placing, "the panel said no")

      assert refunded.state == :refunded
      assert ViewNinjas.Wallet.balance(order.user_id) == order.retail_cents

      assert Orders.timeline(refunded) |> Enum.map(& &1.to_state) |> Enum.take(-2) ==
               ["failed", "refunded"]
    end

    test "apply_supplier_status/2 writes the panel's numbers onto the order" do
      order = supplier_order_fixture(%{supplier_order_id: "1"})

      {:ok, updated} =
        Orders.apply_supplier_status(order, %{
          status: "Completed",
          start_count: 100,
          remains: 0,
          charge_usd_micros: 1_080_000,
          currency: "USD"
        })

      assert updated.state == :completed
      assert updated.charge_usd_micros == 1_080_000
      assert updated.start_count == 100
      assert updated.supplier_status == "Completed"
    end

    test "a charge in another currency is kept raw, never converted" do
      order = supplier_order_fixture(%{supplier_order_id: "1"})

      {:ok, updated} =
        Orders.apply_supplier_status(order, %{
          status: "Completed",
          charge_usd_micros: 1_000_000,
          currency: "KES"
        })

      assert updated.currency == "KES"
      assert updated.charge_usd_micros == nil
    end

    test "an unchanged status records no new event" do
      order = supplier_order_fixture(%{supplier_order_id: "1"})

      {:ok, _} = Orders.apply_supplier_status(order, %{status: "Pending", currency: "USD"})

      {:ok, _} =
        Orders.apply_supplier_status(Orders.get_order!(order.id), %{
          status: "Pending",
          currency: "USD"
        })

      assert Orders.timeline(order) |> Enum.count() == 4
    end

    test "enqueue_placement/1 queues only a paid order" do
      unpaid = order_fixture()
      assert {:ok, :nothing_to_place} = Orders.enqueue_placement(unpaid)
      assert all_enqueued(worker: PlaceOrder) == []

      paid = paid_order_with_lane_fixture()
      assert {:ok, _job} = Orders.enqueue_placement(paid)

      assert [%{args: %{"order_id" => id}}] = all_enqueued(worker: PlaceOrder)
      assert id == paid.id
    end
  end

  describe "notifications (M11)" do
    test "mark_paid/2 enqueues one paid notification" do
      order = order_fixture()

      {:ok, paid} = Orders.mark_paid(order, "R1")

      assert [%{args: %{"order_id" => id, "event" => "paid"}}] =
               all_enqueued(worker: NotifyOrder)

      assert id == paid.id
    end

    test "a report that completes an order enqueues a completion" do
      order = supplier_order_fixture()

      {:ok, _} = Orders.apply_supplier_status(order, %{status: "Completed", currency: "USD"})

      assert notified?("completed")
    end

    test "a report that changes nothing enqueues nothing new" do
      order = supplier_order_fixture()

      {:ok, _} = Orders.apply_supplier_status(order, %{status: "Pending", currency: "USD"})

      refute notified?("completed")
      refute notified?("refunded")
      refute notified?("partial")
    end

    test "a refund enqueues a refund notification" do
      order = paid_order_with_lane_fixture()
      service = order.lane.supplier_service
      {:ok, placing} = Orders.mark_placing(order, service.supplier_id, service.id)

      {:ok, _} = Orders.mark_failed_and_refund(placing, "the panel said no")

      assert notified?("refunded")
    end

    defp notified?(event) do
      Enum.any?(all_enqueued(worker: NotifyOrder), &(&1.args["event"] == event))
    end
  end
end
