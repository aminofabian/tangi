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

  test "saves a number, offers it back, and removes it", %{conn: conn} do
    user = funded_user(50_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    lv
    |> form("#recipient-form", recipient: %{phone: "0712 345 678", label: "Mum"})
    |> render_submit()

    assert [recipient] = Airtime.list_recipients(user)
    assert recipient.phone == "254712345678"
    assert has_element?(lv, "#saved-#{recipient.id}", "Mum")

    # The picker drops the number into the list.
    html = lv |> element("#use-#{recipient.id}") |> render_click()
    assert html =~ "254712345678"

    # And it can be removed.
    lv |> element("#saved-#{recipient.id} button") |> render_click()
    assert Airtime.list_recipients(user) == []
    assert has_element?(lv, "#saved-recipients", "No saved numbers yet")
  end
end
