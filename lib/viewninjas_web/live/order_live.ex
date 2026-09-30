defmodule ViewNinjasWeb.OrderLive do
  @moduledoc """
  One order, live (scope.md §11): what was bought, what it cost, the M-Pesa
  receipt, and the timeline built from its `OrderEvent` rows.

  A paid order that is still moving is worth watching, so the page listens over
  PubSub and re-reads the order and its timeline when the panel reports a change.
  """
  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.OrderComponents

  alias ViewNinjas.{Orders, Payments}
  alias ViewNinjas.Orders.Order
  alias ViewNinjasWeb.Analytics

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket), do: Orders.subscribe(socket.assigns.current_scope.user)

    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:order, nil)
     |> assign(:timeline, [])
     |> assign(:receipt, nil)
     |> assign(:refill, nil)}
  end

  @impl true
  def handle_params(%{"id" => id}, uri, socket) do
    Analytics.record_page_view(socket, uri)

    case Orders.get_order_for_user(socket.assigns.current_scope.user, parse_id(id)) do
      nil -> {:noreply, push_navigate(socket, to: ~p"/orders")}
      order -> {:noreply, load(socket, order)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, push_navigate(socket, to: ~p"/orders")}

  @impl true
  def handle_info({:order, %Order{id: id}}, socket) do
    if socket.assigns.order && socket.assigns.order.id == id do
      {:noreply, load(socket, Orders.get_order_for_user(socket.assigns.current_scope.user, id))}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("refill", _params, socket) do
    case Orders.request_refill(socket.assigns.order) do
      {:ok, _refill} ->
        {:noreply, socket |> put_flash(:info, gettext("Refill requested.")) |> refresh()}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("That order cannot be refilled."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      section={:orders}
      title={gettext("Order")}
    >
      <section :if={@order} class="vn-card" id="order-summary">
        <div class="flex items-start justify-between gap-3">
          <h2>{order_title(@order)}</h2>
          <.state_pill state={@order.state} />
        </div>
        <dl class="vn-detail">
          <dt>{gettext("Grade")}</dt>
          <dd>{@order.lane.grade}</dd>
          <dt>{gettext("How many")}</dt>
          <dd>{@order.quantity}</dd>
          <dt>{gettext("Link")}</dt>
          <dd class="vn-breakall">{@order.link}</dd>
          <dt>{gettext("Paid")}</dt>
          <dd>{kes(@order.retail_cents)}</dd>
          <dt :if={@receipt}>{gettext("M-Pesa receipt")}</dt>
          <dd :if={@receipt}>{@receipt}</dd>
          <dt :if={@order.start_count}>{gettext("Started from")}</dt>
          <dd :if={@order.start_count}>{@order.start_count}</dd>
          <dt :if={@order.remains}>{gettext("Remaining")}</dt>
          <dd :if={@order.remains}>{@order.remains}</dd>
        </dl>
        <p :if={@order.state == :needs_review} class="vn-muted">
          {gettext("We are checking this order by hand. Nothing is lost.")}
        </p>
      </section>

      <section :if={@order && @refillable} class="vn-card" id="refill">
        <h2>{gettext("Refill")}</h2>
        <p class="vn-muted">
          {gettext(
            "This grade came with a refill. If the count has dropped, you can ask for it once."
          )}
        </p>
        <button class="vn-button" phx-click="refill" id="refill-button">{gettext("Ask for a refill")}</button>
      </section>

      <section :if={@refill} class="vn-card" id="refill-status">
        <h2>{gettext("Refill")}</h2>
        <p class="vn-muted">{refill_message(@refill)}</p>
      </section>

      <section :if={@order} class="vn-card">
        <h2>{gettext("Timeline")}</h2>
        <ol class="vn-timeline" id="timeline">
          <li :for={event <- @timeline} id={"event-#{event.id}"} class="vn-timeline__item">
            <span class="vn-timeline__state">{event_label(event)}</span>
            <span :if={event.reason} class="vn-muted">{event.reason}</span>
            <span class="vn-muted vn-timeline__at">{format_at(event.inserted_at)}</span>
          </li>
        </ol>
      </section>
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load(socket, %Order{} = order) do
    socket
    |> assign(:page_title, order_title(order))
    |> assign(:order, order)
    |> assign(:timeline, Orders.timeline(order))
    |> assign(:receipt, receipt(order))
    |> assign(:refill, Orders.get_refill(order))
    |> assign(:refillable, Orders.refillable?(order))
  end

  defp refresh(socket),
    do:
      load(
        socket,
        Orders.get_order_for_user(socket.assigns.current_scope.user, socket.assigns.order.id)
      )

  defp refill_message(%{state: :requested}),
    do: gettext("We have requested the refill. This updates on its own.")

  defp refill_message(%{state: :completed}), do: gettext("The refill is done.")

  defp refill_message(%{state: :rejected, reason: reason}) when is_binary(reason),
    do: gettext("The refill could not go through: %{reason}", reason: reason)

  defp refill_message(%{state: :rejected}),
    do: gettext("The refill could not go through.")

  defp refill_message(_refill), do: ""

  defp receipt(order) do
    order
    |> Payments.list_for_order()
    |> Enum.find_value(& &1.receipt)
  end

  defp event_label(%{to_state: state}) do
    case state_from_string(state) do
      nil -> to_string(state)
      atom -> state_label(atom)
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp format_at(nil), do: ""
  defp format_at(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
end
