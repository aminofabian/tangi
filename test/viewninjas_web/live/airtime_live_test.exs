defmodule ViewNinjasWeb.AirtimeLiveTest do
  @moduledoc """
  Buying airtime (docs/instalipa-airtime.md §8): a single number, a bulk list,
  saved numbers, and the wallet-first pay path.
  """

  use ViewNinjasWeb.ConnCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import Phoenix.LiveViewTest
  import ViewNinjas.AirtimeFixtures

  alias ViewNinjas.Airtime
  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.Providers.Test
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.{ConfirmPayment, CreatePayment}

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

  test "a buy the wallet cannot cover offers the difference, not a dead end", %{conn: conn} do
    user = funded_user(20_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    html =
      lv
      |> form("#airtime-form",
        airtime: %{amount: "100", numbers: "0712345678\n0722000111\n0733000222"}
      )
      |> render_submit()

    # Nothing was spent, and the page says how to close the gap instead of stopping.
    assert Airtime.list_for_user(user) == []
    assert Wallet.balance(user) == 20_000

    assert has_element?(lv, "#airtime-short")
    assert has_element?(lv, "#pay-shortfall")
    # The exact difference, then rounder deposits that leave money behind.
    assert html =~ "Pay KSh 100 with M-Pesa"
    assert has_element?(lv, "#topup-200")
    assert has_element?(lv, "#topup-500")
    assert html =~ "KSh 100 left in your wallet"
    assert html =~ "KSh 400 left in your wallet"
  end

  test "paying the difference raises a top-up for exactly that, and the buy goes out on settle",
       %{conn: conn} do
    user = funded_user(20_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    lv
    |> form("#airtime-form",
      airtime: %{amount: "100", numbers: "0712345678\n0722000111\n0733000222"}
    )
    |> render_change()

    lv |> element("#pay-shortfall") |> render_click()

    assert has_element?(lv, "#payment-sheet")
    payment = Payments.pending_topup(user)
    assert payment.purpose == :topup
    assert payment.amount_cents == 10_000

    # The money lands, and the airtime the customer asked for goes out by itself.
    assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})
    Test.settle!(Payments.get_payment!(payment.id).malipo_payment_id, "R1")
    assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})
    _ = :sys.get_state(lv.pid)

    orders = Airtime.list_for_user(user)
    assert length(orders) == 3
    assert Enum.all?(orders, &(&1.amount_cents == 10_000))
    assert Wallet.balance(user) == 0
    assert has_element?(lv, "#airtime-purchased")
  end

  test "depositing more than the difference covers the buy and keeps the rest", %{conn: conn} do
    user = funded_user(20_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    lv
    |> form("#airtime-form",
      airtime: %{amount: "100", numbers: "0712345678\n0722000111\n0733000222"}
    )
    |> render_change()

    lv |> element("#topup-200") |> render_click()

    payment = Payments.pending_topup(user)
    assert payment.amount_cents == 20_000

    assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})
    Test.settle!(Payments.get_payment!(payment.id).malipo_payment_id, "R1")
    assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})
    _ = :sys.get_state(lv.pid)

    assert length(Airtime.list_for_user(user)) == 3
    # KSh 200 in the wallet + KSh 200 deposited − KSh 300 spent = KSh 100 kept.
    assert Wallet.balance(user) == 10_000
    assert render(lv) =~ "KSh 100"
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
    assert html =~ "Your wallet is short"
    assert has_element?(lv, "#airtime-short")
    assert html =~ "Pay KSh 100 with M-Pesa"
  end

  test "the short-fall block clears once the wallet can cover it", %{conn: conn} do
    user = funded_user(20_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime")

    lv
    |> form("#airtime-form",
      airtime: %{amount: "100", numbers: "0712345678\n0722000111\n0733000222"}
    )
    |> render_change()

    assert has_element?(lv, "#airtime-short")

    html =
      lv
      |> form("#airtime-form",
        airtime: %{amount: "50", numbers: "0712345678\n0722000111\n0733000222"}
      )
      |> render_change()

    refute html =~ "vn-summary--short"
    refute has_element?(lv, "#airtime-short")
    assert has_element?(lv, "#airtime-submit")
  end
end
