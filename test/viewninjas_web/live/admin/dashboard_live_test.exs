defmodule ViewNinjasWeb.Admin.DashboardLiveTest do
  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  test "a signed out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin")
  end

  test "a signed in customer is bounced to the shop", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin")
    assert flash["error"] =~ "don't have access"
  end

  test "an admin gets in", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    {:ok, _lv, html} = live(conn, ~p"/admin")

    assert html =~ "admin"
  end

  test "a super admin gets in", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, _lv, html} = live(conn, ~p"/admin")

    assert html =~ "super_admin"
  end

  test "an admin reads the M9 overview", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin")

    assert has_element?(lv, "#funnel")
    assert has_element?(lv, "#money-at-risk")
    assert has_element?(lv, "#payments-settled")
    assert has_element?(lv, "#margin")
    assert has_element?(lv, "#funnel-completed")
    assert has_element?(lv, "#sms-today")
    assert has_element?(lv, "#health")
    assert has_element?(lv, "#health-settled-rate")
    assert has_element?(lv, "#health-queue")
  end

  test "an alert lands on the open screen", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin")

    ViewNinjas.Alerts.publish(:supplier_paused, "panel-x is under its float")
    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#alerts")
    assert render(lv) =~ "panel-x is under its float"
  end
end
