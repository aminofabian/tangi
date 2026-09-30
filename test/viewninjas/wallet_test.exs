defmodule ViewNinjas.WalletTest do
  @moduledoc """
  The wallet ledger (build-plan.md M7, scope.md §6): append-only, derived balance,
  and a database guard against a double credit.
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Orders
  alias ViewNinjas.Wallet
  alias ViewNinjas.Wallet.LedgerEntry

  describe "balance/1" do
    test "is zero with no ledger, and the sum of entries otherwise" do
      user = user_fixture()

      assert Wallet.balance(user) == 0

      credit_fixture(user, 10_000)
      credit_fixture(user, 2_500)

      assert Wallet.balance(user) == 12_500
    end

    test "is nil-safe" do
      assert Wallet.balance(nil) == 0
    end
  end

  describe "record/1" do
    test "appends a signed entry and never edits one" do
      user = user_fixture()

      {:ok, entry} = Wallet.record(%{user_id: user.id, amount_cents: -1_500, reason: :adjustment})

      assert entry.amount_cents == -1_500
      assert Repo.aggregate(LedgerEntry, :count) == 1
      assert Wallet.balance(user) == -1_500
    end

    test "refuses a zero amount" do
      user = user_fixture()

      assert {:error, changeset} =
               Wallet.record(%{user_id: user.id, amount_cents: 0, reason: :adjustment})

      assert changeset.errors[:amount_cents]
    end

    test "a payment can credit the ledger only once" do
      payment = topup_fixture(%{amount_cents: 5_000}) |> settle_payment()

      assert {:ok, _entry} = Wallet.topup(payment)
      assert Wallet.balance(payment.user_id) == 5_000

      # The unique index on (payment_id, reason) is the guard: a replayed
      # callback cannot double-credit (scope.md §8).
      assert {:error, :already_recorded} = Wallet.topup(payment)
      assert Wallet.balance(payment.user_id) == 5_000
    end
  end

  describe "capture_order/1" do
    test "debits the order's retail price" do
      order = order_fixture()
      credit_fixture(order.user_id, 50_000)

      assert {:ok, entry} = Wallet.capture_order(order)

      assert entry.amount_cents == -order.retail_cents
      assert entry.reason == :order_capture
      assert entry.order_id == order.id
      assert Wallet.balance(order.user_id) == 50_000 - order.retail_cents
    end
  end

  describe "a wallet-funded order" do
    test "debits and marks the order paid in one transaction" do
      order = order_fixture()
      credit_fixture(order.user_id, order.retail_cents)

      assert {:ok, paid} = Orders.pay_from_wallet(order)

      assert paid.state == :paid
      assert Wallet.balance(order.user_id) == 0
    end

    test "refuses when the balance is short, and leaves the order alone" do
      order = order_fixture()
      credit_fixture(order.user_id, order.retail_cents - 100)

      assert {:error, :insufficient_funds} = Orders.pay_from_wallet(order)
      assert Orders.get_order!(order.id).state == :awaiting_payment
      assert Wallet.balance(order.user_id) == order.retail_cents - 100
    end

    test "an order that is already paid cannot be paid again" do
      order = order_fixture()
      credit_fixture(order.user_id, order.retail_cents * 2)

      {:ok, paid} = Orders.pay_from_wallet(order)

      assert {:error, :not_payable} = Orders.pay_from_wallet(paid)
      assert Wallet.balance(order.user_id) == order.retail_cents
    end
  end

  defp settle_payment(payment) do
    {:ok, settled} = ViewNinjas.Payments.settle(payment, "TESTRECEIPT")
    settled
  end
end
