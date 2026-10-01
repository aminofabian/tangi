defmodule ViewNinjas.AirtimeTest do
  @moduledoc """
  Buying airtime (docs/instalipa-airtime.md): the wallet debit, bulk batches, the
  refund line, and saved numbers.
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.AirtimeFixtures

  alias ViewNinjas.Airtime
  alias ViewNinjas.Wallet

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

  describe "saved recipients" do
    test "saves a canonical number once, and updates its label" do
      user = user_fixture()

      assert {:ok, recipient} = Airtime.save_recipient(user, "0712 345 678", "Mum")
      assert recipient.phone == "254712345678"

      assert {:ok, again} = Airtime.save_recipient(user, "254712345678", "Mum ❤")
      assert again.id == recipient.id
      assert again.label == "Mum ❤"
      assert length(Airtime.list_recipients(user)) == 1
    end

    test "an invalid number is refused" do
      assert {:error, :invalid_phone} = Airtime.save_recipient(user_fixture(), "nope", nil)
    end

    test "delete removes only the customer's own number" do
      user = user_fixture()
      other = user_fixture()
      {:ok, recipient} = Airtime.save_recipient(user, "0712345678", nil)

      :ok = Airtime.delete_recipient(other, recipient.id)
      assert length(Airtime.list_recipients(user)) == 1

      :ok = Airtime.delete_recipient(user, recipient.id)
      assert Airtime.list_recipients(user) == []
    end
  end
end
