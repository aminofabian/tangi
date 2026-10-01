defmodule ViewNinjas.AirtimeFixtures do
  @moduledoc """
  Test helpers for airtime (docs/instalipa-airtime.md): a funded customer and the
  orders a buy produces. Jobs are not run here — tests perform them explicitly.
  """

  alias ViewNinjas.AccountsFixtures
  alias ViewNinjas.Airtime
  alias ViewNinjas.Wallet

  @doc "A verified customer whose wallet already holds `cents` (default KSh 1,000)."
  def funded_user(cents \\ 100_000) do
    user = AccountsFixtures.verified_user_fixture()
    {:ok, _entry} = Wallet.record(%{user_id: user.id, amount_cents: cents, reason: :adjustment})
    user
  end

  @doc "Buys airtime and returns the orders it created."
  def airtime_orders_fixture(attrs \\ %{}) do
    user = Map.get(attrs, :user) || funded_user()
    amount_cents = Map.get(attrs, :amount_cents, 10_000)
    phones = Map.get(attrs, :phones, ["254712345678"])

    {:ok, orders} = Airtime.buy(user, %{amount_cents: amount_cents, phones: phones})
    orders
  end

  @doc "One airtime order for a funded customer."
  def airtime_order_fixture(attrs \\ %{}) do
    attrs |> airtime_orders_fixture() |> List.first()
  end
end
