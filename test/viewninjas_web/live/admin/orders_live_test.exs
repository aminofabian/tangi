defmodule ViewNinjasWeb.Admin.OrdersLiveTest do
  @moduledoc """
  The admin review queue (build-plan.md M9, scope.md §11): the orders a person has
  to reconcile, and the two ways to do it.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Orders, Wallet}

  test "a signed out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/orders")
  end

  test "a signed in customer is bounced to the shop", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/", flash: _}}} = live(conn, ~p"/admin/orders")
  end

  test "a needs_review order can be reconciled by attaching the supplier id", %{conn: conn} do
    order = paid_order_with_lane_fixture()
    {:ok, reviewed} = Orders.mark_needs_review(order, "the add never resolved")
    conn = log_in_user(conn, admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/orders")
    assert has_element?(lv, "#order-#{reviewed.id}")

    lv
    |> form("#attach-form-#{reviewed.id}",
      attach: %{order_id: reviewed.id, supplier_order_id: "55221"}
    )
    |> render_submit()

    assert Orders.get_order!(reviewed.id).state == :placed
    assert Orders.get_order!(reviewed.id).supplier_order_id == "55221"
    # It leaves the queue.
    refute has_element?(lv, "#order-#{reviewed.id}")
  end

  test "a needs_review order can be refunded instead", %{conn: conn} do
    order = paid_order_with_lane_fixture()
    {:ok, reviewed} = Orders.mark_needs_review(order, "the add never resolved")
    conn = log_in_user(conn, admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/orders")

    lv |> element("#refund-#{reviewed.id}") |> render_click()

    assert Orders.get_order!(reviewed.id).state == :refunded
    assert Wallet.balance(order.user_id) == order.retail_cents
  end

  test "the partial filter shows what was already credited", %{conn: conn} do
    partial = partial_order_fixture(%{quantity: 1000, remains: 250})
    conn = log_in_user(conn, admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/orders?state=partial")

    assert has_element?(lv, "#order-#{partial.id}")
    assert render(lv) =~ "Already credited"
  end

  test "an empty queue says so", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/orders")

    assert has_element?(lv, "#no-orders")
  end
end
