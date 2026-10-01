defmodule ViewNinjasWeb.AirtimeHistoryLive do
  @moduledoc """
  A customer's airtime history (scope: `docs/instalipa-airtime.md`).

  Every top-up this customer has bought, newest first, with the totals above it and a
  per-order timeline they can open.

  Two things this page is really for:

    * **the money is accounted for.** A refund is the moment a customer most needs to
      be believed, so the summary carries the refunded figure outright and each
      refunded order says plainly that the money went back to their wallet;
    * **nothing is a black box.** The timeline shows the states the order actually
      passed through, so "it hasn't arrived yet" is answerable without support.

  There is no PubSub for airtime, so the page does not subscribe: it reads on mount
  and re-reads when the filter or the expanded order changes. An airtime order only
  moves while a confirming job is running, and a customer watching a history page is
  looking for a record, not a live feed — they can refresh or re-filter.

  Every read is scoped to `current_scope.user`, so one customer can never see
  another's airtime, timeline or totals.
  """

  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.OrderComponents

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Airtime
  alias ViewNinjas.Airtime.AirtimeOrder
  alias ViewNinjasWeb.Analytics

  @limit 100

  # "Still going" is the money-taken-but-not-yet-delivered set. `needs_review` is in
  # it deliberately: an ambiguous send is still owed airtime, and the customer's
  # money is still being looked after.
  @going [:paid, :sending, :submitted, :needs_review]

  # The states an airtime order can be in that `OrderComponents` has no wording for.
  # It knows the social-order vocabulary; `:delivered` is the airtime word for what it
  # calls `:completed`, and `:sending`/`:submitted` are the rail hop. Everything else
  # falls through to `state_label/1` so both pages stay in step.
  @airtime_labels %{
    delivered: "Delivered",
    sending: "Sending",
    submitted: "Sent to the network"
  }

  # The state pill, in airtime's words. `OrderComponents.state_pill/1` renders
  # social-order states, and airtime has three it has never heard of — so it would
  # print them as the raw lowercase atom. Same markup, same colours, our wording.
  attr :state, :atom, required: true

  defp airtime_pill(assigns) do
    ~H"""
    <span class={["vn-state", "vn-state--#{@state}"]}>{state_word(@state)}</span>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    # `handle_params/3` always runs after `mount/3` and does the real read, so these
    # are the safe starting points rather than a second identical query.
    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:orders, [])
     |> assign(:stats, %{spent: 0, refunded: 0, delivered: 0, failed: 0})
     |> assign(:total, 0)
     |> assign(:filter, "all")
     |> assign(:page, 1)
     |> assign(:expanded_id, nil)
     |> assign(:timeline, nil)}
  end

  @impl true
  def handle_params(params, uri, socket) do
    Analytics.record_page_view(socket, uri)
    {:noreply, load(socket, filter_from(params["filter"]), parse_id(params["id"]))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      section={:shop}
      title={gettext("Airtime history")}
    >
      <.summary stats={@stats} />

      <section class="vn-card" id="airtime-history-filters">
        <h2>{gettext("Show")}</h2>
        <div class="vn-chips" id="airtime-history-chips">
          <.link
            :for={chip <- filters()}
            patch={~p"/airtime/history?filter=#{chip.name}"}
            class={["vn-chip", @filter == chip.name && "vn-chip--on"]}
            id={"history-filter-#{chip.name}"}
          >
            {chip.label}
          </.link>
        </div>
      </section>

      <section :if={@orders == []} class="vn-card" id="airtime-history-empty">
        <h2>{gettext("Nothing here")}</h2>
        <%= cond do %>
          <% @total == 0 -> %>
            <p class="vn-muted">
              {gettext("You haven't bought any airtime yet. Buy some and it will show up here.")}
            </p>
          <% true -> %>
            <p class="vn-muted">
              {gettext("None of your airtime is in that group. Try another one.")}
            </p>
        <% end %>
        <.link navigate={~p"/airtime"} class="vn-button" id="airtime-history-buy">
          {gettext("Buy airtime")}
        </.link>
      </section>

      <ul class="vn-orders" id="airtime-history">
        <li :for={order <- @orders} id={"airtime-history-#{order.id}"} class="vn-order-card">
          <div
            class="flex items-start justify-between gap-3 w-full"
            id={"airtime-history-head-#{order.id}"}
          >
            <span class="vn-order-link__body">
              <span class="vn-order-link__title">{Phone.format(order.phone)}</span>
              <span class="vn-order-link__meta">
                {kes(order.amount_cents)} · {format_at(order.inserted_at)}
              </span>
            </span>
            <.airtime_pill state={order.state} />
          </div>

          <div :if={Phone.network(order.phone)} class="flex items-center gap-2">
            <span class="vn-net" id={"airtime-history-net-#{order.id}"}>
              {Phone.network_name(Phone.network(order.phone))}
            </span>
          </div>

          <%!-- A refunded top-up is the one line on this page nobody should have to
                ask about: the money is back, and here is where it went. --%>
          <p
            :if={order.state == :refunded}
            class="vn-open-note"
            id={"airtime-history-refund-#{order.id}"}
          >
            {gettext("Your %{amount} went back to your wallet. Nothing was charged for it.",
              amount: kes(order.amount_cents)
            )}
          </p>

          <%!-- The rail's own words, kept as a note under the plain-language state
                pill rather than as the headline. --%>
          <p
            :if={order.failure_message}
            class="vn-muted"
            id={"airtime-history-failure-#{order.id}"}
          >
            {gettext("What the network said: %{message}", message: order.failure_message)}
          </p>

          <dl
            :if={order.state == :delivered}
            class="vn-detail"
            id={"airtime-history-receipt-#{order.id}"}
          >
            <dt :if={order.receipt}>{gettext("Receipt")}</dt>
            <dd :if={order.receipt} class="vn-breakall">{order.receipt}</dd>
            <dt :if={order.reference}>{gettext("Reference")}</dt>
            <dd :if={order.reference} class="vn-breakall">{order.reference}</dd>
          </dl>

          <.link
            patch={timeline_path(@filter, order.id, @expanded_id == order.id)}
            class="vn-text-button"
            id={"history-timeline-#{order.id}"}
          >
            {timeline_label(@expanded_id == order.id)}
          </.link>

          <%= if @expanded_id == order.id do %>
            <ol class="vn-timeline" id={"airtime-timeline-#{order.id}"}>
              <li
                :for={event <- @timeline}
                id={"airtime-timeline-event-#{event.id}"}
                class="vn-timeline__item"
              >
                <span class="vn-timeline__state">{event_label(event)}</span>
                <span :if={event.reason} class="vn-muted">{event.reason}</span>
                <span class="vn-muted vn-timeline__at">{format_at(event.inserted_at)}</span>
              </li>
            </ol>
          <% end %>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  # -- the money, accounted for ------------------------------------------

  attr :stats, :map, required: true

  defp summary(assigns) do
    ~H"""
    <section class="vn-card" id="airtime-history-summary">
      <h2>{gettext("Your airtime so far")}</h2>
      <div class="vn-stats" id="airtime-history-stats">
        <div class="vn-stat" id="airtime-history-spent">
          <span class="vn-stat__label">{gettext("Spent")}</span>
          <span class="vn-stat__value">{kes(figure(@stats, :spent))}</span>
        </div>
        <div class="vn-stat" id="airtime-history-refunded-stat">
          <span class="vn-stat__label">{gettext("Refunded")}</span>
          <span class="vn-stat__value">{kes(figure(@stats, :refunded))}</span>
        </div>
        <div class="vn-stat" id="airtime-history-delivered-stat">
          <span class="vn-stat__label">{gettext("Delivered")}</span>
          <span class="vn-stat__value">{figure(@stats, :delivered)}</span>
        </div>
        <div class="vn-stat" id="airtime-history-failed-stat">
          <span class="vn-stat__label">{gettext("Not delivered")}</span>
          <span class="vn-stat__value">{figure(@stats, :failed)}</span>
        </div>
      </div>

      <div :if={figure(@stats, :refunded) > 0} class="vn-summary" id="airtime-history-refunded">
        <span>{gettext("Back in your wallet")}</span>
        <span class="vn-summary__total">{kes(figure(@stats, :refunded))}</span>
      </div>

      <p :if={figure(@stats, :failed) > 0} class="vn-open-note" id="airtime-history-problems">
        {gettext(
          "%{count} of your top-ups didn't go through. We are on them and you are not out of pocket.",
          count: figure(@stats, :failed)
        )}
      </p>
    </section>
    """
  end

  # -- the filters -------------------------------------------------------

  # Built as a function, not a module attribute, so each label is a real `gettext/1`
  # call the backend can extract and translate.
  defp filters do
    [
      %{name: "all", label: gettext("All")},
      %{name: "delivered", label: gettext("Delivered")},
      %{name: "refunded", label: gettext("Refunded")},
      %{name: "failed", label: gettext("Failed")},
      %{name: "going", label: gettext("Still going")}
    ]
  end

  defp filter_from(nil), do: "all"

  defp filter_from(name) when is_binary(name) do
    if name in Enum.map(filters(), & &1.name), do: name, else: "all"
  end

  # Filtering happens here, over the already-loaded page of orders: five small groups
  # do not justify a second query or a context function.
  defp keep?(_order, "all"), do: true
  defp keep?(order, "delivered"), do: order.state == :delivered
  defp keep?(order, "refunded"), do: order.state == :refunded
  # `needs_review` counts as failed for the same reason it is in the summary's
  # "not delivered" figure: it is not airtime in the customer's hand.
  defp keep?(order, "failed"), do: order.state in [:failed, :needs_review]
  defp keep?(order, "going"), do: order.state in @going
  defp keep?(_order, _unknown), do: true

  # -- the timeline ------------------------------------------------------

  # Opening the timeline drops it when it is already open, and switching filter drops
  # it too: an order outside the current filter has no row to hang it on.
  defp timeline_path(_filter, _order_id, true), do: ~p"/airtime/history"

  defp timeline_path(filter, order_id, false),
    do: ~p"/airtime/history?filter=#{filter}&id=#{order_id}"

  defp timeline_label(true), do: gettext("Hide timeline")
  defp timeline_label(false), do: gettext("Show timeline")

  # The event stores its states as strings, because the timeline has to keep reading
  # correctly after a state is renamed or withdrawn. Map one back to an atom to get
  # the customer's words for it.
  defp event_label(%{to_state: to_state}) when is_binary(to_state), do: state_word(to_state)

  defp event_label(%{from_state: from_state}) when is_binary(from_state),
    do: state_word(from_state)

  defp event_label(_event), do: ""

  defp state_word(nil), do: ""

  defp state_word(state) when is_atom(state),
    do: @airtime_labels[state] || state_label(state)

  defp state_word(string) when is_binary(string) do
    case Enum.find(AirtimeOrder.states(), &(to_string(&1) == string)) do
      nil -> string
      atom -> state_word(atom)
    end
  end

  defp state_word(other), do: to_string(other)

  # -- internals ---------------------------------------------------------

  defp load(socket, filter, id) do
    user = socket.assigns.current_scope.user
    %{orders: orders, stats: stats} = Airtime.history_for_user(user, limit: @limit)
    {expanded_id, timeline} = timeline_for(user, id)

    socket
    |> assign(:filter, filter)
    |> assign(:page, 1)
    |> assign(:stats, stats)
    |> assign(:total, length(orders))
    |> assign(:orders, Enum.filter(orders, &keep?(&1, filter)))
    |> assign(:expanded_id, expanded_id)
    |> assign(:timeline, timeline)
  end

  # Scoped to the owner on purpose: an `id` from the query string must never be able
  # to open another customer's timeline.
  defp timeline_for(_user, nil), do: {nil, nil}

  defp timeline_for(user, id) do
    case Airtime.get_order_for_user(user, id) do
      nil -> {nil, nil}
      order -> {order.id, Airtime.timeline(order)}
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_id(_id), do: nil

  defp figure(stats, key), do: Map.get(stats, key) || 0

  defp format_at(nil), do: ""
  defp format_at(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
end
