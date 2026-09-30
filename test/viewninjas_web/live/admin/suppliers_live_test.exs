defmodule ViewNinjasWeb.Admin.SuppliersLiveTest do
  use ViewNinjasWeb.ConnCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.SuppliersFixtures

  alias ViewNinjas.Suppliers
  alias ViewNinjas.Workers.{CheckSupplierBalance, SyncSupplierServices}

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/admin/suppliers")
  end

  test "a signed in customer is bounced to the shop", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/suppliers")
  end

  test "an admin sees each panel and the raw catalog", %{conn: conn} do
    supplier = supplier_fixture(%{slug: "secsers"})

    {:ok, _} =
      Suppliers.ingest_services(supplier, [
        service_attrs(%{external_id: "902", name: "IG followers - refill"})
      ])

    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, html} = live(conn, ~p"/admin/suppliers")

    assert html =~ "secsers"
    assert has_element?(lv, "#supplier-secsers")
    assert has_element?(lv, "#sync-secsers")
    assert html =~ "IG followers - refill"
  end

  test "the manual triggers enqueue jobs", %{conn: conn} do
    supplier = supplier_fixture(%{slug: "secsers"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    lv |> element("#check-secsers") |> render_click()
    assert_enqueued(worker: CheckSupplierBalance, args: %{"supplier_id" => supplier.id})

    lv |> element("#sync-secsers") |> render_click()
    assert_enqueued(worker: SyncSupplierServices, args: %{"supplier_id" => supplier.id})
  end

  test "a balance arrives over PubSub", %{conn: conn} do
    supplier_fixture(%{slug: "secsers"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    Suppliers.broadcast({:balance, "secsers", 12_500_000})
    _ = :sys.get_state(lv.pid)

    assert render(lv) =~ "12.50"
  end

  test "a rejected key shows one clear error, not a stack trace", %{conn: conn} do
    supplier_fixture(%{slug: "secsers"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    Suppliers.broadcast({:balance_failed, "secsers", {:api_error, "Incorrect API key"}})
    _ = :sys.get_state(lv.pid)

    assert render(lv) =~ "panel rejected the key: Incorrect API key"
  end

  test "an admin sets a panel key, stored encrypted and never echoed back", %{conn: conn} do
    supplier = supplier_fixture(%{slug: "secsers", api_key: "old-key"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    assert has_element?(lv, "#supplier-form-secsers")

    lv
    |> form("#supplier-form-secsers", supplier: %{"api_key" => "fresh-key-999"})
    |> render_submit()

    assert Suppliers.get_supplier!(supplier.id).api_key == "fresh-key-999"

    %{rows: [[stored]]} =
      ViewNinjas.Repo.query!("select encrypted_api_key from suppliers where id = $1", [
        supplier.id
      ])

    refute stored =~ "fresh-key-999"
    refute render(lv) =~ "fresh-key-999"
  end

  test "a blank key leaves the stored key alone", %{conn: conn} do
    supplier = supplier_fixture(%{slug: "secsers", api_key: "keep-me"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    lv
    |> form("#supplier-form-secsers", supplier: %{"base_url" => "https://secsers.example/api/v2"})
    |> render_submit()

    saved = Suppliers.get_supplier!(supplier.id)
    assert saved.api_key == "keep-me"
    assert saved.base_url == "https://secsers.example/api/v2"
  end

  test "a base URL that is not https is refused with a message", %{conn: conn} do
    supplier = supplier_fixture(%{slug: "secsers", base_url: "https://secsers.example/api/v2"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    html =
      lv
      |> form("#supplier-form-secsers", supplier: %{"base_url" => "http://insecure.example"})
      |> render_submit()

    assert html =~ "must be an https URL"
    assert Suppliers.get_supplier!(supplier.id).base_url == "https://secsers.example/api/v2"
  end

  test "the active flag and capabilities are saved from the panel form", %{conn: conn} do
    supplier = supplier_fixture(%{slug: "secsers", active: false})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    lv
    |> form("#supplier-form-secsers",
      supplier: %{
        "active" => "true",
        "cap_cancel" => "true",
        "cap_refill" => "false",
        "multi_status_limit" => "25"
      }
    )
    |> render_submit()

    saved = Suppliers.get_supplier!(supplier.id)
    assert saved.active
    assert saved.capabilities["cancel"] == true
    refute saved.capabilities["refill"]
    assert saved.capabilities["multi_status_limit"] == 25
  end

  test "a bad multi-status limit is refused without saving", %{conn: conn} do
    supplier = supplier_fixture(%{slug: "secsers"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    lv
    |> form("#supplier-form-secsers", supplier: %{"multi_status_limit" => "lots"})
    |> render_submit()

    assert render(lv) =~ "whole number"
    assert Suppliers.get_supplier!(supplier.id).capabilities["multi_status_limit"] == 100
  end

  test "picking a panel swaps the detail and the form", %{conn: conn} do
    supplier_fixture(%{slug: "alpha", base_url: "https://alpha.example/api/v2"})
    supplier_fixture(%{slug: "zeta", base_url: "https://zeta.example/api/v2"})

    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    # Both are rows in the list; only one of them is the panel on show.
    assert has_element?(lv, "#supplier-alpha")
    assert has_element?(lv, "#supplier-zeta")

    lv |> element("#supplier-zeta") |> render_click()

    assert has_element?(lv, "#supplier-zeta[aria-current='true']")
    assert has_element?(lv, "#supplier-form-zeta")
    assert has_element?(lv, "#save-zeta")
    refute has_element?(lv, "#supplier-form-alpha")
    refute has_element?(lv, "#save-alpha")
    assert render(lv) =~ "https://zeta.example/api/v2"
  end

  test "a new panel is created from the add-panel form", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/suppliers")

    assert has_element?(lv, "#new-supplier-form")

    lv
    |> form("#new-supplier-form",
      supplier: %{
        "slug" => "fourth",
        "base_url" => "https://fourth.example/api/v2",
        "api_key" => "fourth-key",
        "active" => "true"
      }
    )
    |> render_submit()

    assert %{slug: "fourth", active: true} = Suppliers.get_supplier_by_slug("fourth")
    assert has_element?(lv, "#supplier-fourth")
    assert has_element?(lv, "#save-fourth")
  end
end
