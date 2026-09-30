defmodule ViewNinjasWeb.OrdersLive do
  @moduledoc """
  The Orders tab (scope.md §11): everything this customer has bought, newest
  first, updating itself as the panels move.

  The list is fed by PubSub, and the broadcast carries the row, so a status
  change costs no query — the order is swapped in place.
  """
  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.OrderComponents

  alias ViewNinjas.Orders
  alias ViewNinjas.Orders.Order
  alias ViewNinjasWeb.Analytics

  @limit 50

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Orders.subscribe(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:orders, orders(socket))}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    Analytics.record_page_view(socket, uri)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:order, %Order{} = order}, socket) do
    {:noreply, assign(socket, :orders, merge(socket.assigns.orders, order))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      section={:orders}
      title={gettext("Orders")}
    >
      <section :if={@orders == []} class="vn-card" id="no-orders">
        <h2>{gettext("No orders yet")}</h2>
        <p class="vn-muted">
          {gettext("Buy followers, likes or views and they will appear here, live.")}
        </p>
        <.link navigate={~p"/shop"} class="vn-button">{gettext("Browse the shop")}</.link>
      </section>

      <ul :if={@orders != []} class="vn-orders" id="orders">
        <li :for={order <- @orders} id={"order-#{order.id}"} class="vn-order-row">
          <.link navigate={~p"/orders/#{order.id}"} class="vn-order-link">
            <span class="vn-order-link__body">
              <span class="vn-order-link__title">{order_title(order)}</span>
              <span class="vn-order-link__meta">
                {order.quantity} · {kes(order.retail_cents)}
              </span>
            </span>
            <.state_pill state={order.state} />
          </.link>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  defp orders(socket) do
    Orders.list_orders(socket.assigns.current_scope.user, limit: @limit)
  end

  defp merge(orders, %Order{} = order) do
    if Enum.any?(orders, &(&1.id == order.id)) do
      Enum.map(orders, &replace(&1, order))
    else
      [order | orders]
    end
  end

  defp replace(%Order{id: id} = _existing, %Order{id: id} = order), do: order
  defp replace(existing, _order), do: existing
end
