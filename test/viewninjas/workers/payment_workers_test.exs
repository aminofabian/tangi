defmodule ViewNinjas.Workers.PaymentWorkersTest do
  @moduledoc """
  The payment jobs (build-plan.md M7, docs/malipo-connect.md §9): the prompt is
  sent once, and money moves only on a confirming GET.
  """

  use ViewNinjas.DataCase, async: true

  use Oban.Testing, repo: ViewNinjas.Repo

  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.Orders
  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.{Payment, Providers.Test}
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.{ConfirmPayment, CreatePayment, PlaceOrder, SweepPendingPayments}

  describe "CreatePayment" do
    test "sends the prompt once and enqueues the confirmation" do
      order = order_fixture()
      payment = payment_fixture(%{order: order})

      assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})

      sent = Payments.get_payment!(payment.id)
      assert sent.malipo_payment_id =~ "test-"
      assert sent.status == :pending

      # The rail got the right amount, the account's phone, and the attempt key.
      assert [created] = Test.created_for(sent.idempotency_key)
      assert created.amount == Payments.amount_string(order.retail_cents)
      assert created.customer_phone == ViewNinjas.Accounts.get_user!(order.user_id).phone
      assert created.reference == "order-#{order.id}"

      assert [%{args: %{"payment_id" => id}}] = all_enqueued(worker: ConfirmPayment)
      assert id == payment.id
    end

    test "a definite rejection is recorded and not retried" do
      payment = payment_fixture()
      Test.reject_create!(payment.idempotency_key, {:malipo, "rail_failure", "no prompt", 422})

      assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})

      failed = Payments.get_payment!(payment.id)
      assert failed.status == :failed
      assert failed.failure_kind == "rail_failure"
      assert failed.malipo_payment_id == nil
    end

    test "a transport error is retried" do
      payment = payment_fixture()
      Test.reject_create!(payment.idempotency_key, {:transport, :timeout})

      assert {:error, {:transport, :timeout}} =
               perform_job(CreatePayment, %{"payment_id" => payment.id})

      assert Payments.get_payment!(payment.id).status == :pending
    end

    test "on the last attempt a transport error is recorded instead" do
      payment = payment_fixture()
      Test.reject_create!(payment.idempotency_key, {:transport, :timeout})

      assert :ok =
               perform_job(CreatePayment, %{"payment_id" => payment.id}, attempt: 5)

      assert Payments.get_payment!(payment.id).status == :failed
    end

    test "an attempt that already reached the rail is left alone" do
      payment = payment_fixture()
      {:ok, _pending} = Payments.mark_pending(payment, "malipo-fixed")

      assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})

      assert Payments.get_payment!(payment.id).malipo_payment_id == "malipo-fixed"
      assert Test.created_for(payment.idempotency_key) == []
    end

    test "a missing payment is a no-op" do
      assert :ok = perform_job(CreatePayment, %{"payment_id" => -1})
    end
  end

  describe "ConfirmPayment" do
    test "settled is the only way money moves: the order is paid" do
      order = order_fixture()
      payment = sent_attempt(order)
      Test.settle!(payment.malipo_payment_id, "QKH7XYZ123")

      assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})

      assert Orders.get_order!(order.id).state == :paid
      assert Payments.get_payment!(payment.id).status == :settled
      assert Payments.get_payment!(payment.id).receipt == "QKH7XYZ123"

      # A settled order becomes a placement job only after it is paid (M8).
      assert [%{args: %{"order_id" => id}}] = all_enqueued(worker: PlaceOrder)
      assert id == order.id
    end

    test "a settled GET for a different amount does not move money" do
      order = order_fixture()
      payment = sent_attempt(order)

      Test.set_amount!(payment.malipo_payment_id, "1.00")
      Test.settle!(payment.malipo_payment_id, "R1")

      assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})

      assert Payments.get_payment!(payment.id).status == :failed
      assert Payments.get_payment!(payment.id).failure_kind == "amount_mismatch"
      assert Orders.get_order!(order.id).state == :awaiting_payment
      refute Wallet.balance(order.user_id) > 0
    end

    test "a failed prompt fails the payment and leaves the order retryable" do
      order = order_fixture()
      payment = sent_attempt(order)
      Test.fail!(payment.malipo_payment_id, "customer_timeout", "No PIN in time.")

      assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})

      assert Payments.get_payment!(payment.id).status == :failed
      assert Payments.get_payment!(payment.id).failure_kind == "customer_timeout"
      # Nothing was sent on, and the customer can try again.
      assert Orders.get_order!(order.id).state == :awaiting_payment
    end

    test "still pending snoozes until the deadline, then cancels without deciding" do
      payment = sent_attempt(order_fixture())

      future = System.system_time(:second) + 60

      assert {:snooze, 3} =
               perform_job(ConfirmPayment, %{"payment_id" => payment.id, "deadline" => future})

      past = System.system_time(:second) - 1

      assert {:cancel, :prompt_window_elapsed} =
               perform_job(ConfirmPayment, %{"payment_id" => payment.id, "deadline" => past})

      assert Payments.get_payment!(payment.id).status == :pending
    end

    test "a terminal payment is a no-op" do
      order = order_fixture()
      payment = sent_attempt(order)
      Test.settle!(payment.malipo_payment_id, "R1")
      assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})

      # A duplicate callback re-runs the job; nothing changes.
      assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})
      assert Orders.timeline(order) |> Enum.count() == 2
    end

    test "a payment with no rail id yet waits rather than calling out" do
      payment = payment_fixture()

      future = System.system_time(:second) + 60

      assert {:snooze, 3} =
               perform_job(ConfirmPayment, %{"payment_id" => payment.id, "deadline" => future})
    end

    test "a top-up settles into the ledger" do
      payment = topup_fixture(%{amount_cents: 40_000})
      sent = send_attempt(payment)
      Test.settle!(sent.malipo_payment_id, "R2")

      assert :ok = perform_job(ConfirmPayment, %{"payment_id" => payment.id})

      assert Wallet.balance(payment.user_id) == 40_000
    end

    test "an unknown payment is discarded" do
      assert {:discard, :unknown_payment} = perform_job(ConfirmPayment, %{"payment_id" => -1})
    end
  end

  describe "SweepPendingPayments" do
    test "re-enqueues only pending attempts past the prompt window" do
      stale = stubbed_attempt("malipo-stale") |> backdate(120)
      fresh = stubbed_attempt("malipo-fresh")
      given_up = stubbed_attempt("malipo-old") |> backdate(7_200)
      never_sent = payment_fixture()

      assert :ok = perform_job(SweepPendingPayments, %{})

      probed = all_enqueued(worker: ConfirmPayment) |> Enum.map(& &1.args["payment_id"])

      assert probed == [stale.id]
      refute fresh.id in probed
      refute given_up.id in probed
      refute never_sent.id in probed
    end
  end

  # A pending attempt that already has a rail id, without going through the
  # create job (whose own enqueue would muddy "what did the sweep enqueue").
  defp stubbed_attempt(malipo_id) do
    {:ok, sent} = payment_fixture() |> Payments.mark_pending(malipo_id)
    sent
  end

  defp sent_attempt(order) do
    payment_fixture(%{order: order}) |> send_attempt()
  end

  defp send_attempt(payment) do
    assert :ok = perform_job(CreatePayment, %{"payment_id" => payment.id})
    assert %Payment{malipo_payment_id: malipo_id} = sent = Payments.get_payment!(payment.id)
    assert malipo_id =~ "test-"
    sent
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
