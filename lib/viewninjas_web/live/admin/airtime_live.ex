defmodule ViewNinjasWeb.Admin.AirtimeLive do
  @moduledoc """
  The airtime back office (docs/instalipa-airtime.md §9, §10, §12). Super-admin
  only.

  Two numbers sit above the queue, because they are the two ways this line loses
  money:

    * the **float**, read from the rail's own newest `balance` and never estimated,
      with the floor it has to stay above and the kill switch that stops selling
      whatever the rail says;
    * the **money still owed** — taken from a wallet and not yet returned. That
      figure has to reach zero on its own, so it is stated plainly and the failed
      filter is one tap away.

  Below them the queue itself, `needs_review` first, because that is the rows with
  a person's money in them waiting on a decision. Every row carries its own
  timeline, so the reconciliation can be read rather than reconstructed.
  """

  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.OrderComponents

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Airtime
  alias ViewNinjas.Airtime.AirtimeOrder
  alias ViewNinjas.Settings

  @default_filter "needs_review"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Airtime"))
     |> assign(:float_form, float_form())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = filter_for(params["state"], Airtime.review_filters())
    {:noreply, socket |> assign(:filter, filter) |> load()}
  end

  # The kill switch (scope §10): one tap stops the line taking money, whatever the
  # rail is reporting. Written as a setting rather than in memory so it survives a
  # restart — a pause that forgets itself is not a pause.
  @impl true
  def handle_event("toggle_pause", _params, socket) do
    if Airtime.paused?() do
      :ok = Settings.clear("instalipa_paused")
      {:noreply, socket |> put_flash(:info, gettext("Selling airtime again.")) |> load()}
    else
      case Settings.put("instalipa_paused", "true", actor(socket)) do
        {:ok, _setting} ->
          {:noreply, socket |> put_flash(:info, gettext("Selling airtime is paused.")) |> load()}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not pause selling."))}
      end
    end
  end

  # The escape hatch out of a float stop (scope §10). Instalipa has no balance
  # endpoint, so the portal figure is the only way we can learn a float we did not
  # read from a send — and without it, a stop caused by a low float is a one-way door.
  def handle_event("record_float", %{"float" => params}, socket) do
    with {:ok, cents} <- parse_shillings(params["amount"]) do
      :ok = Airtime.record_float(cents, actor(socket))

      {:noreply,
       socket
       |> put_flash(:info, gettext("Float recorded — selling follows it from here."))
       |> load()}
    else
      :error ->
        {:noreply,
         put_flash(socket, :error, gettext("Enter the balance in whole shillings, as 5000."))}
    end
  end

  def handle_event("forget_float", _params, socket) do
    :ok = Airtime.forget_float()

    {:noreply,
     socket
     |> put_flash(:info, gettext("Back to reading the float from the rail."))
     |> load()}
  end

  def handle_event("refund", %{"order_id" => id}, socket) do
    with {order_id, ""} <- Integer.parse(id),
         %AirtimeOrder{} = order <- Airtime.get_order(order_id),
         {:ok, _refunded} <- Airtime.refund(order, actor: actor(socket)) do
      {:noreply, socket |> put_flash(:info, gettext("Refunded to the wallet.")) |> load()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not refund that order."))}
    end
  end

  def handle_event("reconcile", %{"airtime" => params}, socket) do
    with {order_id, ""} <- Integer.parse(params["order_id"] || ""),
         %AirtimeOrder{} = order <- Airtime.get_order(order_id),
         {:ok, _delivered} <-
           Airtime.reconcile_delivered(order, params["instalipa_id"] || "", actor(socket)) do
      {:noreply, socket |> put_flash(:info, gettext("Marked delivered.")) |> load()}
    else
      {:error, :missing_transaction_id} ->
        {:noreply, put_flash(socket, :error, gettext("Paste the transaction id first."))}

      {:error, :not_reconcilable} ->
        {:noreply,
         put_flash(socket, :error, gettext("That order cannot be marked delivered from here."))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not mark that delivered."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Airtime")}
      admin={:airtime}
    >
      <%!-- The float and the switch that stops the line. Instalipa has no balance
            endpoint (scope §10), so a rail reading only exists as a side effect of a
            send — which is why the manual entry below is not a convenience. --%>
      <section class="vn-card" id="airtime-float">
        <h2>{gettext("Float and the kill switch")}</h2>
        <dl class="vn-detail">
          <dt>{gettext("Float")}</dt>
          <dd :if={@float} id="airtime-float-now">{kes(@float.cents)}</dd>
          <dd :if={!@float} id="airtime-float-unknown">
            {gettext("Unknown — the rail has never reported one")}
          </dd>
          <dt :if={@float}>{gettext("Last read")}</dt>
          <dd :if={@float}>
            <span id="airtime-float-at">{format_at(@float.at)}</span>
            <span :if={@float.source == :manual} id="airtime-float-source" class="vn-muted">
              {gettext("entered by hand")}
            </span>
            <span :if={@float.source == :rail && @float.stale?} id="airtime-float-stale">
              {gettext("too old to hold selling off")}
            </span>
          </dd>
          <dt>{gettext("Floor")}</dt>
          <dd id="airtime-floor">{kes(@float_floor)}</dd>
          <dt>{gettext("Selling")}</dt>
          <dd id="airtime-selling">{sellable_label(@pause_reason)}</dd>
        </dl>

        <p :if={@below_floor} class="vn-error" id="airtime-float-low">
          {gettext("The float is under the floor, so selling is off on its own.")}
        </p>
        <p
          :if={@float && @float.source == :rail && @float.stale?}
          class="vn-muted"
          id="airtime-float-stale-note"
        >
          {gettext(
            "This figure is as old as the last send that reported one. It is not holding selling off, because it cannot describe the float now."
          )}
        </p>
        <p :if={@paused} class="vn-error" id="airtime-paused-by-hand">
          {gettext("Paused by hand. The buy screen refuses before taking any money.")}
        </p>

        <button
          :if={@paused}
          type="button"
          class="vn-button"
          phx-click="toggle_pause"
          id="airtime-resume"
        >
          {gettext("Start selling again")}
        </button>
        <button
          :if={!@paused}
          type="button"
          class="vn-button vn-button--muted"
          phx-click="toggle_pause"
          id="airtime-pause"
        >
          {gettext("Stop selling airtime")}
        </button>

        <%!-- The escape hatch (scope §10). Instalipa tells us the balance only as a
              side effect of a send, so a top-up made in their portal is invisible here.
              Without this, a float that dipped far enough to stop selling could never
              be seen to recover, because the recovery would require the sends that the
              stop forbids. --%>
        <div class="mt-4">
          <h3>{gettext("Tell us the float")}</h3>
          <p class="vn-muted" id="airtime-float-entry-hint">
            {gettext(
              "Read the balance from the Instalipa portal and enter it in shillings. This replaces the reading above until a send reports a newer one."
            )}
          </p>

          <.form for={@float_form} id="airtime-float-form" phx-submit="record_float">
            <.input
              field={@float_form[:amount]}
              label={gettext("Float now (shillings)")}
              inputmode="numeric"
              placeholder={gettext("e.g. 5000")}
            />
            <button class="vn-button" id="airtime-float-record">{gettext("Record the float")}</button>
          </.form>

          <button
            :if={@float_manual}
            type="button"
            class="vn-button vn-button--muted mt-2"
            phx-click="forget_float"
            id="airtime-float-forget"
          >
            {gettext("Forget it and read the rail again")}
          </button>
        </div>
      </section>

      <%!-- The number that has to reach zero by itself. --%>
      <section class="vn-card" id="airtime-owed">
        <h2>{gettext("Money still owed")}</h2>
        <p class="vn-total__value" id="airtime-owed-amount">{kes(@owed)}</p>

        <%= if @owed == 0 do %>
          <p class="vn-muted" id="airtime-owed-clear">
            {gettext("Nothing is owed. Every shilling taken has been returned.")}
          </p>
        <% else %>
          <p class="vn-error" id="airtime-owed-open">
            {gettext(
              "Taken from a wallet and not yet returned. Work through the failed and the being-checked orders."
            )}
          </p>
          <.link
            patch={~p"/admin/airtime?state=failed"}
            class="vn-button vn-button--muted"
            id="airtime-owed-failed"
          >
            {gettext("Show the failed ones")}
          </.link>
        <% end %>
      </section>

      <section class="vn-card" id="airtime-counters">
        <h2>{gettext("Where the orders are")}</h2>
        <ul class="vn-stats">
          <li :for={state <- @states} id={"count-#{state}"}>
            <span class="vn-muted">{state_label(state)}</span>
            <span class="vn-stat__value">{Map.get(@counts, state, 0)}</span>
          </li>
        </ul>
      </section>

      <section class="vn-card">
        <div class="vn-chips">
          <.link
            :for={{label, _states} <- @filters}
            patch={~p"/admin/airtime?state=#{label}"}
            class={["vn-chip", @filter == label && "vn-chip--on"]}
            id={"filter-#{label}"}
          >
            {filter_label(label)}
          </.link>
        </div>
        <p class="vn-muted">
          {gettext("Orders waiting on a person, being checked first. A customer never has to call.")}
        </p>
      </section>

      <section :if={@rows == []} class="vn-card" id="no-airtime">
        <h2>{gettext("Nothing waiting")}</h2>
        <p class="vn-muted">{gettext("Every airtime order is moving on its own.")}</p>
      </section>

      <section :for={row <- @rows} class="vn-card" id={"airtime-#{row.order.id}"}>
        <div class="flex items-start justify-between gap-3">
          <h2>{Phone.format(row.order.phone)}</h2>
          <.state_pill state={row.order.state} />
        </div>
        <dl class="vn-detail">
          <dt>{gettext("Order")}</dt>
          <dd>{row.order.id}</dd>
          <dt>{gettext("Amount")}</dt>
          <dd id={"airtime-amount-#{row.order.id}"}>{kes(row.order.amount_cents)}</dd>
          <dt>{gettext("Customer")}</dt>
          <dd class="vn-breakall" id={"airtime-customer-#{row.order.id}"}>
            {customer_email(row.order)}
          </dd>
          <dt :if={row.order.discount_cents}>{gettext("Rail discount")}</dt>
          <dd :if={row.order.discount_cents}>{kes(row.order.discount_cents)}</dd>
          <dt>{gettext("Reference")}</dt>
          <dd class="vn-breakall">{row.order.reference}</dd>
          <dt :if={row.order.instalipa_id}>{gettext("Rail transaction")}</dt>
          <dd :if={row.order.instalipa_id} class="vn-breakall">{row.order.instalipa_id}</dd>
          <dt :if={row.order.instalipa_status}>{gettext("Rail said")}</dt>
          <dd :if={row.order.instalipa_status}>{row.order.instalipa_status}</dd>
          <dt :if={row.order.receipt}>{gettext("Receipt")}</dt>
          <dd :if={row.order.receipt} class="vn-breakall">{row.order.receipt}</dd>
          <dt :if={row.order.failure_kind}>{gettext("Failed because")}</dt>
          <dd :if={row.order.failure_kind}>{row.order.failure_kind}</dd>
          <dt :if={row.order.failure_message}>{gettext("What the rail said")}</dt>
          <dd :if={row.order.failure_message}>{row.order.failure_message}</dd>
        </dl>

        <%!-- The reconcile (scope §9, §12): it did go out, or it never did. Never a
              second send on the same intent either way. --%>
        <div :if={row.order.state == :needs_review} class="mt-3">
          <.form for={row.form} id={"airtime-form-#{row.order.id}"} phx-submit="reconcile">
            <.input type="hidden" field={row.form[:order_id]} />
            <.input field={row.form[:instalipa_id]} label={gettext("Rail transaction id")} />
            <button class="vn-button" id={"airtime-delivered-#{row.order.id}"}>
              {gettext("It was delivered")}
            </button>
          </.form>

          <button
            class="vn-button vn-button--muted mt-2"
            phx-click="refund"
            phx-value-order_id={row.order.id}
            id={"airtime-refund-#{row.order.id}"}
          >
            {gettext("It was never sent — refund")}
          </button>
        </div>

        <%!-- A `failed` row whose refund never landed is money we still owe. The
              sweep normally settles it within a minute; the button is here so a
              person is never the only way it gets settled. --%>
        <div :if={row.order.state == :failed} class="mt-3">
          <button
            class="vn-button"
            phx-click="refund"
            phx-value-order_id={row.order.id}
            id={"airtime-refund-failed-#{row.order.id}"}
          >
            {gettext("Refund the wallet now")}
          </button>
        </div>

        <h3>{gettext("Timeline")}</h3>
        <ol class="vn-timeline" id={"timeline-#{row.order.id}"}>
          <li :for={event <- row.timeline} id={"airtime-event-#{event.id}"} class="vn-timeline__item">
            <span class="vn-timeline__state">{state_label(event.to_state)}</span>
            <span :if={event.reason} class="vn-muted">{event.reason}</span>
            <span :if={event.actor} class="vn-muted">{event.actor.email}</span>
            <span class="vn-muted vn-timeline__at">{format_at(event.inserted_at)}</span>
          </li>
        </ol>
      </section>
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

  defp actor(socket), do: socket.assigns.current_scope.user

  defp load(socket) do
    filters = Airtime.review_filters()

    rows =
      filters
      |> states_for(socket.assigns.filter)
      |> Airtime.list_for_review()
      |> Enum.map(&row/1)

    assign(socket,
      rows: rows,
      filters: filters,
      states: AirtimeOrder.states(),
      counts: Airtime.counts_by_state(),
      float: Airtime.float(),
      float_manual: Settings.airtime_float_manual_cents(),
      float_floor: Airtime.float_floor_cents(),
      below_floor: Airtime.below_float_floor?(),
      pause_reason: Airtime.pause_reason(),
      paused: Airtime.paused?(),
      owed: Airtime.outstanding_refund_cents()
    )
  end

  defp float_form, do: to_form(%{"amount" => ""}, as: "float")

  # Shillings in, cents out — the rail's own figures are in shillings, and a float
  # balance is read off a portal page rather than typed from memory.
  defp parse_shillings(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {shillings, ""} when shillings >= 0 -> {:ok, shillings * 100}
      _ -> :error
    end
  end

  defp parse_shillings(_value), do: :error

  defp row(%AirtimeOrder{} = order) do
    %{
      order: order,
      timeline: Airtime.timeline(order),
      form: to_form(%{"order_id" => order.id, "instalipa_id" => ""}, as: "airtime")
    }
  end

  # `needs_review` rows are reconciled in one step: the pasted transaction id is what
  # makes the claim checkable against the rail later.
  defp customer_email(%AirtimeOrder{user: %{email: email}}), do: email
  defp customer_email(%AirtimeOrder{}), do: gettext("Unknown")

  defp sellable_label(nil), do: gettext("On")
  defp sellable_label(:paused), do: gettext("Off — paused by hand")
  defp sellable_label(:float_low), do: gettext("Off — the float is under the floor")

  defp filter_for(state, filters) do
    if Enum.any?(filters, fn {label, _states} -> label == state end),
      do: state,
      else: @default_filter
  end

  defp states_for(filters, filter) do
    {_label, states} = Enum.find(filters, fn {label, _states} -> label == filter end)
    states
  end

  defp filter_label("needs_review"), do: gettext("Needs review")
  defp filter_label("failed"), do: gettext("Failed")
  defp filter_label("open"), do: gettext("Open")
  defp filter_label("recent"), do: gettext("Recent")
  defp filter_label(_all), do: gettext("All")

  defp format_at(nil), do: ""
  defp format_at(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
end
