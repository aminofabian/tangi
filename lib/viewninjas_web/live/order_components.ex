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

  @doc "An order the customer can still pay for."
  def payable?(%{state: :awaiting_payment}), do: true
  def payable?(_order), do: false

  @doc """
  An order they can buy again.

  One at a time: an order still being delivered is not repeated, because buying the
  same service again now would be a duplicate the customer pays for twice. An open
  payment is finished, not copied.
  """
  def repeatable?(%{state: :awaiting_payment}), do: false
  def repeatable?(%{state: state}) when is_atom(state), do: not Order.blocking?(state)
  def repeatable?(_order), do: false

  @doc """
  The note shown on an order that is holding its service, so "order again" is absent
  for a reason the customer can read.
  """
  def in_progress_note(%{state: state}) when is_atom(state) do
    if Order.blocking?(state) do
      gettext("This one's still on its way. Order it again once it's done.")
    end
  end

  def in_progress_note(_order), do: nil

  @doc "The offer to land on when the old grade is off sale, with the link kept."
  def offer_again_path(%{lane: %{offer: %{id: id}}, link: link, quantity: quantity}) do
    ~p"/offers/#{id}?link=#{link}&quantity=#{quantity}"
  end

  @doc "What the customer bought, when the offer is loaded."
  @spec order_title(map()) :: String.t()
  def order_title(%{lane: %{offer: %{title: title}}}) when is_binary(title), do: title
  def order_title(_order), do: gettext("Your order")

  @doc "A KES price, or an em dash."
  @spec kes(integer() | nil) :: String.t()
  def kes(nil), do: "—"
  def kes(cents), do: Pricing.format_kes_cents(cents)

  @doc "The four beats of delivery, once an order is paid."
  def delivery_steps do
    [
      %{label: gettext("Paid")},
      %{label: gettext("Sent")},
      %{label: gettext("Arriving")},
      %{label: gettext("Here")}
    ]
  end

  @doc "Where this order sits on the delivery rail, or nil when it has left that story."
  def runway_index(state) do
    case state do
      s when s in [:paid, :placing] -> 0
      :placed -> 1
      s when s in [:in_progress, :partial] -> 2
      :completed -> 3
      _ -> nil
    end
  end

  @doc "The sentence under the delivery rail."
  def runway_note(:paid),
    do: gettext("Paid. We're sending it now — this page updates on its own.")

  def runway_note(:placing), do: runway_note(:paid)
  def runway_note(:placed), do: gettext("Sent. It's in the queue, and you'll see it move here.")

  def runway_note(:in_progress),
    do: gettext("Arriving. The count on this page moves as they land.")

  def runway_note(:partial),
    do: gettext("Part of it landed. The rest is back in your wallet.")

  def runway_note(:completed), do: gettext("Here. All of them arrived.")
  def runway_note(_state), do: nil

  @doc "An order state from the raw string on an `OrderEvent`, when we know it."
  @spec state_from_string(String.t() | nil) :: atom() | nil
  def state_from_string(string) when is_binary(string) do
    Enum.find(Order.states(), &(Atom.to_string(&1) == string))
  end

  def state_from_string(_string), do: nil
end
