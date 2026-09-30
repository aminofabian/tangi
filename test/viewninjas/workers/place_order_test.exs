defmodule ViewNinjas.Workers.PlaceOrderTest do
  @moduledoc """
  The one `add` (build-plan.md M8, scope.md §5, §10).

  The rule that matters most: `add` is not idempotent, so it is sent once — a
  timeout or a garbled body becomes `needs_review`, never a second order.
  """

  # Points the panel client at the Req test plug, so keep this serial.
  use ViewNinjas.DataCase, async: false

  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Orders, Suppliers, Wallet}
  alias ViewNinjas.Workers.PlaceOrder

  setup do
    previous = Application.get_env(:viewninjas, :suppliers, [])
    on_exit(fn -> Application.put_env(:viewninjas, :suppliers, previous) end)

    Application.put_env(
      :viewninjas,
      :suppliers,
      Keyword.put(previous, :req_options, plug: {Req.Test, __MODULE__})
    )

    :ok
  end

  test "a paid order is placed once, and the supplier's id is stored" do
    order = paid_order_with_lane_fixture(%{quantity: 1000, link: "https://instagram.com/x"})
    calls = :counters.new(1, [])

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "action=add"
      assert body =~ "quantity=1000"
      :counters.add(calls, 1, 1)
      Req.Test.json(conn, %{"order" => 23_501})
    end)

    perform_job(PlaceOrder, %{"order_id" => order.id})

    placed = Orders.get_order!(order.id)
    assert placed.state == :placed
    assert placed.supplier_order_id == "23501"
    # The intent was persisted: supplier and service are on the order now.
    assert placed.supplier_id == order.lane.supplier_service.supplier_id
    assert placed.supplier_service_id == order.lane.supplier_service.id
    assert :counters.get(calls, 1) == 1

    states = Orders.timeline(placed) |> Enum.map(& &1.to_state)
    assert states == ["awaiting_payment", "paid", "placing", "placed"]
  end

  test "a duplicate job does not call add again" do
    order = paid_order_with_lane_fixture()
    calls = :counters.new(1, [])

    Req.Test.stub(__MODULE__, fn conn ->
      :counters.add(calls, 1, 1)
      Req.Test.json(conn, %{"order" => 11})
    end)

    perform_job(PlaceOrder, %{"order_id" => order.id})
    perform_job(PlaceOrder, %{"order_id" => order.id})

    assert Orders.get_order!(order.id).state == :placed
    assert :counters.get(calls, 1) == 1
  end

  test "a definite rejection fails the order and refunds the wallet" do
    order = paid_order_with_lane_fixture()

    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"error" => "Not enough funds"}) end)

    perform_job(PlaceOrder, %{"order_id" => order.id})

    refunded = Orders.get_order!(order.id)
    assert refunded.state == :refunded
    assert refunded.supplier_order_id == nil
    # Nothing was sent, so the customer's money came back to the wallet.
    assert Wallet.balance(order.user_id) == order.retail_cents

    states = Orders.timeline(refunded) |> Enum.map(& &1.to_state)
    assert states == ["awaiting_payment", "paid", "placing", "failed", "refunded"]
  end

  test "an ambiguous add lands in needs_review and never produces a second order" do
    order = paid_order_with_lane_fixture()
    calls = :counters.new(1, [])

    Req.Test.stub(__MODULE__, fn conn ->
      :counters.add(calls, 1, 1)
      Req.Test.transport_error(conn, :timeout)
    end)

    perform_job(PlaceOrder, %{"order_id" => order.id})

    reviewed = Orders.get_order!(order.id)
    assert reviewed.state == :needs_review
    assert reviewed.supplier_order_id == nil

    # Re-running the job — a retry, a redeploy, an admin tapping it again — must
    # not send another `add`.
    perform_job(PlaceOrder, %{"order_id" => order.id})

    assert Orders.get_order!(order.id).state == :needs_review
    assert :counters.get(calls, 1) == 1
    assert placed_events(order.id) == 0
  end

  test "a garbled body is ambiguous too" do
    order = paid_order_with_lane_fixture()

    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"queued" => true}) end)

    perform_job(PlaceOrder, %{"order_id" => order.id})

    assert Orders.get_order!(order.id).state == :needs_review
  end

  test "a panel that cannot add fails the order and refunds" do
    order = paid_order_with_lane_fixture()
    supplier = Suppliers.get_supplier!(order.lane.supplier_service.supplier_id)
    {:ok, _} = Suppliers.update_supplier(supplier, %{capabilities: %{"add" => false}})

    perform_job(PlaceOrder, %{"order_id" => order.id})

    assert Orders.get_order!(order.id).state == :refunded
    assert Wallet.balance(order.user_id) == order.retail_cents
  end

  test "an order that has not been paid is not placed" do
    order = order_fixture()
    calls = :counters.new(1, [])

    Req.Test.stub(__MODULE__, fn conn ->
      :counters.add(calls, 1, 1)
      Req.Test.json(conn, %{"order" => 1})
    end)

    perform_job(PlaceOrder, %{"order_id" => order.id})

    assert Orders.get_order!(order.id).state == :awaiting_payment
    assert :counters.get(calls, 1) == 0
  end

  defp placed_events(order_id) do
    Orders.timeline(Orders.get_order!(order_id))
    |> Enum.count(&(&1.to_state == "placed"))
  end
end
