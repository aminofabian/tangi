defmodule ViewNinjas.PaymentsTest do
  @moduledoc """
  Payment attempts and the settlement funnel (build-plan.md M7, scope.md §8).
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Orders
  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Wallet

  describe "start_attempt/1" do
    test "one order attempt carries one key, and the next key is the next number" do
      order = order_fixture()

      assert {:ok, first} = Payments.start_order_payment(order)
      assert first.idempotency_key == "order-#{order.id}-1"
      assert first.status == :pending
      assert first.malipo_payment_id == nil
      assert first.amount_cents == order.retail_cents

      assert {:ok, second} = Payments.start_order_payment(order)
      assert second.idempotency_key == "order-#{order.id}-2"
    end

    test "a repeated key returns the original row, never a second one" do
      order = order_fixture()
      {:ok, first} = Payments.start_order_payment(order)

      attrs = %{
        user_id: order.user_id,
        order_id: order.id,
        purpose: :order,
        amount_cents: order.retail_cents,
        idempotency_key: first.idempotency_key
      }

      assert {:ok, again} = Payments.start_attempt(attrs)
      assert again.id == first.id
    end

    test "a top-up attempt is not tied to an order" do
      payment = topup_fixture(%{amount_cents: 25_000})

      assert payment.purpose == :topup
      assert payment.order_id == nil
      assert payment.amount_cents == 25_000
      assert payment.idempotency_key =~ "topup-"
    end
  end

  describe "amount_string/1" do
    test "whole shillings as Malipo wants them" do
      assert Payments.amount_string(27_600) == "276.00"
      assert Payments.amount_string(100) == "1.00"
    end
  end

  describe "failure_copy/2" do
    test "the kinds the customer can fix are said plainly" do
      assert Payments.failure_copy("wrong_pin", "raw") =~ "PIN"
      assert Payments.failure_copy("insufficient_funds", "raw") =~ "enough money"
      assert Payments.failure_copy("customer_declined", "raw") =~ "declined"
    end

    test "our kinds say nothing was charged" do
      assert Payments.failure_copy("expired", "raw") =~ "Nothing was charged"
      assert Payments.failure_copy("timeout", "raw") =~ "Nothing was charged"
    end

    test "an unknown kind falls back to the rail's message" do
      assert Payments.failure_copy("something_new", "Rail said this.") == "Rail said this."
      assert Payments.failure_copy(nil, nil) =~ "did not go through"
    end
  end

  describe "the status helpers" do
    test "terminal?/1 is true only after a decision" do
      assert Payment.terminal?(:settled)
      assert Payment.terminal?(:failed)
      refute Payment.terminal?(:pending)
    end

    test "mark_pending/2 records the rail's id" do
      payment = payment_fixture()

      {:ok, pending} = Payments.mark_pending(payment, "malipo-123")

      assert pending.malipo_payment_id == "malipo-123"
      assert pending.status == :pending
    end

    test "mark_failed/2 records why" do
      payment = payment_fixture()

      {:ok, failed} =
        Payments.mark_failed(payment, %{failure_kind: "wrong_pin", failure_message: "Wrong PIN."})

      assert failed.status == :failed
      assert failed.failure_kind == "wrong_pin"
    end
  end

  describe "apply_settlement/2" do
    test "pays the order behind an order payment" do
      order = order_fixture()
      payment = payment_fixture(%{order: order})

      assert {:ok, {:paid, paid_order}} = Payments.apply_settlement(payment, "QKH7XYZ123")

      assert paid_order.id == order.id
      assert paid_order.state == :paid
      assert Payments.get_payment!(payment.id).status == :settled
      assert Payments.get_payment!(payment.id).receipt == "QKH7XYZ123"
    end

    test "credits the wallet behind a top-up payment" do
      payment = topup_fixture(%{amount_cents: 30_000})

      assert {:ok, {:credited, entry}} = Payments.apply_settlement(payment, "R1")

      assert entry.amount_cents == 30_000
      assert Wallet.balance(payment.user_id) == 30_000
      assert Payments.get_payment!(payment.id).status == :settled
    end

    test "a replayed settlement writes nothing a second time" do
      order = order_fixture()
      payment = payment_fixture(%{order: order})

      assert {:ok, {:paid, _}} = Payments.apply_settlement(payment, "R1")

      # A duplicate callback re-reads the same, now terminal, row.
      settled = Payments.get_payment!(payment.id)
      assert {:ok, {:already_settled, _}} = Payments.apply_settlement(settled, "R1")

      assert Orders.get_order!(order.id).state == :paid
      assert Orders.timeline(order) |> Enum.count() == 2
    end

    test "a settlement applied twice credits once" do
      payment = topup_fixture(%{amount_cents: 12_000})

      assert {:ok, {:credited, _}} = Payments.apply_settlement(payment, "R1")
      assert Wallet.balance(payment.user_id) == 12_000

      # The row is terminal now, and the transaction wrote the ledger and the
      # status together, so a replay is a no-op.
      assert {:ok, {:already_settled, _}} =
               Payments.apply_settlement(Payments.get_payment!(payment.id), "R1")

      assert Wallet.balance(payment.user_id) == 12_000
    end
  end

  describe "list_stale_pending/3" do
    test "only pending attempts that reached the rail, within the window" do
      inside = payment_fixture() |> with_malipo_id("malipo-inside") |> backdate(120)
      uncreated = payment_fixture() |> backdate(120)
      too_new = payment_fixture() |> with_malipo_id("malipo-new")

      from = DateTime.add(DateTime.utc_now(:second), -3_600, :second)
      to = DateTime.add(DateTime.utc_now(:second), -90, :second)

      ids = Payments.list_stale_pending(from, to) |> Enum.map(& &1.id)

      assert ids == [inside.id]
      refute uncreated.id in ids
      refute too_new.id in ids

      # Past the give-up bound, nothing is probed.
      assert Payments.list_stale_pending(from, from) == []
    end
  end

  defp with_malipo_id(payment, malipo_id) do
    {:ok, updated} = Payments.mark_pending(payment, malipo_id)
    updated
  end

  defp backdate(payment, seconds) do
    at = DateTime.add(DateTime.utc_now(:second), -seconds, :second)

    ViewNinjas.Repo.update_all(
      Ecto.Query.from(p in Payment, where: p.id == ^payment.id),
      set: [inserted_at: at]
    )

    payment
  end
end
