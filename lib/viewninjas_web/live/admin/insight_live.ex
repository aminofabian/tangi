defmodule ViewNinjasWeb.Admin.InsightLive do
  @moduledoc """
  The insight screen (scope.md §10, §11; build-plan.md M10). Super-admin only.

  One screen that answers the four questions: the month's profit, whether the
  target is on track, where the visitors came from, and where the funnel leaks —
  plus the same thing as the Sunday message, so what you read here and what
  arrives on Sunday cannot drift apart.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.{Analysis, Digest, Pricing, Profit, Progress, Traffic}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, gettext("Insight")) |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Insight")}
      admin={:insight}
    >
      <section class="vn-card" id="profit">
        <h2>{gettext("Profit")}</h2>
        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th></th>
                <th>{gettext("Today")}</th>
                <th>{gettext("This week")}</th>
                <th>{gettext("This month")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- profit_rows(@today, @week, @month)} id={"profit-#{row.key}"}>
                <td>{row.label}</td>
                <td>{row.today}</td>
                <td>{row.week}</td>
                <td>{row.month}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="vn-card" id="break-even">
        <h2>{gettext("Break-even")}</h2>
        <p :if={@break_even.orders_needed} id="break-even-line">
          {gettext("%{orders} orders this month cover %{fixed} of fixed cost at the current margin.",
            orders: @break_even.orders_needed,
            fixed: kes(@break_even.fixed_cents)
          )}
        </p>
        <p :if={!@break_even.orders_needed} class="vn-muted">
          {gettext("No margin to divide yet — the line appears once an order is charged.")}
        </p>
      </section>

      <section class="vn-card" id="trend">
        <h2>{gettext("This month, day by day")}</h2>
        <ul class="vn-stats">
          <li :for={day <- @trend} id={"trend-#{day.day}"}>
            <span class="vn-muted">{day.day}</span>
            <span class="vn-stat__value">{kes(day.profit_cents)}</span>
          </li>
        </ul>
        <p :if={@trend == []} class="vn-muted">
          {gettext("The daily rollup fills in from tonight.")}
        </p>
      </section>

      <section class="vn-card" id="progress">
        <h2>{gettext("Progress")}</h2>
        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>{gettext("Metric")}</th>
                <th>{gettext("Period")}</th>
                <th>{gettext("Goal")}</th>
                <th>{gettext("Actual")}</th>
                <th>{gettext("Delta")}</th>
                <th>{gettext("Days left")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- @progress} id={"target-#{row.period}-#{row.metric}"}>
                <td>{Progress.label(row.metric)}</td>
                <td>{row.period}</td>
                <td>{Progress.format(row.metric, row.goal)}</td>
                <td>{Progress.format(row.metric, row.actual)}</td>
                <td>{Progress.format(row.metric, row.delta)}</td>
                <td>{row.days_left}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@progress == []} class="vn-muted">{gettext("No targets set.")}</p>
        <dl class="vn-detail">
          <dt>{gettext("Settled-order streak")}</dt>
          <dd id="streak">{@streak}</dd>
          <dt>{gettext("Repeat rate (30 days)")}</dt>
          <dd id="repeat-rate">{repeat_label(@repeat)}</dd>
        </dl>
      </section>

      <section class="vn-card" id="traffic">
        <h2>{gettext("Traffic")}</h2>
        <p class="vn-muted" id="traffic-totals">
          {gettext("Uniques — today %{today}, 7 days %{week}, 30 days %{month}.",
            today: @traffic.today.uniques,
            week: @traffic.week.uniques,
            month: @traffic.month.uniques
          )}
        </p>

        <h3>{gettext("The funnel")}</h3>
        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>{gettext("Step")}</th>
                <th>{gettext("Count")}</th>
                <th>{gettext("Conversion")}</th>
                <th>{gettext("Drop")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={step <- @traffic.funnel} id={"funnel-#{step.step}"}>
                <td>
                  {step.step}
                  <span :if={@leak == step.step} class="vn-error" id="biggest-leak">
                    {gettext("biggest leak")}
                  </span>
                </td>
                <td>{step.count}</td>
                <td>{percent(step.conversion)}</td>
                <td>{percent(step.drop)}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <h3>{gettext("Sources")}</h3>
        <ul class="vn-stats">
          <li :for={source <- @traffic.sources} id={"source-#{source.source}"}>
            <span class="vn-muted">{source.source}</span>
            <span class="vn-stat__value">{source.visits}</span>
          </li>
        </ul>

        <h3>{gettext("Devices")}</h3>
        <ul class="vn-stats">
          <li :for={device <- @traffic.devices} id={"device-#{device.device}"}>
            <span class="vn-muted">{device.device}</span>
            <span class="vn-stat__value">{device.visits}</span>
          </li>
        </ul>

        <h3>{gettext("Offers: viewed against bought")}</h3>
        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>{gettext("Offer")}</th>
                <th>{gettext("Viewed")}</th>
                <th>{gettext("Bought")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={offer <- @traffic.offers} id={"offer-gap-#{offer.offer_id}"}>
                <td>#{offer.offer_id}</td>
                <td>{offer.viewed}</td>
                <td>{offer.bought}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <section class="vn-card" id="digest">
        <h2>{gettext("The Sunday message")}</h2>
        <pre class="vn-digest" phx-no-curly-interpolation id="digest-body">{@digest}</pre>
      </section>
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load(socket) do
    at = Date.utc_today()
    month = window(:month, at)
    funnel = Traffic.funnel(elem(month, 0), elem(month, 1))

    assign(socket,
      today: Profit.for_period(:day, at),
      week: Profit.for_period(:week, at),
      month: Profit.for_period(:month, at),
      break_even: Profit.break_even(:month, at),
      trend: Traffic.daily(%{at | day: 1}, at),
      progress: Progress.status(at),
      streak: Progress.streak(at),
      repeat: Progress.repeat_rate(),
      traffic: traffic(at, month, funnel),
      leak: biggest_leak(funnel),
      digest: Digest.body(Analysis.digest(at))
    )
  end

  defp traffic(at, month, funnel) do
    {from, to} = month

    %{
      today: totals(window(:day, at)),
      week: totals(window(:week, at)),
      month: totals(month),
      funnel: funnel,
      sources: Traffic.sources(from, to, 6),
      devices: Traffic.devices(from, to),
      offers: offer_gaps(from, to)
    }
  end

  defp totals({from, to}),
    do: %{visits: Traffic.visits(from, to), uniques: Traffic.uniques(from, to)}

  defp offer_gaps(from, to) do
    viewed = Traffic.offer_views(from, to)
    bought = Traffic.offers_bought(from, to)

    viewed
    |> Enum.sort_by(fn {_id, count} -> count end, :desc)
    |> Enum.take(8)
    |> Enum.map(fn {offer_id, count} ->
      %{offer_id: offer_id, viewed: count, bought: Map.get(bought, offer_id, 0)}
    end)
  end

  defp window(period, at) do
    {from_date, to_date} = Profit.bounds(period, at)

    {DateTime.new!(from_date, ~T[00:00:00]), DateTime.new!(Date.add(to_date, 1), ~T[00:00:00])}
  end

  defp biggest_leak(funnel) do
    funnel
    |> Enum.reject(&is_nil(&1.drop))
    |> Enum.max_by(& &1.drop, fn -> nil end)
    |> case do
      nil -> nil
      step -> step.step
    end
  end

  defp profit_rows(today, week, month) do
    [
      {"revenue", "Revenue", & &1.revenue_cents},
      {"cogs", "Cost of goods", & &1.cogs_cents},
      {"gross", "Gross profit", & &1.gross_cents},
      {"fees", "Malipo fees", & &1.fees_cents},
      {"sms", "SMS", & &1.sms_cents},
      {"other", "Other costs", & &1.other_cents},
      {"net", "Net profit", & &1.net_cents}
    ]
    |> Enum.map(fn {key, label, field} ->
      %{
        key: key,
        label: label,
        today: kes(field.(today)),
        week: kes(field.(week)),
        month: kes(field.(month))
      }
    end)
  end

  defp repeat_label(%{rate: nil}), do: "—"

  defp repeat_label(%{rate: rate, repeat: repeat, total: total}),
    do: "#{repeat}/#{total} (#{percent(rate)})"

  defp percent(nil), do: "—"
  defp percent(fraction), do: "#{Float.round(fraction * 100, 1)}%"

  defp kes(cents), do: Pricing.format_kes_cents(cents)
end
