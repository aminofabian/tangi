defmodule ViewNinjas.OrdersFixtures do
  @moduledoc """
  Test helpers for the money milestones (build-plan.md M7): orders, payment
  attempts, and wallet entries.
  """

  alias ViewNinjas.AccountsFixtures
  alias ViewNinjas.CatalogFixtures
  alias ViewNinjas.{Orders, Payments, Wallet}

  @doc """
  An order for a verified user against a published lane.

  Pass `:user`, `:offer`, `:lane`, `:link`, `:quantity`, and `paid: true` to end
  with a paid order.
  """
  def order_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || AccountsFixtures.verified_user_fixture()
    offer = Map.get(attrs, :offer) || CatalogFixtures.published_offer_fixture()
    lane = Map.get(attrs, :lane) || List.first(offer.lanes)

    {:ok, order} =
      Orders.create_order(%{
        user: user,
        lane: lane,
        link: Map.get(attrs, :link, "https://instagram.com/viewninjas"),
        quantity: Map.get(attrs, :quantity, 1000)
      })

    if Map.get(attrs, :paid, false) do
      {:ok, paid} = Orders.mark_paid(order, "TESTRECEIPT")
      paid
    else
      order
    end
  end

  @doc "A local payment attempt for an order (not yet created at the rail)."
  def payment_fixture(attrs \\ %{}) do
    order = Map.get(attrs, :order) || order_fixture()

    {:ok, payment} = Payments.start_order_payment(order)
    payment
  end

  @doc "A paid order with its lane, pinned service and supplier loaded."
  def paid_order_with_lane_fixture(attrs \\ %{}) do
    attrs
    |> Map.put(:paid, true)
    |> order_fixture()
    |> then(&Orders.get_order_with_lane(&1.id))
  end

  @doc """
  An order the panel has accepted: `placed`, with the supplier columns and a
  supplier order id, as if `add` had answered.
  """
  def supplier_order_fixture(attrs \\ %{}) do
    order = paid_order_with_lane_fixture(Map.delete(attrs, :supplier_order_id))
    service = order.lane.supplier_service

    {:ok, placing} = Orders.mark_placing(order, service.supplier_id, service.id)
    {:ok, placed} = Orders.mark_placed(placing, Map.get(attrs, :supplier_order_id, "SUP-1"))
    placed
  end

  @doc "A completed order, with its lane, pinned service and supplier loaded."
  def completed_order_fixture(attrs \\ %{}) do
    order = supplier_order_fixture(attrs)
    {:ok, _completed} = Orders.transition(order, :completed, reason: "supplier said Completed")
    Orders.get_order_with_lane(order.id)
  end

  @doc """
  An order the panel reported `Partial`: the remains are written and the
  undelivered share is credited back to the wallet.
  """
  def partial_order_fixture(attrs \\ %{}) do
    order = supplier_order_fixture(attrs)

    {:ok, partial} =
      Orders.apply_supplier_status(order, %{
        status: "Partial",
        start_count: 0,
        remains: Map.get(attrs, :remains, 250),
        currency: "USD"
      })

    partial
  end

  @doc "A local top-up attempt for a user."
  def topup_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || AccountsFixtures.verified_user_fixture()
    amount = Map.get(attrs, :amount_cents, 10_000)

    {:ok, payment} = Payments.start_topup_payment(user, amount)
    payment
  end

  @doc "Credits a wallet directly, for tests that need a balance to spend."
  def credit_fixture(user_or_id, cents) do
    user_id = if is_integer(user_or_id), do: user_or_id, else: user_or_id.id
    {:ok, entry} = Wallet.record(%{user_id: user_id, amount_cents: cents, reason: :adjustment})
    entry
  end
end
