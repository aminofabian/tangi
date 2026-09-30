defmodule ViewNinjasWeb.Admin.SettlementsLiveTest do
  @moduledoc """
  Settlement reconciliation on screen (build-plan.md M10,
  docs/malipo-connect.md §10). Super-admin only.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Payments

  test "a signed out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/settlements")
  end

  test "an ordinary admin is bounced", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    assert {:error, {:redirect, %{to: "/", flash: _}}} = live(conn, ~p"/admin/settlements")
  end

  test "pasting a clean statement matches, fills the fee and zeroes the delta", %{conn: conn} do
    {payment, line} = settled_payment()
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/settlements")

    lv
    |> form("#settlement-form",
      settlement: %{
        statement_id: "stmt-1",
        received: shillings(line.net),
        text: statement_csv(payment, line)
      }
    )
    |> render_submit()

    assert has_element?(lv, "#bucket-matched")
    assert render(lv) =~ "KSh 0"
    assert Payments.get_payment!(payment.id).fee_cents == line[:fee]
  end

  defp settled_payment do
    order = paid_order_with_lane_fixture()
    payment = payment_fixture(%{order: order})
    {:ok, sent} = Payments.mark_pending(payment, "malipo-#{payment.id}")
    {:ok, settled} = Payments.settle(sent, "RCPT#{payment.id}")

    fee = 750
    line = %{gross: settled.amount_cents, fee: fee, net: settled.amount_cents - fee}
    {settled, line}
  end

  defp statement_csv(payment, line) do
    """
    malipo_id,receipt,gross,fee,net,settled_on
    #{payment.malipo_payment_id},#{payment.receipt},#{shillings(line.gross)},#{shillings(line.fee)},#{shillings(line.net)},#{Date.utc_today()}
    """
  end

  defp shillings(cents),
    do: cents |> Decimal.new() |> Decimal.div(100) |> Decimal.to_string(:normal)
end
