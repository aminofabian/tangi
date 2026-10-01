defmodule ViewNinjasWeb.OrderLiveTest do
  @moduledoc """
  One order, live (build-plan.md M8, scope.md §11): the details, the timeline,
  and the in-place update as the panel reports movement.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Orders

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/orders/1")
  end

  test "the order shows its details and timeline", %{conn: conn} do
    user = verified_user_fixture()
    paid = paid_order_with_lane_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders/#{paid.id}")

    assert has_element?(lv, "#journey")
    assert has_element?(lv, "#runway")
    assert has_element?(lv, "#runway-now", "sending it now")
    assert has_element?(lv, "#order-summary")
    assert has_element?(lv, "#order-summary .vn-state--paid")
    assert has_element?(lv, "#timeline")
    assert render(lv) =~ paid.link
  end

  test "someone else's order is not reachable", %{conn: conn} do
    user = verified_user_fixture()
    other = verified_user_fixture()
    theirs = paid_order_with_lane_fixture(%{user: other})
    conn = log_in_user(conn, user)

    assert {:error, {_kind, %{to: "/orders"}}} = live(conn, ~p"/orders/#{theirs.id}")
  end

  test "a needs_review order says a person is on it", %{conn: conn} do
    user = verified_user_fixture()
    paid = paid_order_with_lane_fixture(%{user: user})
    {:ok, _} = Orders.mark_needs_review(paid, "the add never resolved")
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders/#{paid.id}")

    assert has_element?(lv, "#order-summary .vn-state--needs_review")
    assert render(lv) =~ "checking this order"
  end

  test "a status change updates the page in place", %{conn: conn} do
    user = verified_user_fixture()
    placed = supplier_order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders/#{placed.id}")
    assert has_element?(lv, "#order-summary .vn-state--placed")

    {:ok, _} =
      Orders.apply_supplier_status(placed, %{
        status: "In progress",
        start_count: 100,
        remains: 42,
        charge_usd_micros: 1_080_000,
        currency: "USD"
      })

    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#order-summary .vn-state--in_progress")
    assert render(lv) =~ "42"
  end

  test "a completed order sold with refill offers the one refill", %{conn: conn} do
    user = verified_user_fixture()
    order = completed_order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/orders/#{order.id}")
    assert has_element?(lv, "#refill-button")

    lv |> element("#refill-button") |> render_click()

    assert has_element?(lv, "#refill-status")
    refute has_element?(lv, "#refill-button")
  end
end
