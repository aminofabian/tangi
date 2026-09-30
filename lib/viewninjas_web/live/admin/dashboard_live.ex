defmodule ViewNinjasWeb.Admin.DashboardLive do
  @moduledoc """
  The back office overview (scope.md §10, §11; build-plan.md M9).

  The business in one screen, as far as M9 can honestly read it: the order funnel
  from paid to completed, how payments settle, the money still at risk, the real
  margin from the panel's own charges, and anything that raised an alert while
  the screen was open. Profit trends, targets and traffic are M10's job.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.{Alerts, Margin, Observability, Overview, Sms}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Alerts.subscribe()

    {:ok, socket |> assign(:page_title, gettext("Admin")) |> assign(:alerts, []) |> load()}
  end

  @impl true
  def handle_info({:alert, alert}, socket) do
    {:noreply, assign(socket, :alerts, [alert | Enum.take(socket.assigns.alerts, 9)])}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Overview")}
      admin={:overview}
    >
      <section class="vn-card">
        <p class="vn-muted">
          {gettext("Signed in as %{email} (%{role}).",
            email: @current_scope.user.email,
            role: @current_scope.user.role
          )}
        </p>
        <p class="vn-actions">
          <.link navigate={~p"/admin/orders"} class="vn-button vn-button--muted">
            {gettext("Orders")} ({@review.needs_review + @review.partial})
          </.link>
          <.link navigate={~p"/admin/suppliers"} class="vn-button vn-button--muted">
            Suppliers
          </.link>
          <.link navigate={~p"/admin/catalog"} class="vn-button vn-button--muted">Catalog</.link>
          <.link
            :if={@current_scope.user.role == :super_admin}
            navigate={~p"/admin/insight"}
            class="vn-button vn-button--muted"
            id="admin-insight-link"
          >
            {gettext("Insight")}
          </.link>
        </p>
      </section>

      <section class="vn-card" id="funnel">
        <h2>{gettext("Orders")}</h2>
        <ul class="vn-stats">
          <li :for={{state, count} <- @funnel} id={"funnel-#{state}"}>
            <span class="vn-muted">{ViewNinjasWeb.OrderComponents.state_label(state)}</span>
            <span class="vn-stat__value">{count}</span>
          </li>
        </ul>
      </section>

      <section class="vn-card" id="money">
        <h2>{gettext("Money")}</h2>
        <dl class="vn-detail">
          <dt>{gettext("Money at risk")}</dt>
          <dd id="money-at-risk">{kes(@money_at_risk)}</dd>
          <dt>{gettext("Payments settled")}</dt>
          <dd id="payments-settled">{Map.get(@payments, :settled, 0)}</dd>
          <dt>{gettext("Payments failed")}</dt>
          <dd id="payments-failed">{Map.get(@payments, :failed, 0)}</dd>
          <dt>{gettext("Payments pending")}</dt>
          <dd id="payments-pending">{Map.get(@payments, :pending, 0)}</dd>
          <dt>{gettext("SMS sent today")}</dt>
          <dd id="sms-today">{@sms_today}</dd>
        </dl>
      </section>

      <section class="vn-card" id="health">
        <h2>{gettext("Health")}</h2>
        <dl class="vn-detail">
          <dt>{gettext("Payments settled")}</dt>
          <dd id="health-settled-rate">{rate(@health.payments.settled_rate)}</dd>
          <dt>{gettext("OTP delivered")}</dt>
          <dd id="health-otp-rate">{rate(@health.otp.delivery_rate)}</dd>
          <dt>{gettext("Placements succeeded")}</dt>
          <dd id="health-placement-rate">{rate(1 - (@health.placement.error_rate || 0))}</dd>
          <dt>{gettext("Jobs waiting")}</dt>
          <dd id="health-queue">
            {@health.queue.available} · {div(@health.queue.lag_seconds, 60)} min behind
          </dd>
        </dl>
      </section>

      <section class="vn-card" id="margin">
        <h2>{gettext("Margin by week")}</h2>
        <p class="vn-muted">
          {gettext("Retail against the panel's real charge, at each order's own rate.")}
        </p>
        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>{gettext("Week")}</th>
                <th>{gettext("Orders")}</th>
                <th>{gettext("Retail")}</th>
                <th>{gettext("Cost")}</th>
                <th>{gettext("Profit")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={week <- @margin_weeks} id={"week-#{week.week}"}>
                <td>{week.week}</td>
                <td>{week.orders}</td>
                <td>{kes(week.retail_cents)}</td>
                <td>{kes(week.cost_cents)}</td>
                <td>{kes(week.profit_cents)}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@margin_weeks == []} class="vn-muted">
          {gettext("No charged orders yet — margin appears as panels report.")}
        </p>
      </section>

      <section :if={@alerts != []} class="vn-card" id="alerts">
        <h2>{gettext("Alerts")}</h2>
        <ul class="vn-orders">
          <li :for={alert <- @alerts} class="vn-order-row">
            <span>{alert.message}</span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  defp load(socket) do
    assign(socket,
      funnel: Overview.funnel(),
      payments: Overview.payment_counts(),
      review: Overview.review_counts(),
      money_at_risk: Overview.money_at_risk_cents(),
      sms_today: Sms.count_today(),
      health: Observability.snapshot(),
      margin_weeks: Margin.by_week()
    )
  end

  defp kes(nil), do: "—"
  defp kes(cents), do: ViewNinjas.Pricing.format_kes_cents(cents)

  defp rate(nil), do: "—"
  defp rate(fraction), do: "#{Float.round(fraction * 100.0, 1)}%"
end
