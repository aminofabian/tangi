defmodule ViewNinjasWeb.OrdersLiveTest do
  @moduledoc """
  The Orders tab (build-plan.md M8, scope.md §11): the customer's own orders,
  newest first, and the state pill that moves on its own.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Catalog, Orders}

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/orders")
  end

  test "a customer with no orders is invited to the shop", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders")

    assert has_element?(lv, "#no-orders")
  end

  test "the customer's orders are listed with their state pills", %{conn: conn} do
    user = verified_user_fixture()
    placed = supplier_order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders")

    assert has_element?(lv, "#orders")
    assert has_element?(lv, "#order-#{placed.id}")
    assert has_element?(lv, "#order-#{placed.id} .vn-state--placed")
  end

  test "only the customer's own orders appear", %{conn: conn} do
    user = verified_user_fixture()
    other = verified_user_fixture()
    mine = supplier_order_fixture(%{user: user})
    theirs = supplier_order_fixture(%{user: other})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders")

    assert has_element?(lv, "#order-#{mine.id}")
    refute has_element?(lv, "#order-#{theirs.id}")
  end

  test "a status change swaps the row in place", %{conn: conn} do
    user = verified_user_fixture()
    placed = supplier_order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders")
    assert has_element?(lv, "#order-#{placed.id} .vn-state--placed")

    {:ok, _} =
      Orders.apply_supplier_status(placed, %{
        status: "Completed",
        start_count: 0,
        remains: 0,
        charge_usd_micros: 1_000_000,
        currency: "USD"
      })

    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#order-#{placed.id} .vn-state--completed")
  end

  test "an unpaid order offers finish paying, and not a second copy", %{conn: conn} do
    user = verified_user_fixture()
    order = order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders")

    assert has_element?(lv, "#open-payments")
    assert has_element?(lv, "#finish-#{order.id}")
    refute has_element?(lv, "#reorder-#{order.id}")

    path = "/checkout/#{order.id}"

    assert {:error, {:live_redirect, %{to: ^path}}} =
             lv |> element("#finish-#{order.id}") |> render_click()
  end

  test "a placed order can be ordered again, at a new checkout", %{conn: conn} do
    user = verified_user_fixture()
    placed = supplier_order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders")

    refute has_element?(lv, "#open-payments")
    assert has_element?(lv, "#reorder-#{placed.id}")

    assert {:error, {:live_redirect, %{to: to}}} =
             lv |> element("#reorder-#{placed.id}") |> render_click()

    "/checkout/" <> id = to
    fresh = Orders.get_order!(String.to_integer(id))
    assert fresh.id != placed.id
    assert fresh.state == :awaiting_payment
    assert fresh.link == placed.link
    assert fresh.quantity == placed.quantity
  end

  test "a grade that has come off sale sends the buyer back to the offer", %{conn: conn} do
    user = verified_user_fixture()
    placed = supplier_order_fixture(%{user: user})
    {:ok, _} = Catalog.unpublish_lane(Catalog.get_lane!(placed.lane_id))
    offer_id = Orders.get_order_for_user(user, placed.id).lane.offer.id
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders")

    assert {:error, {:live_redirect, %{to: to}}} =
             lv |> element("#reorder-#{placed.id}") |> render_click()

    assert to =~ "/offers/#{offer_id}?"
    assert URI.decode_query(URI.parse(to).query)["link"] == placed.link
    assert URI.decode_query(URI.parse(to).query)["quantity"] == to_string(placed.quantity)
  end
end
