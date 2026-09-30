defmodule ViewNinjasWeb.Admin.InsightLiveTest do
  @moduledoc """
  The insight screen (build-plan.md M10, scope.md §11): profit, progress and
  traffic on one page, super-admin only.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  test "a signed out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/insight")
  end

  test "an ordinary admin is bounced", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    assert {:error, {:redirect, %{to: "/", flash: _}}} = live(conn, ~p"/admin/insight")
  end

  test "a super-admin reads the profit, progress and traffic", %{conn: conn} do
    _order = paid_order_with_lane_fixture()
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/insight")

    assert has_element?(lv, "#profit")
    assert has_element?(lv, "#profit-revenue")
    assert has_element?(lv, "#break-even")
    assert has_element?(lv, "#progress")
    assert has_element?(lv, "#streak")
    assert has_element?(lv, "#repeat-rate")
    assert has_element?(lv, "#traffic")
    assert has_element?(lv, "#funnel-shop")
    assert has_element?(lv, "#digest-body")
  end

  test "the funnel marks the biggest leak", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    # Two visitors reach the shop, one opens an offer, none start checkout.
    view(conn, "/", "1.1.1.1")
    view(conn, "/", "2.2.2.2")
    view(conn, "/offers/1", "1.1.1.1")

    {:ok, lv, _html} = live(conn, ~p"/admin/insight")

    assert has_element?(lv, "#biggest-leak")
  end

  test "the admin dashboard links to insight for the super-admin", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin")

    assert has_element?(lv, "#admin-insight-link")
  end

  defp view(conn, path, ip) do
    ViewNinjas.Insight.record_page_view(%{
      path: path,
      at: DateTime.utc_now(:second),
      ip: ip,
      user_agent: "Mozilla/5.0 (iPhone)"
    })

    conn
  end
end
