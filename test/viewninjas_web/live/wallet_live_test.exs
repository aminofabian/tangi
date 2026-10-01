defmodule ViewNinjasWeb.WalletLiveTest do
  @moduledoc """
  The wallet screen (build-plan.md M7, scope.md §8, §11): the derived balance, the
  ledger, and a top-up that is settled by a confirming GET.
  """

  use ViewNinjasWeb.ConnCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Payments, Wallet}
  alias ViewNinjas.Payments.Providers.Test
  alias ViewNinjas.Workers.{ConfirmPayment, CreatePayment}

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/wallet")
  end

  test "the balance is the sum of the ledger, shown with its rows", %{conn: conn} do
    user = verified_user_fixture()
    credit_fixture(user, 25_000)
    credit_fixture(user, -4_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/wallet")

    assert has_element?(lv, "#wallet-balance")
    assert render(lv) =~ "KSh 210"
    # A debit renders negative, an adjustment is labelled.
    assert render(lv) =~ "−KSh 40"
  end

  test "a top-up shows the sheet, and a settled GET credits the ledger", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/wallet")

    lv
    |> form("#topup-form", topup: %{amount: "100"})
    |> render_submit()

    assert has_element?(lv, "#payment-sheet")

    payment = Payments.pending_topup(user)
    assert payment.amount_cents == 10_000
    assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})
    Test.settle!(Payments.get_payment!(payment.id).malipo_payment_id, "R1")
    assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})
    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#payment-succeeded")
    assert Wallet.balance(user) == 10_000
    assert render(lv) =~ "KSh 100"
  end

  test "a rejected prompt shows the failure and charges nothing", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/wallet")

    lv
    |> form("#topup-form", topup: %{amount: "100"})
    |> render_submit()

    payment = Payments.pending_topup(user)
    Test.reject_create!(payment.idempotency_key)
    assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})
    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#payment-failed")
    assert Wallet.balance(user) == 0
  end

  test "any whole-shilling amount can be topped up, not only the shortcuts", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/wallet")

    lv |> form("#topup-form", topup: %{amount: "15"}) |> render_submit()

    payment = Payments.pending_topup(user)
    assert payment.amount_cents == 1_500
  end

  test "an amount chip fills the field and does not start a payment", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/wallet")

    html = lv |> element("#topup-amount-200") |> render_click()

    assert html =~ ~s(value="200")
    assert has_element?(lv, "#topup-amount-200.vn-chip--on")
    assert Payments.pending_topup(user) == nil
  end

  test "the amount is validated before any prompt", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/wallet")

    html = lv |> form("#topup-form", topup: %{amount: "0"}) |> render_submit()
    assert html =~ "whole number of shillings"
    assert Payments.pending_topup(user) == nil

    html = lv |> form("#topup-form", topup: %{amount: "lots"}) |> render_submit()
    assert html =~ "whole number of shillings"
    assert Payments.pending_topup(user) == nil
    assert all_enqueued(worker: CreatePayment) == []
  end

  test "the prompt can go to a number other than the account's", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p/\/wallet/)

    lv
    |> form("#topup-form", topup: %{amount: "100", phone: "0722 000 000"})
    |> render_submit()

    payment = Payments.pending_topup(user)
    # Stored in the canonical form, not as it was typed.
    assert payment.phone == "254722000000"

    assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})
    assert [created] = Test.created_for(payment.idempotency_key)
    assert created.customer_phone == "254722000000"

    # The rail reports the prompted number, so the settlement still matches even
    # though it is not the account's own.
    Test.settle!(Payments.get_payment!(payment.id).malipo_payment_id, "R2")
    assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})
    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#payment-succeeded")
    assert Wallet.balance(user) == 10_000
  end

  test "a number that is not a Kenyan mobile is refused before any prompt", %{conn: conn} do
    user = verified_user_fixture()
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p/\/wallet/)

    html =
      lv
      |> form("#topup-form", topup: %{amount: "100", phone: "not a phone"})
      |> render_submit()

    assert html =~ "valid M-Pesa number"
    assert Payments.pending_topup(user) == nil
    assert all_enqueued(worker: CreatePayment) == []
  end
end
