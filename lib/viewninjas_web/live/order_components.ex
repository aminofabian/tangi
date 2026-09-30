defmodule ViewNinjasWeb.OrderComponents do
  @moduledoc """
  The pieces the orders list and the order page share (scope.md §11): the state
  pill and the plain-language copy for every state an order can hold.
  """
  use ViewNinjasWeb, :html

  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Pricing

  @labels %{
    awaiting_payment: "Awaiting payment",
    abandoned: "Expired",
    paid: "Paid",
    placing: "Placing",
    placed: "Placed",
    needs_review: "Being checked",
    in_progress: "In progress",
    completed: "Completed",
    partial: "Partly delivered",
    canceled: "Canceled",
    refunded: "Refunded",
    failed: "Failed"
  }

  @doc "The customer-facing words for an order state."
  @spec state_label(atom() | String.t() | nil) :: String.t()
  def state_label(state) when is_atom(state), do: Map.get(@labels, state, to_string(state))
  def state_label(state) when is_binary(state), do: state
  def state_label(_state), do: ""

  @doc "The state pill. The colour is the state, so a customer can read it at a glance."
  attr :state, :atom, required: true

  def state_pill(assigns) do
    ~H"""
    <span class={["vn-state", "vn-state--#{@state}"]}>{state_label(@state)}</span>
    """
  end

  @doc "What the customer bought, when the offer is loaded."
  @spec order_title(map()) :: String.t()
  def order_title(%{lane: %{offer: %{title: title}}}) when is_binary(title), do: title
  def order_title(_order), do: gettext("Your order")

  @doc "A KES price, or an em dash."
  @spec kes(integer() | nil) :: String.t()
  def kes(nil), do: "—"
  def kes(cents), do: Pricing.format_kes_cents(cents)

  @doc "An order state from the raw string on an `OrderEvent`, when we know it."
  @spec state_from_string(String.t() | nil) :: atom() | nil
  def state_from_string(string) when is_binary(string) do
    Enum.find(Order.states(), &(Atom.to_string(&1) == string))
  end

  def state_from_string(_string), do: nil
end
