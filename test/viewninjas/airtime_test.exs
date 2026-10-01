defmodule ViewNinjas.AirtimeTest do
  @moduledoc """
  Buying airtime (docs/instalipa-airtime.md): the wallet debit, bulk batches, the
  refund line, and saved numbers.

  Also the two halves of the money-back promise: the atomic `fail_and_refund/4`,
  and the kill switch that stops selling before a customer is ever charged.
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.AirtimeFixtures

  alias ViewNinjas.Airtime
  alias ViewNinjas.Settings
  alias ViewNinjas.Wallet
  alias ViewNinjas.Wallet.LedgerEntry

  describe "buy/2" do
    test "pays from the wallet and creates one paid order" do
      user = funded_user(50_000)

      assert {:ok, [order]} =
               Airtime.buy(user, %{amount_cents: 10_000, phones: ["0712345678"]})

      assert order.state == :paid
      assert order.phone == "254712345678"
      assert order.amount_cents == 10_000
      assert order.reference =~ "airtime-"
      assert Wallet.balance(user) == 40_000
    end

    test "a bulk buy shares one batch and debits each line" do
      user = funded_user(100_000)

      assert {:ok, orders} =
               Airtime.buy(user, %{
                 amount_cents: 10_000,
                 phones: ["0712345678", "0722000111", "0733000222"]
               })

      assert length(orders) == 3
      assert orders |> Enum.map(& &1.batch_id) |> Enum.uniq() |> length() == 1

      assert orders |> Enum.map(& &1.phone) |> Enum.sort() ==
               ["254712345678", "254722000111", "254733000222"]

      assert Wallet.balance(user) == 70_000
    end

    test "a repeated number is bought once" do
      user = funded_user(50_000)

      assert {:ok, orders} =
               Airtime.buy(user, %{amount_cents: 10_000, phones: ["0712345678", "254712345678"]})

      assert length(orders) == 1
      assert Wallet.balance(user) == 40_000
    end

    test "refuses when the wallet does not cover the whole batch" do
      user = funded_user(15_000)

      assert {:error, :insufficient_funds} =
               Airtime.buy(user, %{amount_cents: 10_000, phones: ["0712345678", "0722000111"]})

      assert Wallet.balance(user) == 15_000
      assert Airtime.list_for_user(user) == []
    end

    test "validates the amount and the numbers before taking any money" do
      user = funded_user(100_000)

      assert {:error, :not_whole_shillings} =
               Airtime.buy(user, %{amount_cents: 10_050, phones: ["0712345678"]})

      assert {:error, :amount_too_small} =
               Airtime.buy(user, %{amount_cents: 500, phones: ["0712345678"]})

      assert {:error, :no_recipients} = Airtime.buy(user, %{amount_cents: 10_000, phones: []})

      assert {:error, {:invalid_phone, "nope"}} =
               Airtime.buy(user, %{amount_cents: 10_000, phones: ["nope"]})

      too_many = for n <- 1..21, do: "07120000" <> String.pad_leading(to_string(n), 2, "0")

      assert {:error, :too_many_recipients} =
               Airtime.buy(user, %{amount_cents: 10_000, phones: too_many})

      assert Wallet.balance(user) == 100_000
      assert Airtime.list_for_user(user) == []
    end
  end

  describe "refund/1" do
    test "credits the wallet once and closes the order" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user})

      {:ok, sending} = Airtime.mark_sending(order)
      {:ok, failed} = Airtime.mark_failed(sending, "invalid_phone", "bad number")

      assert {:ok, refunded} = Airtime.refund(failed)
      assert refunded.state == :refunded
      assert Wallet.balance(user) == 50_000

      assert {:error, :not_refundable} = Airtime.refund(refunded)
      assert Wallet.balance(user) == 50_000
    end
  end

  describe "remembered numbers" do
    test "buying a number remembers it for next time" do
      user = funded_user(100_000)

      {:ok, _orders} =
        Airtime.buy(user, %{amount_cents: 5_000, phones: ["0712345678", "0722000111"]})

      phones = user |> Airtime.list_recipients() |> Enum.map(& &1.phone)
      assert Enum.sort(phones) == ["254712345678", "254722000111"]
    end

    test "remembering the same number twice does not duplicate it" do
      user = user_fixture()

      :ok = Airtime.remember_recipients(user, ["254712345678"])
      :ok = Airtime.remember_recipients(user, ["254712345678"])

      assert [recipient] = Airtime.list_recipients(user)
      assert recipient.phone == "254712345678"
    end

    test "the most recently bought number floats first" do
      user = funded_user(100_000)

      {:ok, _} = Airtime.buy(user, %{amount_cents: 5_000, phones: ["0712345678"]})
      {:ok, _} = Airtime.buy(user, %{amount_cents: 5_000, phones: ["0722000111"]})

      assert [first | _] = Airtime.list_recipients(user)
      assert first.phone == "254722000111"
    end

    test "delete removes only the customer's own number" do
      user = user_fixture()
      other = user_fixture()
      :ok = Airtime.remember_recipients(user, ["254712345678"])
      [recipient] = Airtime.list_recipients(user)

      :ok = Airtime.delete_recipient(other, recipient.id)
      assert length(Airtime.list_recipients(user)) == 1

      :ok = Airtime.delete_recipient(user, recipient.id)
      assert Airtime.list_recipients(user) == []
    end
  end

  describe "fail_and_refund/4" do
    test "from sending it ends refunded with the wallet made whole" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)

      assert {:ok, refunded} = Airtime.fail_and_refund(sending, "invalid_phone", "bad number")
      assert refunded.state == :refunded
      assert refunded.failure_kind == "invalid_phone"
      assert Wallet.balance(user) == 50_000

      assert [entry] = refund_entries(order.id)
      assert entry.reason == :airtime_refund
      assert entry.amount_cents == 10_000
    end

    test "from submitted it makes the same promise" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)

      {:ok, submitted} =
        Airtime.mark_submitted(sending, %{id: "TX1", status: :submitted, balance: "100.00"})

      assert {:ok, refunded} = Airtime.fail_and_refund(submitted, "barred", "number barred")
      assert refunded.state == :refunded
      assert refunded.instalipa_id == "TX1"
      assert Wallet.balance(user) == 50_000
      assert [_entry] = refund_entries(order.id)
    end

    test "both halves commit together, so nothing is left failed and still debited" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)

      assert {:ok, refunded} = Airtime.fail_and_refund(sending, "invalid_phone", "bad number")
      assert refunded.state == :refunded
      assert Airtime.get_order(order.id).state == :refunded

      # The sweep that drains stranded refunds finds nothing, so there is no window
      # in which the order reads `failed` and the money has not come back.
      assert Airtime.list_stranded_refunds() == []
      assert Airtime.outstanding_refund_cents() == 0

      assert Airtime.timeline(order) |> Enum.map(& &1.to_state) ==
               ["paid", "sending", "failed", "refunded"]
    end

    test "a refunded order is never credited twice" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)
      {:ok, refunded} = Airtime.fail_and_refund(sending, "invalid_phone", "bad number")

      assert {:error, :not_refundable} = Airtime.refund(refunded)
      assert {:error, :not_refundable} = Airtime.refund(Airtime.get_order(order.id))

      assert Wallet.balance(user) == 50_000
      assert [_entry] = refund_entries(order.id)
    end

    test "refuses an order that has not reached the rail, and takes nothing" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})

      assert {:error, :not_failable} =
               Airtime.fail_and_refund(order, "invalid_phone", "too early to know")

      assert Airtime.get_order(order.id).state == :paid
      assert Wallet.balance(user) == 40_000
      assert refund_entries(order.id) == []
    end

    test "refuses an order that is already refunded, and takes nothing" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)
      {:ok, refunded} = Airtime.fail_and_refund(sending, "invalid_phone", "bad number")

      assert {:error, :not_failable} =
               Airtime.fail_and_refund(refunded, "invalid_phone", "again")

      assert Airtime.get_order(order.id).state == :refunded
      assert Wallet.balance(user) == 50_000
      assert [_entry] = refund_entries(order.id)
    end
  end

  describe "the float kill switch" do
    test "a paused rail refuses the buy and takes no money" do
      user = funded_user(50_000)
      {:ok, _setting} = Settings.put("instalipa_paused", "true", nil)

      assert Airtime.paused?()
      assert Airtime.pause_reason() == :paused
      refute Airtime.sellable?()

      assert {:error, :paused} =
               Airtime.buy(user, %{amount_cents: 10_000, phones: ["0712345678"]})

      assert Wallet.balance(user) == 50_000
      assert Airtime.list_for_user(user) == []
    end

    test "clearing the pause puts the line back in service" do
      user = funded_user(50_000)
      {:ok, _setting} = Settings.put("instalipa_paused", "true", nil)
      :ok = Settings.clear("instalipa_paused")

      refute Airtime.paused?()
      assert Airtime.sellable?()

      assert {:ok, [order]} = Airtime.buy(user, %{amount_cents: 10_000, phones: ["0712345678"]})
      assert order.state == :paid
      assert Wallet.balance(user) == 40_000
    end

    test "a float under the floor stops the buy before any money moves" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)

      {:ok, _submitted} =
        Airtime.mark_submitted(sending, %{id: "TX1", status: :submitted, balance: "10.00"})

      # The floor is a stored override, so it is scoped to this test by the sandbox.
      {:ok, _setting} = Settings.put("airtime_float_floor_cents", "2000", nil)

      assert %{cents: 1_000, order_id: float_order_id} = Airtime.float()
      assert float_order_id == order.id
      assert Airtime.float_floor_cents() == 2_000
      assert Airtime.below_float_floor?()
      assert Airtime.pause_reason() == :float_low
      refute Airtime.sellable?()

      assert {:error, :float_low} =
               Airtime.buy(user, %{amount_cents: 5_000, phones: ["0722000111"]})

      assert Wallet.balance(user) == 40_000
      assert [%{id: only_id}] = Airtime.list_for_user(user)
      assert only_id == order.id

      # Clearing the override removes the floor we set, but the float really is that
      # low, so selling stays off.
      :ok = Settings.clear("airtime_float_floor_cents")
      assert Airtime.float_floor_cents() > 2_000
      refute Airtime.sellable?()
    end

    test "a float above the floor keeps the line selling" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)

      {:ok, _submitted} =
        Airtime.mark_submitted(sending, %{id: "TX_A", status: :submitted, balance: "100000.00"})

      assert %{cents: 10_000_000} = Airtime.float()
      refute Airtime.below_float_floor?()
      assert Airtime.sellable?()

      assert {:ok, [_order]} = Airtime.buy(user, %{amount_cents: 5_000, phones: ["0722000111"]})
      assert Wallet.balance(user) == 35_000
    end

    test "a float the rail has never reported does not stop selling" do
      assert Airtime.float() == nil
      refute Airtime.below_float_floor?()
      assert Airtime.sellable?()

      user = funded_user(50_000)
      assert {:ok, [_order]} = Airtime.buy(user, %{amount_cents: 10_000, phones: ["0712345678"]})
      assert Wallet.balance(user) == 40_000
    end
  end

  describe "list_stranded_refunds/0" do
    test "a failed order whose credit never landed is listed" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)
      {:ok, failed} = Airtime.mark_failed(sending, "invalid_phone", "bad number")

      assert [stranded] = Airtime.list_stranded_refunds()
      assert stranded.id == failed.id
      assert stranded.state == :failed

      # Money taken and not returned: the amount we still owe.
      assert Airtime.outstanding_refund_cents() == 10_000
      assert Wallet.balance(user) == 40_000
    end

    test "an order that was refunded is never listed" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)
      {:ok, refunded} = Airtime.fail_and_refund(sending, "invalid_phone", "bad number")

      assert refunded.state == :refunded
      assert Airtime.list_stranded_refunds() == []
      assert Airtime.outstanding_refund_cents() == 0
      assert Wallet.balance(user) == 50_000
    end

    test "an ambiguous send waiting on a person is never listed" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)
      {:ok, parked} = Airtime.mark_needs_review(sending, "the rail timed out")

      assert parked.state == :needs_review
      assert Airtime.list_stranded_refunds() == []

      # We do not know whether it went out, so we do not refund it — but the money is
      # still owed until a person decides.
      assert Airtime.outstanding_refund_cents() == 10_000
      assert refund_entries(order.id) == []
    end
  end

  describe "the back office totals" do
    test "outstanding_refund_cents/0 is zero when nothing is owed" do
      user = funded_user(50_000)
      _order = airtime_order_fixture(%{user: user, amount_cents: 10_000})

      assert Airtime.outstanding_refund_cents() == 0
    end

    test "outstanding_refund_cents/0 sums failed and needs_review only" do
      user = funded_user(100_000)

      failed = airtime_order_fixture(%{user: user, amount_cents: 5_000, phones: ["0712345678"]})
      {:ok, failed_sending} = Airtime.mark_sending(failed)
      {:ok, _failed} = Airtime.mark_failed(failed_sending, "invalid_phone", "bad number")

      parked = airtime_order_fixture(%{user: user, amount_cents: 7_000, phones: ["0722000111"]})
      {:ok, parked_sending} = Airtime.mark_sending(parked)
      {:ok, _parked} = Airtime.mark_needs_review(parked_sending, "the rail timed out")

      settled = airtime_order_fixture(%{user: user, amount_cents: 3_000, phones: ["0733000222"]})
      {:ok, settled_sending} = Airtime.mark_sending(settled)
      {:ok, _refunded} = Airtime.fail_and_refund(settled_sending, "invalid_phone", "bad number")

      assert Airtime.outstanding_refund_cents() == 12_000
    end

    test "counts_by_state/0 is keyed by state" do
      user = funded_user(100_000)

      first = airtime_order_fixture(%{user: user, amount_cents: 5_000, phones: ["0712345678"]})
      {:ok, sending} = Airtime.mark_sending(first)
      {:ok, _refunded} = Airtime.fail_and_refund(sending, "invalid_phone", "bad number")

      _second = airtime_order_fixture(%{user: user, amount_cents: 6_000, phones: ["0722000111"]})

      assert Airtime.counts_by_state() == %{refunded: 1, paid: 1}
    end

    test "list_for_review/1 filters by state and loads the customer" do
      user = funded_user(100_000)

      parked = airtime_order_fixture(%{user: user, amount_cents: 5_000, phones: ["0712345678"]})
      {:ok, parked_sending} = Airtime.mark_sending(parked)
      {:ok, _parked} = Airtime.mark_needs_review(parked_sending, "the rail timed out")

      failed = airtime_order_fixture(%{user: user, amount_cents: 6_000, phones: ["0722000111"]})
      {:ok, failed_sending} = Airtime.mark_sending(failed)
      {:ok, _failed} = Airtime.mark_failed(failed_sending, "invalid_phone", "bad number")

      assert [only] = Airtime.list_for_review([:needs_review])
      assert only.id == parked.id
      assert only.user.id == user.id

      assert Airtime.list_for_review([:failed]) |> Enum.map(& &1.id) == [failed.id]

      # The rows carrying a customer's money lead the queue, whatever the filter.
      assert [top | _rest] = Airtime.list_for_review([:failed, :needs_review])
      assert top.id == parked.id
    end

    test "history_for_user/2 reports nothing owed on a clean account" do
      user = funded_user(50_000)

      assert %{orders: [], stats: stats} = Airtime.history_for_user(user)
      assert stats.spent == 0
      assert stats.refunded == 0
      assert stats.delivered == 0
      assert stats.failed == 0
    end

    test "history_for_user/2 counts a delivered send as spent and a refund as refunded" do
      user = funded_user(100_000)

      sent = airtime_order_fixture(%{user: user, amount_cents: 10_000, phones: ["0712345678"]})
      {:ok, sending} = Airtime.mark_sending(sent)
      {:ok, submitted} = Airtime.mark_submitted(sending, %{id: "TX_A", status: :submitted})
      {:ok, _delivered} = Airtime.mark_delivered(submitted, %{status: :success})

      failed = airtime_order_fixture(%{user: user, amount_cents: 20_000, phones: ["0722000111"]})
      {:ok, failed_sending} = Airtime.mark_sending(failed)
      {:ok, refunded} = Airtime.fail_and_refund(failed_sending, "invalid_phone", "bad number")

      history = Airtime.history_for_user(user)

      assert Enum.map(history.orders, & &1.id) == [refunded.id, sent.id]
      assert history.stats.spent == 10_000
      assert history.stats.refunded == 20_000
      assert history.stats.delivered == 1
      assert history.stats.failed == 0
    end
  end

  describe "reconcile_delivered/3" do
    test "a pasted transaction id delivers a parked order" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)
      {:ok, parked} = Airtime.mark_needs_review(sending, "the rail timed out")
      assert parked.state == :needs_review

      assert {:ok, delivered} = Airtime.reconcile_delivered(parked, "TX_A", nil)
      assert delivered.state == :delivered
      assert delivered.instalipa_id == "TX_A"
      assert delivered.instalipa_status == "Success"

      # The claim is that the airtime did go out, so no money comes back.
      assert Wallet.balance(user) == 40_000
      assert refund_entries(order.id) == []
    end

    test "a blank transaction id changes nothing" do
      user = funded_user(50_000)
      order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
      {:ok, sending} = Airtime.mark_sending(order)
      {:ok, parked} = Airtime.mark_needs_review(sending, "the rail timed out")

      assert {:error, :missing_transaction_id} = Airtime.reconcile_delivered(parked, "", nil)
      assert {:error, :missing_transaction_id} = Airtime.reconcile_delivered(parked, "   ", nil)

      assert Airtime.get_order(order.id).state == :needs_review
      assert Airtime.get_order(order.id).instalipa_id == nil
      assert Wallet.balance(user) == 40_000
    end

    test "only a parked order can be reconciled" do
      order = airtime_order_fixture()

      assert {:error, :not_reconcilable} = Airtime.reconcile_delivered(order, "TX_B", nil)
    end
  end

  # The refund credit for one order, in the ledger rather than off a balance.
  defp refund_entries(order_id) do
    LedgerEntry
    |> where([e], e.airtime_order_id == ^order_id and e.reason == :airtime_refund)
    |> Repo.all()
  end
end
