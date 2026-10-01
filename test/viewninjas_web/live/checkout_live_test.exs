defmodule ViewNinjasWeb.CheckoutLiveTest do
  @moduledoc """
  Checkout and the M-Pesa sheet (build-plan.md M7, scope.md §8, §12).
  """

  use ViewNinjasWeb.ConnCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Orders, Payments, Wallet}
  alias ViewNinjas.Payments.Providers.Test
  alias ViewNinjas.Workers.{ConfirmPayment, CreatePayment}

  test "a signed out visitor is sent to log in" do
    order = order_fixture()

    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/checkout/#{order.id}")
  end

  test "someone else's order is not reachable", %{conn: conn} do
    order = order_fixture()
    conn = log_in_user(conn, verified_user_fixture())

    assert {:error, {:live_redirect, %{to: "/orders"}}} = live(conn, ~p"/checkout/#{order.id}")
  end

  test "an unverified phone can still pay, and the wallet balance is shown", %{conn: conn} do
    user = user_fixture()
    order = order_fixture(%{user: user})
    credit_fixture(user, 5_000)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/checkout/#{order.id}")

    refute has_element?(lv, "#verify-first")
    assert has_element?(lv, "#pay")
    assert has_element?(lv, "#pay-mpesa")
    assert render(lv) =~ "KSh 50"
    # The wallet is short of the order, so checkout offers a top-up of the gap.
    refute has_element?(lv, "#pay-wallet")
    assert has_element?(lv, "#topup-wallet")
  end

  test "an unverified buyer whose wallet covers the order pays with no prompt", %{conn: conn} do
    user = user_fixture()
    order = order_fixture(%{user: user})
    credit_fixture(user, order.retail_cents)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/checkout/#{order.id}")

    assert has_element?(lv, "#pay-wallet")
    refute has_element?(lv, "#verify-first")

    lv |> element("#pay-wallet") |> render_click()

    assert has_element?(lv, "#payment-succeeded")
    assert Orders.get_order!(order.id).state == :paid
    assert Wallet.balance(user) == 0
  end

  test "a verified buyer sees the summary, the total and the pay button", %{conn: conn} do
    user = verified_user_fixture()
    order = order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/checkout/#{order.id}")

    assert has_element?(lv, "#order-summary")
    assert render(lv) =~ "KSh 276"
    assert has_element?(lv, "#pay-mpesa")
    # An empty wallet cannot pay, so the option is not offered.
    refute has_element?(lv, "#pay-wallet")
  end

  test "paying with M-Pesa shows the sheet, and a settled GET pays the order", %{conn: conn} do
    user = verified_user_fixture()
    order = order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/checkout/#{order.id}")

    lv |> element("#pay-mpesa") |> render_click()

    assert has_element?(lv, "#payment-sheet")
    assert [%{args: %{"payment_id" => _}}] = all_enqueued(worker: CreatePayment)

    # The rail creates the prompt, then reports it settled.
    payment = Payments.pending_for_order(order)
    assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})
    Test.settle!(Payments.get_payment!(payment.id).malipo_payment_id, "QKH7XYZ123")

    # The confirming GET is what moves the money.
    assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})
    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#payment-succeeded")
    assert render(lv) =~ "QKH7XYZ123"
    assert Orders.get_order!(order.id).state == :paid
  end

  test "a pending attempt is picked up again after a reload", %{conn: conn} do
    user = verified_user_fixture()
    order = order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/checkout/#{order.id}")
    lv |> element("#pay-mpesa") |> render_click()
    assert has_element?(lv, "#payment-sheet")

    # Coming back to the page resumes waiting rather than starting a second prompt.
    {:ok, lv2, _html} = live(conn, ~p"/checkout/#{order.id}")
    assert has_element?(lv2, "#payment-sheet")
  end

  test "a failed prompt offers a retry that is a new attempt", %{conn: conn} do
    user = verified_user_fixture()
    order = order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/checkout/#{order.id}")
    lv |> element("#pay-mpesa") |> render_click()

    first = Payments.pending_for_order(order)
    assert :ok = perform_job(CreatePayment, %{"payment_id" => first.id})
    Test.fail!(Payments.get_payment!(first.id).malipo_payment_id, "customer_timeout", "No PIN.")
    assert :ok = perform_job(ConfirmPayment, %{"payment_id" => first.id})
    _ = :sys.get_state(lv.pid)

    assert has_element?(lv, "#payment-failed")
    # The kind is mapped to customer copy, not the rail's raw message.
    assert render(lv) =~ "PIN was not entered in time"
    assert Orders.get_order!(order.id).state == :awaiting_payment

    lv |> element("#payment-retry") |> render_click()

    assert Payments.pending_for_order(order).idempotency_key == "order-#{order.id}-2"
    assert has_element?(lv, "#payment-sheet")
  end

  test "a wallet that covers the order pays it with no prompt at all", %{conn: conn} do
    user = verified_user_fixture()
    order = order_fixture(%{user: user})
    credit_fixture(user, order.retail_cents)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/checkout/#{order.id}")

    assert has_element?(lv, "#pay-wallet")

    lv |> element("#pay-wallet") |> render_click()

    assert has_element?(lv, "#payment-succeeded")
    assert Orders.get_order!(order.id).state == :paid
    assert Wallet.balance(user) == 0
    assert all_enqueued(worker: CreatePayment) == []
  end

  test "a wallet short of the order tops up, then pays the order from it", %{conn: conn} do
    user = verified_user_fixture()
    order = order_fixture(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/checkout/#{order.id}")

    # An empty wallet cannot pay, so checkout offers the top-up instead.
    refute has_element?(lv, "#pay-wallet")
    assert has_element?(lv, "#topup-wallet")

    lv |> element("#topup-wallet") |> render_click()
    assert has_element?(lv, "#payment-sheet")

    payment = Payments.pending_topup(user)
    assert payment.purpose == :topup
    assert payment.amount_cents == order.retail_cents

    assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})
    Test.settle!(Payments.get_payment!(payment.id).malipo_payment_id, "TOPUP123")
    assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})
    _ = :sys.get_state(lv.pid)

    # Back on the review, the wallet now covers the order and pays it.
    assert Wallet.balance(user) == order.retail_cents
    assert has_element?(lv, "#pay-wallet")
    refute has_element?(lv, "#topup-wallet")

    lv |> element("#pay-wallet") |> render_click()

    assert has_element?(lv, "#payment-succeeded")
    assert Orders.get_order!(order.id).state == :paid
  end
end
