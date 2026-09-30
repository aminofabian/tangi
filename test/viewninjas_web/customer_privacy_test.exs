defmodule ViewNinjasWeb.CustomerPrivacyTest do
  @moduledoc """
  No customer screen names a supplier or carries a supplier id (scope.md §13, §17).

  The panels are the back office's business. A customer sees a grade, a price and a
  state — never "Secsers", never an order id belonging to somebody else's system.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.CatalogFixtures
  import ViewNinjas.SuppliersFixtures

  alias ViewNinjas.{Catalog, Orders, Repo, Suppliers}
  alias ViewNinjas.Suppliers.SupplierService

  # The panel names that must not appear anywhere a customer can reach (§17).
  @panel_names ~w(secsers jap smmfollows)
  @supplier_order_id "99887766"

  setup %{conn: conn} do
    supplier = supplier_fixture(%{slug: "secsers"})
    {:ok, _stats} = Suppliers.ingest_services(supplier, [service_attrs(%{external_id: "777"})])
    service = Repo.get_by!(SupplierService, supplier_id: supplier.id, external_id: "777")

    offer = offer_fixture(%{published: true})

    {:ok, _lane} =
      Catalog.pin_lane(%{
        offer_id: offer.id,
        grade: :cheap,
        supplier_service_id: service.id,
        published: true
      })

    user = verified_user_fixture()
    lane = Catalog.get_offer!(offer.id).lanes |> List.first()

    {:ok, order} =
      Orders.create_order(%{
        user: user,
        lane: lane,
        link: "https://instagram.com/viewninjas",
        quantity: 1000
      })

    {:ok, paid} = Orders.mark_paid(order, "RCPT1")
    {:ok, placing} = Orders.mark_placing(paid, supplier.id, service.id)
    {:ok, placed} = Orders.mark_placed(placing, @supplier_order_id)

    %{conn: log_in_user(conn, user), offer: offer, order: placed}
  end

  test "no customer screen names a panel or shows a supplier order id", %{
    conn: conn,
    offer: offer,
    order: order
  } do
    paths = ["/", "/shop", "/refunds", "/orders", "/orders/#{order.id}", "/offers/#{offer.id}"]

    for path <- paths do
      {:ok, _lv, html} = live(conn, path)

      for panel <- @panel_names do
        refute html =~ panel, "#{panel} leaked on #{path}"
      end

      refute html =~ @supplier_order_id, "the supplier order id leaked on #{path}"
    end
  end

  test "the admin side of the same order still has the id, for staff", %{order: order} do
    # The id belongs on the order row (admin), just not on a customer screen.
    assert Orders.get_order!(order.id).supplier_order_id == @supplier_order_id
  end
end
