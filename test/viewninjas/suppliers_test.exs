defmodule ViewNinjas.SuppliersTest do
  use ViewNinjas.DataCase, async: true

  import ViewNinjas.SuppliersFixtures

  alias ViewNinjas.Suppliers
  alias ViewNinjas.Suppliers.SupplierService

  describe "suppliers" do
    test "the API key is encrypted at rest and redacted in logs" do
      supplier = supplier_fixture(%{api_key: "plaintext-key-123"})

      %{rows: [[stored]]} =
        Repo.query!("select encrypted_api_key from suppliers where id = $1", [supplier.id])

      refute stored =~ "plaintext-key-123"
      assert Suppliers.get_supplier!(supplier.id).api_key == "plaintext-key-123"
      refute inspect(Suppliers.get_supplier!(supplier.id)) =~ "plaintext-key-123"
    end

    test "upsert is idempotent by slug" do
      attrs = %{
        slug: "secsers",
        base_url: "https://secsers.com/api/v2",
        api_key: "first-key",
        capabilities: %{"cancel" => false}
      }

      assert {:ok, supplier} = Suppliers.upsert_supplier(attrs)
      assert supplier.api_key == "first-key"

      assert {:ok, updated} =
               Suppliers.upsert_supplier(
                 Map.merge(attrs, %{api_key: "rotated-key", active: true})
               )

      assert updated.id == supplier.id
      assert updated.api_key == "rotated-key"
      assert updated.active
      assert Suppliers.list_suppliers() |> length() == 1
    end

    test "record_balance/2 stores micros and the time" do
      supplier = supplier_fixture()
      assert {:ok, recorded} = Suppliers.record_balance(supplier, 1_234_000)
      assert recorded.last_balance_micros == 1_234_000
      assert recorded.last_balance_at
    end
  end

  describe "the back office panel form (M12)" do
    test "a blank key leaves the stored key alone; a typed one rotates it" do
      supplier = supplier_fixture(%{api_key: "keep-me"})

      assert {:ok, untouched} =
               Suppliers.update_supplier_config(supplier, %{
                 "base_url" => "https://new.test/api/v2",
                 "api_key" => "  "
               })

      assert untouched.api_key == "keep-me"
      assert untouched.base_url == "https://new.test/api/v2"

      assert {:ok, rotated} = Suppliers.update_supplier_config(supplier, %{"api_key" => "new"})
      assert rotated.api_key == "new"
    end

    test "capabilities are merged over the panel's existing set" do
      supplier = supplier_fixture(%{capabilities: %{"cancel" => false, "bespoke" => "kept"}})

      assert {:ok, updated} =
               Suppliers.update_supplier_config(supplier, %{
                 "cap_cancel" => "true",
                 "cap_refill" => "false",
                 "multi_status_limit" => "25"
               })

      assert updated.capabilities["cancel"] == true
      assert updated.capabilities["refill"] == false
      assert updated.capabilities["multi_status_limit"] == 25
      assert updated.capabilities["bespoke"] == "kept"
    end

    test "a bad multi-status limit is refused" do
      supplier = supplier_fixture()

      assert {:error, :invalid_limit} =
               Suppliers.update_supplier_config(supplier, %{"multi_status_limit" => "lots"})

      assert {:error, :invalid_limit} =
               Suppliers.update_supplier_config(supplier, %{"multi_status_limit" => "0"})
    end

    test "a fourth panel is created from the form" do
      assert {:ok, supplier} =
               Suppliers.create_supplier_config(%{
                 "slug" => "fourth",
                 "base_url" => "https://fourth.test/api/v2",
                 "api_key" => "fourth-key",
                 "cap_cancel" => "true"
               })

      assert supplier.slug == "fourth"
      assert supplier.api_key == "fourth-key"
      assert supplier.capabilities["cancel"] == true
      refute supplier.capabilities["refill"]
    end

    test "a new panel without a key is refused" do
      assert {:error, %Ecto.Changeset{}} =
               Suppliers.create_supplier_config(%{
                 "slug" => "keyless",
                 "base_url" => "https://keyless.test/api/v2"
               })

      assert Suppliers.get_supplier_by_slug("keyless") == nil
    end
  end

  describe "ingest_services/2" do
    test "upserts a whole pull and deactivates what is missing" do
      supplier = supplier_fixture()

      services = [
        service_attrs(%{external_id: "1", rate_micros: 900_000}),
        service_attrs(%{external_id: "2", rate_micros: 50_000})
      ]

      assert {:ok, %{received: 2, active: 2, deactivated: 0}} =
               Suppliers.ingest_services(supplier, services)

      # A second pull where 2 has been withdrawn and 1 changed price.
      second_pull = [service_attrs(%{external_id: "1", rate_micros: 1_000_000})]

      assert {:ok, %{received: 1, active: 1, deactivated: 1}} =
               Suppliers.ingest_services(supplier, second_pull)

      # Nothing is deleted: 2 is still there, just inactive.
      assert Suppliers.count_services(supplier) == 2

      assert Repo.get_by!(SupplierService, supplier_id: supplier.id, external_id: "1").rate_micros ==
               1_000_000

      refute Repo.get_by!(SupplierService, supplier_id: supplier.id, external_id: "2").active
    end

    test "a service that reappears becomes active again" do
      supplier = supplier_fixture()
      service = service_attrs(%{external_id: "7"})

      assert {:ok, _} = Suppliers.ingest_services(supplier, [service])
      assert {:ok, %{deactivated: 1}} = Suppliers.ingest_services(supplier, [])
      assert {:ok, %{active: 1, deactivated: 0}} = Suppliers.ingest_services(supplier, [service])
    end

    test "two pulls in the same second are still exact" do
      supplier = supplier_fixture()

      assert {:ok, _} =
               Suppliers.ingest_services(supplier, [
                 service_attrs(%{external_id: "a"}),
                 service_attrs(%{external_id: "b"})
               ])

      assert {:ok, %{active: 1, deactivated: 1}} =
               Suppliers.ingest_services(supplier, [service_attrs(%{external_id: "a"})])
    end
  end

  describe "helpers" do
    test "format_usd_micros/1" do
      assert Suppliers.format_usd_micros(1_234_000) == "1.23"
      assert Suppliers.format_usd_micros(900_000) == "0.90"
      assert Suppliers.format_usd_micros(nil) == nil
    end

    test "error_message/1 is one sentence" do
      assert Suppliers.error_message({:api_error, "Incorrect API key"}) =~
               "panel rejected the key: Incorrect API key"

      assert Suppliers.error_message({:http_error, 502, "bad"}) =~ "HTTP 502"
      assert Suppliers.error_message({:transport, :timeout}) =~ "could not reach the panel"
      assert Suppliers.error_message({:invalid_response, %{}}) =~ "could not read"
    end

    test "retryable_error?/1 is only true for transient failures" do
      assert Suppliers.retryable_error?({:transport, :timeout})
      assert Suppliers.retryable_error?({:http_error, 503, "down"})
      refute Suppliers.retryable_error?({:api_error, "Incorrect API key"})
      refute Suppliers.retryable_error?({:http_error, 403, "nope"})
      refute Suppliers.retryable_error?({:invalid_response, %{}})
    end

    test "definite_error?/1 is the line between a no and an unknown" do
      assert Suppliers.definite_error?({:api_error, "Incorrect API key"})
      assert Suppliers.definite_error?({:http_error, 422, "bad"})
      refute Suppliers.definite_error?({:http_error, 503, "down"})
      refute Suppliers.definite_error?({:transport, :timeout})
      refute Suppliers.definite_error?({:invalid_response, %{}})
    end
  end

  describe "the float (M9)" do
    test "a panel is paused once and resumed once" do
      supplier = supplier_fixture()
      Suppliers.subscribe()

      {:ok, paused} = Suppliers.pause(supplier, "under the float")
      assert Suppliers.paused?(paused)
      assert_receive {:suppliers, {:paused, _slug, "under the float"}}

      # Pausing again is a no-op, not a second event.
      {:ok, _again} = Suppliers.pause(paused, "under the float")
      refute_received {:suppliers, {:paused, _slug, _reason}}

      {:ok, resumed} = Suppliers.resume(paused)
      refute Suppliers.paused?(resumed)
      assert_receive {:suppliers, {:resumed, _slug}}
    end

    test "low_balance?/1 is under the configured floor" do
      assert Suppliers.low_balance?(Suppliers.low_balance_micros() - 1)
      refute Suppliers.low_balance?(Suppliers.low_balance_micros())
      refute Suppliers.low_balance?(nil)
    end
  end
end
