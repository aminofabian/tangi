defmodule ViewNinjasWeb.Admin.CostsLiveTest do
  @moduledoc """
  Costs and targets (build-plan.md M10, scope.md §11). Super-admin only.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures

  alias ViewNinjas.Progress

  test "a signed out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/costs")
  end

  test "an ordinary admin is bounced", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    assert {:error, {:redirect, %{to: "/", flash: _}}} = live(conn, ~p"/admin/costs")
  end

  test "a cost is recorded in shillings", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/costs")

    lv
    |> form("#cost-form",
      cost: %{
        kind: "hosting",
        amount: "1500",
        incurred_on: Date.to_iso8601(Date.utc_today()),
        note: "VPS"
      }
    )
    |> render_submit()

    assert render(lv) =~ "KSh 1,500"
    assert render(lv) =~ "VPS"
  end

  test "a target is set, money in shillings and margin in percent", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/costs")

    lv
    |> form("#target-form", target: %{metric: "revenue", period: "month", value: "5000"})
    |> render_submit()

    assert [%{metric: :revenue, period: :month, value_cents: 500_000}] =
             Progress.current_targets()

    lv
    |> form("#target-form", target: %{metric: "margin", period: "month", value: "45"})
    |> render_submit()

    assert Enum.any?(
             Progress.current_targets(),
             &(&1.metric == :margin and &1.value_cents == 4_500)
           )
  end
end
