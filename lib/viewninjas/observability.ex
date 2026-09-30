defmodule ViewNinjas.Observability do
  @moduledoc """
  Is the machine healthy (scope.md §11, §13; build-plan.md M12).

  Four questions, answered from the rows the earlier milestones already write, so
  there is no third-party APM and nothing new to store: what share of payments
  settle, what share of OTPs arrive, what share of placements succeed, and how far
  behind the job queue is. `Analysis` reads the same numbers to decide what to
  alert on — one place, so the dashboard and the alert cannot disagree.
  """

  import Ecto.Query

  alias ViewNinjas.Orders.OrderEvent
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Repo
  alias ViewNinjas.Sms.SmsMessage

  # Seconds of queue lag that would say a job is late.
  @queue_lag_seconds 900

  @doc "Everything about the last 24 hours, plus the live queue."
  @spec snapshot(DateTime.t()) :: map()
  def snapshot(now \\ DateTime.utc_now(:second)) do
    {from, to} = window(now)

    %{
      payments: payment_health(from, to),
      otp: otp_health(from, to),
      placement: placement_health(from, to),
      queue: queue_lag(now)
    }
  end

  @doc "How payments settled in a window."
  @spec payment_health(DateTime.t(), DateTime.t()) :: map()
  def payment_health(from, to) do
    counts = status_counts(Payment, from, to)

    settled = Map.get(counts, :settled, 0)
    failed = Map.get(counts, :failed, 0)

    %{
      settled: settled,
      failed: failed,
      pending: Map.get(counts, :pending, 0),
      settled_rate: ratio(settled, settled + failed)
    }
  end

  @doc "How the OTPs delivered in a window."
  @spec otp_health(DateTime.t(), DateTime.t()) :: map()
  def otp_health(from, to) do
    counts = sms_status_counts(from, to)
    sent = counts |> Map.values() |> Enum.sum()

    %{
      sent: sent,
      delivered: Map.get(counts, :delivered, 0),
      failed: Map.get(counts, :failed, 0),
      delivery_rate: ratio(Map.get(counts, :delivered, 0), sent)
    }
  end

  @doc "How placements went in a window: placed against failed and needs_review."
  @spec placement_health(DateTime.t(), DateTime.t()) :: map()
  def placement_health(from, to) do
    counts =
      OrderEvent
      |> where(
        [e],
        e.inserted_at >= ^from and e.inserted_at < ^to and
          e.to_state in ["placed", "failed", "needs_review"]
      )
      |> group_by([e], e.to_state)
      |> select([e], {e.to_state, count(e.id)})
      |> Repo.all()
      |> Map.new()

    placed = Map.get(counts, "placed", 0)
    failed = Map.get(counts, "failed", 0)
    review = Map.get(counts, "needs_review", 0)

    %{
      placed: placed,
      failed: failed,
      needs_review: review,
      error_rate: ratio(failed + review, placed + failed + review)
    }
  end

  @doc "How far behind the Oban queue is, and how much is waiting."
  @spec queue_lag(DateTime.t()) :: map()
  def queue_lag(now \\ DateTime.utc_now(:second)) do
    counts = oban_counts()
    oldest = oldest_waiting()

    lag = if oldest, do: max(DateTime.diff(now, oldest), 0), else: 0

    %{
      available: Map.get(counts, "available", 0),
      scheduled: Map.get(counts, "scheduled", 0),
      executing: Map.get(counts, "executing", 0),
      retryable: Map.get(counts, "retryable", 0),
      lag_seconds: lag
    }
  end

  @doc "The number of seconds of queue lag that means a job is late."
  @spec queue_lag_seconds() :: pos_integer()
  def queue_lag_seconds, do: @queue_lag_seconds

  # -- internals ---------------------------------------------------------

  defp status_counts(schema, from, to) do
    schema
    |> where([r], r.inserted_at >= ^from and r.inserted_at < ^to)
    |> group_by([r], r.status)
    |> select([r], {r.status, count(r.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp sms_status_counts(from, to) do
    SmsMessage
    |> where([m], m.inserted_at >= ^from and m.inserted_at < ^to)
    |> group_by([m], m.status)
    |> select([m], {m.status, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp oban_counts do
    Oban.Job
    |> group_by([j], j.state)
    |> select([j], {j.state, count(j.id)})
    |> Repo.all()
    |> Map.new()
  end

  defp oldest_waiting do
    Repo.one(
      from j in Oban.Job,
        where: j.state in ["available", "scheduled"],
        select: min(j.scheduled_at)
    )
  end

  defp ratio(_numerator, 0), do: nil
  defp ratio(numerator, denominator), do: numerator / denominator

  defp window(now), do: {DateTime.add(now, -86_400), now}
end
