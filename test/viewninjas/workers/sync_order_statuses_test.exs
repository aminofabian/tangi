defmodule ViewNinjas.Workers.SyncOrderStatusesTest do
  @moduledoc """
  The status batch (build-plan.md M8, scope.md §10): the panel's numbers written
  back onto the order, so margin is real rather than estimated.
  """

  # Points the panel client at the Req test plug, so keep this serial.
  use ViewNinjas.DataCase, async: false

  use Oban.Testing, repo: ViewNinjas.Repo

  import ExUnit.CaptureLog
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.CatalogFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Orders, Suppliers}
  alias ViewNinjas.Workers.SyncOrderStatuses

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

  test "maps the panel's word and writes its numbers onto the order" do
    order = supplier_order_fixture(%{supplier_order_id: "77"})

    Req.Test.stub(__MODULE__, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert body =~ "action=status"
      assert body =~ "order=77"

      Req.Test.json(conn, %{
        "77" => %{
          "status" => "In progress",
          "start_count" => "1200",
          "remains" => "400",
          "charge" => "0.54",
          "currency" => "USD"
        }
      })
    end)

    assert :ok = perform_job(SyncOrderStatuses, %{})

    updated = Orders.get_order!(order.id)
    assert updated.state == :in_progress
    assert updated.supplier_status == "In progress"
    assert updated.start_count == 1200
    assert updated.remains == 400
    assert updated.charge_usd_micros == 540_000
    assert updated.currency == "USD"
  end

  test "a terminal word moves the order to completed" do
    order = supplier_order_fixture(%{supplier_order_id: "9"})

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"9" => %{"status" => "Completed", "remains" => "0"}})
    end)

    perform_job(SyncOrderStatuses, %{})

    assert Orders.get_order!(order.id).state == :completed
  end

  test "an unknown word keeps the state we had and stores what the panel said" do
    order = supplier_order_fixture(%{supplier_order_id: "5"})

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"5" => %{"status" => "Awaiting verification"}})
    end)

    perform_job(SyncOrderStatuses, %{})

    updated = Orders.get_order!(order.id)
    assert updated.state == :placed
    assert updated.supplier_status == "Awaiting verification"
    # One event for placement, and none for the unknown word.
    assert Orders.timeline(updated) |> Enum.count(&(&1.to_state == "placed")) == 1
  end

  test "a charge in another currency is never written" do
    order = supplier_order_fixture(%{supplier_order_id: "3"})

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{
        "3" => %{"status" => "Completed", "charge" => "1.00", "currency" => "EUR"}
      })
    end)

    log = capture_log(fn -> assert :ok = perform_job(SyncOrderStatuses, %{}) end)

    updated = Orders.get_order!(order.id)
    assert updated.currency == "EUR"
    assert updated.charge_usd_micros == nil
    assert log =~ "not USD"
  end

  test "an unchanged status does not add another timeline entry" do
    order = supplier_order_fixture(%{supplier_order_id: "4"})

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"4" => %{"status" => "Pending"}})
    end)

    perform_job(SyncOrderStatuses, %{})
    perform_job(SyncOrderStatuses, %{})

    assert Orders.get_order!(order.id).state == :placed
    # created, paid, placing, placed — and nothing more.
    assert Orders.timeline(Orders.get_order!(order.id)) |> Enum.count() == 4
  end

  test "chunks to the panel's multi-status limit" do
    offer = published_offer_fixture()
    lane = List.first(offer.lanes)
    user = verified_user_fixture()

    for id <- ["a", "b"] do
      place_order_on(lane, user, id)
    end

    supplier = Suppliers.get_supplier!(lane.supplier_service.supplier_id)

    {:ok, _} =
      Suppliers.update_supplier(supplier, %{
        capabilities: %{supplier.capabilities | "multi_status_limit" => 1}
      })

    calls = :counters.new(1, [])

    Req.Test.stub(__MODULE__, fn conn ->
      :counters.add(calls, 1, 1)
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      # One id per call, so no comma in the form body.
      refute body =~ "%2C"
      Req.Test.json(conn, %{})
    end)

    perform_job(SyncOrderStatuses, %{})

    assert :counters.get(calls, 1) == 2
  end

  test "orders with nothing to ask are skipped" do
    _unpaid = order_fixture()
    paid = paid_order_with_lane_fixture()

    calls = :counters.new(1, [])

    Req.Test.stub(__MODULE__, fn conn ->
      :counters.add(calls, 1, 1)
      Req.Test.json(conn, %{})
    end)

    perform_job(SyncOrderStatuses, %{})

    assert :counters.get(calls, 1) == 0
    assert Orders.get_order!(paid.id).state == :paid
  end

  defp place_order_on(lane, user, supplier_order_id) do
    {:ok, order} =
      Orders.create_order(%{user: user, lane: lane, link: "https://x.test", quantity: 1000})

    {:ok, paid} = Orders.mark_paid(order, "TESTRECEIPT")
    loaded = Orders.get_order_with_lane(paid.id)
    service = loaded.lane.supplier_service

    {:ok, placing} = Orders.mark_placing(loaded, service.supplier_id, service.id)
    {:ok, placed} = Orders.mark_placed(placing, supplier_order_id)
    placed
  end
end
