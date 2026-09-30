defmodule ViewNinjas.Progress do
  @moduledoc """
  Goals against reality (scope.md §11; build-plan.md M10).

  A number without a target is trivia, so every headline metric can carry a
  `Target` for a day, week or month. This context reports each metric's newest
  target beside its actual, the delta and the days left — plus the two habits the
  scope singles out: the streak of days with at least one settled order, and the
  share of customers who come back within 30 days.
  """

  import Ecto.Query

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Insight.Target
  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Pricing
  alias ViewNinjas.Profit
  alias ViewNinjas.Repo

  @repeat_window_days 30

  # -- targets -----------------------------------------------------------

  @doc "Every target, newest first."
  @spec list_targets(keyword()) :: [Target.t()]
  def list_targets(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Target
    |> order_by([t], desc: t.effective_at, desc: t.id)
    |> limit(^limit)
    |> preload(:setter)
    |> Repo.all()
  end

  @doc "Sets a target; a change is a new effective row, never an edit."
  @spec create_target(map(), User.t() | nil) :: {:ok, Target.t()} | {:error, Ecto.Changeset.t()}
  def create_target(params, actor) do
    params =
      params
      |> Map.put_new("set_by", actor && actor.id)
      |> Map.put_new("effective_at", DateTime.utc_now(:second))

    %Target{}
    |> Target.changeset(params)
    |> Repo.insert()
  end

  def change_target(%Target{} = target, attrs \\ %{}), do: Target.changeset(target, attrs)

  @doc "The newest target for each metric and period."
  @spec current_targets() :: [Target.t()]
  def current_targets do
    list_targets() |> Enum.uniq_by(&{&1.metric, &1.period})
  end

  # -- goals against reality ---------------------------------------------

  @doc "Each current target with its actual, delta and days left, at `at`."
  @spec status(Date.t()) :: [map()]
  def status(at \\ Date.utc_today()) do
    current_targets()
    |> Enum.map(&status_row(&1, at))
    |> Enum.sort_by(&{&1.period, &1.metric})
  end

  defp status_row(%Target{} = target, at) do
    actual = actual_value(target.metric, target.period, at)

    %{
      target: target,
      metric: target.metric,
      period: target.period,
      goal: target.value_cents,
      actual: actual,
      delta: actual - target.value_cents,
      days_left: days_left(target.period, at)
    }
  end

  @doc "The actual value of a metric for a period ending on `at`."
  @spec actual_value(atom(), atom(), Date.t()) :: integer()
  def actual_value(:revenue, period, at), do: Profit.for_period(period, at).revenue_cents

  def actual_value(:orders, period, at) do
    p = Profit.for_period(period, at)
    Profit.captured_count(p.from, p.to)
  end

  def actual_value(:new_customers, period, at) do
    {from, to} = datetime_bounds(period, at)

    Repo.one(
      from u in User, where: u.inserted_at >= ^from and u.inserted_at < ^to, select: count(u.id)
    )
  end

  def actual_value(:margin, period, at) do
    p = Profit.for_period(period, at)
    if p.revenue_cents > 0, do: div(p.gross_cents * 10_000, p.revenue_cents), else: 0
  end

  @doc "How many days are left in the period containing `at`."
  @spec days_left(atom(), Date.t()) :: non_neg_integer()
  def days_left(:day, _at), do: 0
  def days_left(:week, at), do: 7 - Date.day_of_week(at)
  def days_left(:month, at), do: Date.days_in_month(at) - at.day

  # -- the two habits ----------------------------------------------------

  @doc """
  Consecutive days, ending today or yesterday, with at least one settled order.

  Today is not held against the streak until it is over: a Sunday report read on
  Sunday morning still shows the run going.
  """
  @spec streak(Date.t()) :: non_neg_integer()
  def streak(at \\ Date.utc_today()) do
    days = settled_days()
    start = if MapSet.member?(days, at), do: at, else: Date.add(at, -1)
    count_streak(days, start, 0)
  end

  @doc "The share of customers who ordered again within 30 days."
  @spec repeat_rate() :: %{
          repeat: non_neg_integer(),
          total: non_neg_integer(),
          rate: float() | nil
        }
  def repeat_rate do
    orders =
      Repo.all(
        from o in Order,
          select: {o.user_id, o.inserted_at},
          order_by: [asc: o.inserted_at, asc: o.id]
      )

    by_user = Enum.group_by(orders, &elem(&1, 0))
    total = map_size(by_user)

    repeat =
      Enum.count(by_user, fn {_user_id, rows} ->
        repeat_within?(Enum.map(rows, &elem(&1, 1)), @repeat_window_days)
      end)

    %{repeat: repeat, total: total, rate: if(total > 0, do: repeat / total, else: nil)}
  end

  # -- labels ------------------------------------------------------------

  @doc "The words for a metric."
  @spec label(atom() | String.t()) :: String.t()
  def label(metric) when metric in [:revenue, "revenue"], do: "Revenue"
  def label(metric) when metric in [:orders, "orders"], do: "Orders"
  def label(metric) when metric in [:new_customers, "new_customers"], do: "New customers"
  def label(metric) when metric in [:margin, "margin"], do: "Margin"
  def label(other), do: to_string(other)

  @doc "A metric value as a human string (money, a count, or a percentage)."
  @spec format(atom(), integer() | nil) :: String.t()
  def format(:revenue, value) when is_integer(value), do: Pricing.format_kes_cents(value)
  def format(:margin, value) when is_integer(value), do: "#{Float.round(value / 100, 2)}%"
  def format(_metric, value) when is_integer(value), do: Integer.to_string(value)
  def format(_metric, nil), do: "—"

  defp settled_days do
    Payment
    |> where([p], p.status == :settled and p.purpose == :order)
    |> select([p], fragment("?::date", p.inserted_at))
    |> Repo.all()
    |> MapSet.new()
  end

  defp count_streak(days, date, count) do
    if MapSet.member?(days, date) do
      count_streak(days, Date.add(date, -1), count + 1)
    else
      count
    end
  end

  defp repeat_within?(times, days) do
    times
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [first, second] ->
      Date.diff(DateTime.to_date(second), DateTime.to_date(first)) <= days
    end)
  end

  defp datetime_bounds(period, at) do
    {from_date, to_date} = Profit.bounds(period, at)
    {DateTime.new!(from_date, ~T[00:00:00]), DateTime.new!(Date.add(to_date, 1), ~T[00:00:00])}
  end
end
