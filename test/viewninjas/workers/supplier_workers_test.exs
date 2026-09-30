defmodule ViewNinjas.Workers.SupplierWorkersTest do
  # Mutates global supplier config (the Req test plug), so keep this serial.
  use ViewNinjas.DataCase, async: false

  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.CatalogFixtures
  import ViewNinjas.SuppliersFixtures

  alias ViewNinjas.{Alerts, Catalog, Repo, Suppliers}
  alias ViewNinjas.Suppliers.SupplierService
  alias ViewNinjas.Workers.{CheckSupplierBalance, SyncSupplierServices}

  setup do
    previous = Application.get_env(:viewninjas, :suppliers, [])
    on_exit(fn -> Application.put_env(:viewninjas, :suppliers, previous) end)

    Application.put_env(
      :viewninjas,
      :suppliers,
      Keyword.put(previous, :req_options, plug: {Req.Test, __MODULE__})
    )

    Suppliers.subscribe()
    Alerts.subscribe()
    %{supplier: supplier_fixture(%{api_key: "secret-key"})}
  end

  describe "SyncSupplierServices" do
    test "ingests the pull and tells the back office", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, [
          %{
            "service" => 1,
            "name" => "IG followers",
            "rate" => "0.90",
            "min" => "100",
            "max" => "10000",
            "refill" => true
          },
          %{
            "service" => 2,
            "name" => "IG likes",
            "rate" => "0.05",
            "min" => "50",
            "max" => "5000"
          }
        ])
      end)

      assert :ok = perform_job(SyncSupplierServices, %{"supplier_id" => supplier.id})

      assert_receive {:suppliers, {:synced, slug, %{received: 2, active: 2, deactivated: 0}}}
      assert slug == supplier.slug
      assert Suppliers.count_active_services(supplier) == 2
    end

    test "a rejected key is reported once and not retried", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"error" => "Incorrect API key"})
      end)

      assert :ok = perform_job(SyncSupplierServices, %{"supplier_id" => supplier.id})
      assert_receive {:suppliers, {:sync_failed, _slug, {:api_error, "Incorrect API key"}}}
    end

    test "a transport error is returned so Oban retries", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, {:transport, _reason}} =
               perform_job(SyncSupplierServices, %{"supplier_id" => supplier.id})

      assert_receive {:suppliers, {:sync_failed, _slug, {:transport, _}}}
    end
  end

  describe "CheckSupplierBalance" do
    test "records the float and tells the back office", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"balance" => "12.50"}) end)

      assert :ok = perform_job(CheckSupplierBalance, %{"supplier_id" => supplier.id})

      assert_receive {:suppliers, {:balance, _slug, 12_500_000}}
      assert Suppliers.get_supplier!(supplier.id).last_balance_micros == 12_500_000
    end

    test "a rejected key is reported once and not retried", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, %{"error" => "Incorrect API key"})
      end)

      assert :ok = perform_job(CheckSupplierBalance, %{"supplier_id" => supplier.id})
      assert_receive {:suppliers, {:balance_failed, _slug, {:api_error, "Incorrect API key"}}}
      assert is_nil(Suppliers.get_supplier!(supplier.id).last_balance_micros)
    end

    test "a balance under the float pauses the panel and raises an alert", %{supplier: supplier} do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"balance" => "1.00"}) end)

      assert :ok = perform_job(CheckSupplierBalance, %{"supplier_id" => supplier.id})

      assert Suppliers.paused?(Suppliers.get_supplier!(supplier.id))
      assert_receive {:alert, %{kind: :supplier_paused}}
    end

    test "a balance back above the float resumes the panel", %{supplier: supplier} do
      {:ok, _} = Suppliers.pause(supplier, "under the float")
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"balance" => "50.00"}) end)

      assert :ok = perform_job(CheckSupplierBalance, %{"supplier_id" => supplier.id})

      refute Suppliers.paused?(Suppliers.get_supplier!(supplier.id))
      assert_receive {:alert, %{kind: :supplier_resumed}}
    end
  end

  describe "SyncSupplierServices — stale lanes (M9)" do
    test "a changed service takes its published lanes off sale and alerts", %{supplier: supplier} do
      lane = published_lane_for(supplier)
      assert lane.published

      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, [%{"service" => 1, "name" => "IG", "rate" => "2.00"}])
      end)

      assert :ok = perform_job(SyncSupplierServices, %{"supplier_id" => supplier.id})

      refute Catalog.get_lane!(lane.id).published
      assert_receive {:alert, %{kind: :lanes_unpublished}}
    end

    test "an unchanged service leaves its lanes on sale", %{supplier: supplier} do
      lane = published_lane_for(supplier)

      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.json(conn, [%{"service" => 1, "name" => "IG", "rate" => "0.90"}])
      end)

      assert :ok = perform_job(SyncSupplierServices, %{"supplier_id" => supplier.id})

      assert Catalog.get_lane!(lane.id).published
      refute_received {:alert, %{kind: :lanes_unpublished}}
    end
  end

  # A published lane pinned to the supplier's service `1`, ingested at the rate
  # the sync above will then change. Bounds and refill are left out so a pull that
  # repeats the same rate is genuinely unchanged.
  defp published_lane_for(supplier) do
    {:ok, _stats} =
      Suppliers.ingest_services(supplier, [
        service_attrs(%{external_id: "1", min: nil, max: nil})
      ])

    service = Repo.get_by!(SupplierService, supplier_id: supplier.id, external_id: "1")
    offer = offer_fixture()

    {:ok, lane} =
      Catalog.pin_lane(%{
        offer_id: offer.id,
        grade: :cheap,
        supplier_service_id: service.id,
        published: true
      })

    lane
  end
end
