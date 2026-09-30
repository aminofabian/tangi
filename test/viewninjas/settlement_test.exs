defmodule ViewNinjas.SettlementTest do
  @moduledoc """
  Reconciling a settlement statement (build-plan.md M10, docs/malipo-connect.md §10):
  the four buckets, the reconciled fee, and the payout delta.
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Payments, Settlement}

  describe "import/2" do
    test "a matching line is matched and its fee lands on the payment" do
      {payment, line} = settled_payment_with_line(fee_cents: 500)

      {:ok, buckets} = Settlement.import("stmt-1", [line])

      assert buckets.counts[:matched] == 1
      assert Payments.get_payment!(payment.id).fee_cents == 500
    end

    test "a different gross is an amount mismatch and writes no fee" do
      {payment, line} = settled_payment_with_line(gross_delta: 100)

      {:ok, buckets} = Settlement.import("stmt-1", [line])

      assert buckets.counts[:amount_mismatch] == 1
      assert Payments.get_payment!(payment.id).fee_cents == nil
    end

    test "a line we have no payment for is provider only" do
      {:ok, buckets} =
        Settlement.import("stmt-1", [
          %{
            "provider_ref" => "malipo-unknown",
            "receipt" => "NOPE",
            "gross_cents" => 25_000,
            "fee_cents" => 100,
            "net_cents" => 24_900,
            "settled_on" => Date.utc_today()
          }
        ])

      assert buckets.counts[:provider_only] == 1
    end

    test "a settled payment the statement omits is local only" do
      {_payment, line} = settled_payment_with_line()
      # A statement that mentions a different payment: ours is left unmentioned.
      {:ok, buckets} = Settlement.import("stmt-1", [%{line | "provider_ref" => "someone-else"}])

      assert buckets.counts[:local_only] == 1
    end

    test "a re-import is a no-op, keyed on (statement_id, provider_ref)" do
      {payment, line} = settled_payment_with_line(fee_cents: 500)

      {:ok, _} = Settlement.import("stmt-1", [line])
      {:ok, buckets} = Settlement.import("stmt-1", [line])

      assert buckets.counts[:matched] == 1
      assert length(buckets.lines) == 1
      assert Payments.get_payment!(payment.id).fee_cents == 500
    end
  end

  describe "payout_delta/2" do
    test "is zero when the net matches what was received" do
      {_payment, line} = settled_payment_with_line(fee_cents: 500)
      {:ok, buckets} = Settlement.import("stmt-1", [line])

      assert Settlement.payout_delta("stmt-1", buckets.net_cents) == 0
    end

    test "is the gap when the till received less" do
      {_payment, line} = settled_payment_with_line(fee_cents: 500)
      {:ok, buckets} = Settlement.import("stmt-1", [line])

      assert Settlement.payout_delta("stmt-1", buckets.net_cents - 3_000) == 3_000
    end
  end

  describe "parse_csv/1" do
    test "reads a header row and the columns it names" do
      csv = """
      malipo_id,receipt,gross,fee,net,settled_on
      malipo-9,RCPT9,"1,250.00",12.50,"1,237.50",2026-09-29
      """

      assert {:ok, [line]} = Settlement.parse_csv(csv)
      assert line["provider_ref"] == "malipo-9"
      assert line["receipt"] == "RCPT9"
      assert line["gross_cents"] == 125_000
      assert line["fee_cents"] == 1_250
      assert line["net_cents"] == 123_750
      assert line["settled_on"] == ~D[2026-09-29]
    end

    test "refuses a statement with no reference column" do
      assert {:error, message} = Settlement.parse_csv("receipt,gross\nR1,10\n")
      assert message =~ "provider_ref"
    end
  end

  # A settled order payment and the statement line that should match it.
  defp settled_payment_with_line(opts \\ []) do
    order = paid_order_with_lane_fixture()
    payment = payment_fixture(%{order: order})
    {:ok, sent} = Payments.mark_pending(payment, "malipo-#{payment.id}")
    {:ok, settled} = Payments.settle(sent, "RCPT#{payment.id}")

    gross = settled.amount_cents + Keyword.get(opts, :gross_delta, 0)
    fee = Keyword.get(opts, :fee_cents, 0)

    line = %{
      "provider_ref" => settled.malipo_payment_id,
      "receipt" => settled.receipt,
      "gross_cents" => gross,
      "fee_cents" => fee,
      "net_cents" => gross - fee,
      "settled_on" => Date.utc_today()
    }

    {settled, line}
  end
end
