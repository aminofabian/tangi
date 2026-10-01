defmodule ViewNinjasWeb.Admin.NavTest do
  @moduledoc """
  The back office's own chrome (build-plan.md). The customer tab bar stays out of
  it, and the section strip only offers what the signed-in role can reach —
  otherwise an operator is one tap from a redirect.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  @staff_sections ~w(admin-nav-overview admin-nav-orders admin-nav-suppliers admin-nav-catalog)
  @super_sections ~w(admin-nav-pricing admin-nav-costs admin-nav-settlements admin-nav-insight)

  test "a super-admin sees every section", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin")

    for id <- @staff_sections ++ @super_sections do
      assert has_element?(lv, "##{id}"), "expected #{id}"
    end
  end

  test "an ordinary admin is not offered the money pages", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin")

    for id <- @staff_sections, do: assert(has_element?(lv, "##{id}"))
    for id <- @super_sections, do: refute(has_element?(lv, "##{id}"))
  end

  test "the section you are on is the one marked current", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    for {path, id} <- [
          {~p"/admin", "admin-nav-overview"},
          {~p"/admin/orders", "admin-nav-orders"},
          {~p"/admin/catalog", "admin-nav-catalog"},
          {~p"/admin/settlements", "admin-nav-settlements"}
        ] do
      {:ok, lv, _html} = live(conn, path)

      assert has_element?(lv, "##{id}[aria-current='page']"), "expected #{id} to be current"
      assert has_element?(lv, "nav[aria-label='Back office']")
    end
  end

  test "the back office gives up the customer tab bar", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin")

    refute has_element?(lv, "nav.vn-tabbar")
    assert has_element?(lv, "nav.vn-admin-nav")
    refute has_element?(lv, "#pwa-install")
  end

  test "the shop keeps its own tabs and no section strip", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    {:ok, lv, _html} = live(conn, ~p"/")

    assert has_element?(lv, "nav.vn-tabbar")
    refute has_element?(lv, "nav.vn-admin-nav")
    # The install nudge belongs to the customer shell only.
    assert has_element?(lv, "#pwa-install")
  end

  test "a staff account browsing the shop is not shown the section strip", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/shop")

    assert has_element?(lv, "nav.vn-tabbar")
    refute has_element?(lv, "nav.vn-admin-nav")
  end
end
