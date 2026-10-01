defmodule ViewNinjasWeb.AirtimeLiveTest do
  @moduledoc """
  Buying airtime (docs/instalipa-airtime.md §8): a single number, a bulk list,
  saved numbers, and the wallet-first pay path.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AirtimeFixtures

  alias ViewNinjas.Airtime
  alias ViewNinjas.Wallet

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/airtime")
  end

  test "buys airtime for one number from the wallet", %{conn: conn} do
    user = funded_user(50_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    html =
      lv
      |> form("#airtime-form", airtime: %{amount: "100", numbers: "0712345678"})
      |> render_submit()

    assert html =~ "On its way"
    assert has_element?(lv, "#airtime-purchased")

    assert [order] = Airtime.list_for_user(user)
    assert order.state == :paid
    assert order.phone == "254712345678"
    assert order.amount_cents == 10_000
    assert Wallet.balance(user) == 40_000
  end

  test "buys a bulk list in one purchase", %{conn: conn} do
    user = funded_user(100_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    lv
    |> form("#airtime-form", airtime: %{amount: "50", numbers: "0712345678\n0722 000 111"})
    |> render_submit()

    orders = Airtime.list_for_user(user)
    assert length(orders) == 2
    assert orders |> Enum.map(& &1.batch_id) |> Enum.uniq() |> length() == 1
    assert Wallet.balance(user) == 90_000
  end

  test "refuses a purchase the wallet cannot cover", %{conn: conn} do
    user = funded_user(5_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    html =
      lv
      |> form("#airtime-form", airtime: %{amount: "100", numbers: "0712345678"})
      |> render_submit()

    assert html =~ "does not cover"
    assert Airtime.list_for_user(user) == []
    assert Wallet.balance(user) == 5_000
  end

  test "rejects a number that is not a Kenyan mobile", %{conn: conn} do
    user = funded_user(50_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    html =
      lv
      |> form("#airtime-form", airtime: %{amount: "100", numbers: "nope"})
      |> render_submit()

    assert html =~ "not a Kenyan mobile number"
    assert Airtime.list_for_user(user) == []
  end

  test "a bought number is remembered and offered back", %{conn: conn} do
    user = funded_user(50_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    lv
    |> form("#airtime-form", airtime: %{amount: "100", numbers: "0712345678"})
    |> render_submit()

    assert [recipient] = Airtime.list_recipients(user)
    assert recipient.phone == "254712345678"
    assert has_element?(lv, "#saved-#{recipient.id}")

    # Tapping it drops the number back into the list.
    html = lv |> element("#saved-#{recipient.id} .vn-recent__add") |> render_click()
    assert html =~ "254712345678"

    # And it can be forgotten from the same pill.
    lv |> element("#saved-#{recipient.id} .vn-recent__forget") |> render_click()
    assert Airtime.list_recipients(user) == []
  end

  test "shows the running total before buying", %{conn: conn} do
    user = funded_user(50_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    html =
      lv
      |> form("#airtime-form", airtime: %{amount: "100", numbers: "0712345678\n0722000111"})
      |> render_change()

    assert html =~ "airtime-summary"
    assert html =~ "KSh 200"
    refute html =~ "vn-summary--short"
  end

  test "warns when the wallet is short of the total", %{conn: conn} do
    user = funded_user(20_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    html =
      lv
      |> form("#airtime-form",
        airtime: %{
          amount: "100",
          numbers: "0712345678\n0722000111\n0733000222"
        }
      )
      |> render_change()

    assert html =~ "vn-summary--short"
    assert html =~ "Add KSh 100"
  end
end
