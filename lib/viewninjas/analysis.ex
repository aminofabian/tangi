defmodule ViewNinjas.Analysis do
  @moduledoc """
  The super-admin's read of the business (scope.md §11; build-plan.md M10, M12).

  Two things live here: the week's digest, and the anomaly checks. An anomaly is
  stated as data — a kind and a sentence — so the same finding can be raised as an
  alert during the day and carried in the Sunday message, rather than living twice.

  The settled rate, the OTP delivery rate, the placement error rate and the queue
  lag come from `ViewNinjas.Observability`, so the alert and the health panel read
  the same numbers and cannot disagree.
  """

  import Ecto.Query

  alias ViewNinjas.{Margin, Observability, Profit, Progress, Sms, Traffic}
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Repo

  # A settled-rate drop is only worth shouting about past a floor of attempts.
  @min_attempts 5
  @min_settled_rate 0.5
  @max_placement_error_rate 0.5
  @failure_spike 5
  @min_sms 10
  @min_delivery_rate 0.9
  @traffic_cliff 0.4
  @max_queue_backlog 100
  # A day's SMS volume more than this multiple of the week is a spike worth a look.
  @sms_spike_multiplier 3.0
  @min_sms_volume 20

  @doc """
  The week's digest: the P&L, orders, new customers, conversion, the best lane and
  the current anomalies — what the Sunday message carries (scope.md §11).
  """
  @spec digest(Date.t()) :: map()
  def digest(at \\ Date.utc_today()) do
    profit = Profit.for_period(:week, at)

    %{
      at: at,
      profit: profit,
      orders: Profit.captured_count(profit.from, profit.to),
      new_customers: Progress.actual_value(:new_customers, :week, at),
      conversion: conversion(profit.from, profit.to),
      best_lane: List.first(Margin.by_lane()),
      anomalies: anomalies()
    }
  end

  @doc "Every anomaly right now, as `[{kind, message}]`. Empty is the good answer."
  @spec anomalies(Date.t()) :: [{atom(), String.t()}]
  def anomalies(at \\ Date.utc_today()) do
    health = Observability.snapshot()

    []
    |> settled_rate(health)
    |> failure_spike()
    |> otp_slip(health)
    |> sms_spike(at)
    |> placement_errors(health)
    |> queue_backlog(health)
    |> negative_margin(at)
    |> traffic_cliff(at)
  end

  # -- checks ------------------------------------------------------------

  defp settled_rate(anomalies, %{payments: %{settled: settled, failed: failed}}) do
    attempts = settled + failed

    if attempts >= @min_attempts and settled / attempts < @min_settled_rate do
      anomalies ++
        [{:settled_rate_drop, "#{settled} of #{attempts} payments settled in the last day"}]
    else
      anomalies
    end
  end

  defp failure_spike(anomalies) do
    {from, to} = last_day()

    spikes =
      Payment
      |> where(
        [p],
        p.inserted_at >= ^from and p.inserted_at < ^to and p.status == :failed and
          not is_nil(p.failure_kind)
      )
      |> group_by([p], p.failure_kind)
      |> having([p], count(p.id) >= ^@failure_spike)
      |> select([p], {p.failure_kind, count(p.id)})
      |> Repo.all()

    Enum.reduce(spikes, anomalies, fn {kind, count}, acc ->
      acc ++ [{:failure_spike, "#{count} payments failed with '#{kind}' in the last day"}]
    end)
  end

  defp otp_slip(anomalies, %{otp: %{sent: sent, delivered: delivered}}) do
    if sent >= @min_sms and delivered / sent < @min_delivery_rate do
      anomalies ++
        [{:otp_delivery_slip, "#{delivered} of #{sent} messages delivered in the last day"}]
    else
      anomalies
    end
  end

  defp sms_spike(anomalies, at) do
    {from, to} = day_bounds(at)
    today = Sms.count_between(from, to)
    average = weekly_sms_average(at)

    if today >= @min_sms_volume and today > @sms_spike_multiplier * average do
      anomalies ++
        [{:sms_spike, "#{today} messages today against a #{round(average)}-a-day week"}]
    else
      anomalies
    end
  end

  defp placement_errors(anomalies, %{placement: placement}) do
    attempts = placement.placed + placement.failed + placement.needs_review
    errors = placement.failed + placement.needs_review

    if attempts >= @min_attempts and errors / attempts > @max_placement_error_rate do
      anomalies ++
        [
          {:supplier_error_rate,
           "#{errors} of #{attempts} placements did not succeed in the last day"}
        ]
    else
      anomalies
    end
  end

  defp queue_backlog(anomalies, %{queue: %{available: available, lag_seconds: lag}}) do
    if available > @max_queue_backlog or lag > Observability.queue_lag_seconds() do
      anomalies ++
        [{:queue_backlog, "#{available} jobs waiting, #{div(lag, 60)} minutes behind"}]
    else
      anomalies
    end
  end

  defp negative_margin(anomalies, at) do
    from = DateTime.new!(Date.add(at, -7), ~T[00:00:00])

    losers =
      Margin.by_order(limit: 500)
      |> Enum.filter(&(&1.at >= from and is_integer(&1.profit_cents) and &1.profit_cents < 0))

    case losers do
      [] ->
        anomalies

      [first | _] ->
        message =
          "#{length(losers)} order(s) sold below cost in the last week, " <>
            "e.g. order ##{first.order_id}"

        anomalies ++ [{:negative_margin, message}]
    end
  end

  defp traffic_cliff(anomalies, at) do
    {from, to} = day_bounds(at)
    today = Traffic.visits(from, to)
    average = recent_average(at)

    if average >= 5 and today < @traffic_cliff * average do
      anomalies ++
        [{:traffic_cliff, "#{today} visits today against a #{round(average)}-a-day week"}]
    else
      anomalies
    end
  end

  # -- helpers -----------------------------------------------------------

  defp weekly_sms_average(at) do
    days = for offset <- 1..7, do: Date.add(at, -offset)

    total =
      days
      |> Enum.map(fn date ->
        {from, to} = day_bounds(date)
        Sms.count_between(from, to)
      end)
      |> Enum.sum()

    total / 7
  end

  defp conversion(from, to) do
    Traffic.funnel(from, to)
    |> Enum.find(&(&1.step == "settled"))
    |> case do
      %{conversion: conversion} -> conversion
      _ -> nil
    end
  end

  defp recent_average(at) do
    days = for offset <- 1..7, do: Date.add(at, -offset)

    total =
      days
      |> Enum.map(fn date ->
        {from, to} = day_bounds(date)
        Traffic.visits(from, to)
      end)
      |> Enum.sum()

    total / 7
  end

  defp day_bounds(date) do
    {DateTime.new!(date, ~T[00:00:00]), DateTime.new!(Date.add(date, 1), ~T[00:00:00])}
  end

  defp last_day do
    now = DateTime.utc_now(:second)
    {DateTime.add(now, -86_400), now}
  end
end
