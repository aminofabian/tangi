defmodule ViewNinjas.Workers.RefillWorkersTest do
  @moduledoc """
  The one refill call and its status poll (build-plan.md M9, scope.md §10).

  Like `add`, `refill` is sent once and never retried: a rejection is terminal, an
  ambiguous answer or a paused panel is left for a person.
  """

  # Mutates global supplier config (the Req test plug), so keep this serial.
  use ViewNinjas.DataCase, async: false

  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Orders
  alias ViewNinjas.Suppliers
  alias ViewNinjas.Workers.{RefillOrder, SyncRefillStatuses}

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

  defp requested_refill do
    order = completed_order_fixture()
    {:ok, refill} = Orders.request_refill(order)
    refill
  end

  describe "RefillOrder" do
    test "asks once and stores the panel's refill id" do
      refill = requested_refill()
      calls = :counters.new(1, [])

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "action=refill"
        :counters.add(calls, 1, 1)
        Req.Test.json(conn, %{"refill" => 7654})
      end)

      perform_job(RefillOrder, %{"refill_id" => refill.id})

      updated = Orders.get_refill(refill.id)
      assert updated.state == :requested
      assert updated.supplier_refill_id == "7654"
      assert :counters.get(calls, 1) == 1
    end

    test "a rejection is terminal" do
      refill = requested_refill()

      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"error" => "Refill not available"})
      end)

      perform_job(RefillOrder, %{"refill_id" => refill.id})

      rejected = Orders.get_refill(refill.id)
      assert rejected.state == :rejected
      assert rejected.reason =~ "Refill not available"
    end

    test "an ambiguous answer is left for a person, not rejected" do
      refill = requested_refill()

      Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      perform_job(RefillOrder, %{"refill_id" => refill.id})

      parked = Orders.get_refill(refill.id)
      assert parked.state == :requested
      assert parked.supplier_refill_id == nil
    end

    test "a paused panel is left for a person" do
      refill = requested_refill()
      order = Orders.get_order!(refill.order_id)
      supplier = Suppliers.get_supplier!(order.supplier_id)
      {:ok, _} = Suppliers.pause(supplier, "under the float")

      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"refill" => 1}) end)

      perform_job(RefillOrder, %{"refill_id" => refill.id})

      assert Orders.get_refill(refill.id).state == :requested
    end

    test "a refill that is already resolved is not called again" do
      refill = requested_refill()
      {:ok, _} = Orders.mark_refill_rejected(refill, "already done")

      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"refill" => 1}) end)

      assert :ok = perform_job(RefillOrder, %{"refill_id" => refill.id})
      assert Orders.get_refill(refill.id).state == :rejected
    end
  end

  describe "SyncRefillStatuses" do
    test "resolves a requested refill the panel has completed" do
      refill = requested_refill()
      {:ok, asked} = Orders.mark_refill_requested(refill, "7654")

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert body =~ "action=refill_status"
        assert body =~ "refill=7654"
        Req.Test.json(conn, %{"status" => "Completed"})
      end)

      assert :ok = perform_job(SyncRefillStatuses, %{})

      assert Orders.get_refill(asked.id).state == :completed
    end

    test "a rejection from the poll is terminal too" do
      refill = requested_refill()
      {:ok, asked} = Orders.mark_refill_requested(refill, "7654")

      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"status" => "Rejected"}) end)

      perform_job(SyncRefillStatuses, %{})

      assert Orders.get_refill(asked.id).state == :rejected
    end
  end
end
