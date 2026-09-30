defmodule ViewNinjasWeb.Admin.OrdersLive do
  @moduledoc """
  The admin review queue (scope.md §11; build-plan.md M9): the orders waiting on
  a person — `needs_review`, where `add` never resolved, and `partial`, where the
  panel delivered part of what was paid for.

  A `needs_review` order is reconciled by hand: attach the supplier's order id
  when it did exist, or refund it when it never did. A `partial` order shows what
  was credited back automatically, so support can check the arithmetic.
  """

  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.OrderComponents

  alias ViewNinjas.Orders
  alias ViewNinjas.Orders.Order

  @filters [
    {"needs_review", [:needs_review]},
    {"partial", [:partial]},
    {"all", [:needs_review, :partial]}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, gettext("Orders")) |> assign(:filters, @filters)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = filter_for(params["state"], @filters)
    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  @impl true
  def handle_event("attach", %{"attach" => params}, socket) do
    with {order_id, ""} <- Integer.parse(params["order_id"] || ""),
         %Order{} = order <- Orders.get_order(order_id),
         {:ok, _placed} <- Orders.admin_attach(order, params["supplier_order_id"], actor(socket)) do
      {:noreply, socket |> put_flash(:info, "Attached supplier order.") |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not attach that id.")}
    end
  end

  def handle_event("refund", %{"order_id" => id}, socket) do
    with {order_id, ""} <- Integer.parse(id),
         %Order{} = order <- Orders.get_order(order_id),
         {:ok, _refunded} <- Orders.admin_refund(order, actor(socket)) do
      {:noreply, socket |> put_flash(:info, "Refunded to the wallet.") |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Could not refund that order.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Orders")}
      admin={:orders}
    >
      <section class="vn-card">
        <div class="vn-chips">
          <.link
            :for={{label, _states} <- @filters}
            patch={~p"/admin/orders?state=#{label}"}
            class={["vn-chip", @filter == label && "vn-chip--on"]}
            id={"filter-#{label}"}
          >
            {filter_label(label)}
          </.link>
        </div>
        <p class="vn-muted">
          {gettext("Orders a person has to reconcile. A customer never has to call.")}
        </p>
      </section>

      <section :if={@rows == []} class="vn-card" id="no-orders">
        <h2>{gettext("Nothing waiting")}</h2>
        <p class="vn-muted">{gettext("Every order is moving on its own.")}</p>
      </section>

      <section :for={row <- @rows} class="vn-card" id={"order-#{row.order.id}"}>
        <div class="flex items-start justify-between gap-3">
          <h2>{order_title(row.order)}</h2>
          <.state_pill state={row.order.state} />
        </div>
        <dl class="vn-detail">
          <dt>{gettext("Order")}</dt>
          <dd>#{row.order.id}</dd>
          <dt>{gettext("Link")}</dt>
          <dd class="vn-breakall">{row.order.link}</dd>
          <dt>{gettext("Paid")}</dt>
          <dd>{kes(row.order.retail_cents)} · {row.order.quantity}</dd>
          <dt :if={row.order.supplier_order_id}>{gettext("Supplier order")}</dt>
          <dd :if={row.order.supplier_order_id}>{row.order.supplier_order_id}</dd>
          <dt :if={row.order.supplier_status}>{gettext("Panel said")}</dt>
          <dd :if={row.order.supplier_status}>{row.order.supplier_status}</dd>
          <dt :if={row.credit}>{gettext("Already credited")}</dt>
          <dd :if={row.credit}>{kes(row.credit)}</dd>
        </dl>

        <div :if={row.order.state == :needs_review} class="mt-3">
          <.form for={row.form} id={"attach-form-#{row.order.id}"} phx-submit="attach">
            <.input type="hidden" field={row.form[:order_id]} />
            <.input field={row.form[:supplier_order_id]} label={gettext("Supplier order id")} />
            <button class="vn-button" id={"attach-#{row.order.id}"}>{gettext("Attach")}</button>
          </.form>

          <button
            class="vn-button vn-button--muted mt-2"
            phx-click="refund"
            phx-value-order_id={row.order.id}
            id={"refund-#{row.order.id}"}
          >
            {gettext("It was never placed — refund")}
          </button>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

  defp actor(socket), do: socket.assigns.current_scope.user

  defp load(socket) do
    rows =
      socket.assigns.filter
      |> states_for()
      |> Orders.list_by_states()
      |> Enum.map(&row/1)

    assign(socket, :rows, rows)
  end

  defp row(%Order{} = order) do
    %{
      order: order,
      credit: credit(order),
      form: to_form(%{"order_id" => order.id, "supplier_order_id" => ""}, as: "attach")
    }
  end

  # Only a partial has money to show back; a needs_review order was never placed.
  defp credit(%Order{state: :partial} = order), do: Orders.partial_cents(order)
  defp credit(%Order{}), do: nil

  defp filter_for(state, filters) do
    if Enum.any?(filters, fn {label, _states} -> label == state end),
      do: state,
      else: "needs_review"
  end

  defp states_for(filter) do
    {_label, states} = Enum.find(@filters, fn {label, _states} -> label == filter end)
    states
  end

  defp filter_label("needs_review"), do: gettext("Needs review")
  defp filter_label("partial"), do: gettext("Partial")
  defp filter_label(_all), do: gettext("All")
end
