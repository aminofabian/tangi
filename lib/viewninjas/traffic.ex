defmodule ViewNinjas.Traffic do
  @moduledoc """
  First-party traffic (scope.md §6, §11, §13; build-plan.md M10).

  The `page_views` rows have been accruing since M6; this is where they are read.
  No cookie, no third party, no stored IP — a `visitor_hash` that rotates daily,
  so "unique" means unique within a day and never a person followed across days.

  The funnel runs home → offer → checkout started → payment settled → order placed,
  the first three counted by unique visitor and the last two by the money that
  actually moved. `analytics_daily` is the cheap, rebuildable rollup over all of it.
  """

  import Ecto.Query

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Insight.{AnalyticsDaily, PageView}
  alias ViewNinjas.Orders.{Order, OrderEvent}
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Profit
  alias ViewNinjas.Repo

  @shop_paths ["/", "/shop"]
  @rolled [:visits, :uniques, :signups, :orders, :revenue_cents, :cost_cents, :profit_cents]

  @doc "Page views in the window."
  @spec visits(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def visits(from, to) do
    Repo.one(from p in PageView, where: p.at >= ^from and p.at < ^to, select: count(p.id))
  end

  @doc "Distinct visitors in the window. Unique within a day, never across days."
  @spec uniques(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def uniques(from, to) do
    Repo.one(
      from p in PageView,
        where: p.at >= ^from and p.at < ^to and not is_nil(p.visitor_hash),
        select: count(p.visitor_hash, :distinct)
    )
  end

  @doc "Visits and uniques per day, oldest first."
  @spec daily_visits(Date.t(), Date.t()) :: [map()]
  def daily_visits(from_date, to_date) do
    {from, to} = datetime_bounds(from_date, to_date)

    PageView
    |> where([p], p.at >= ^from and p.at < ^to)
    |> group_by([p], fragment("?::date", p.at))
    |> select([p], %{
      day: fragment("?::date", p.at),
      visits: count(p.id),
      uniques: count(p.visitor_hash, :distinct)
    })
    |> order_by([p], asc: fragment("?::date", p.at))
    |> Repo.all()
  end

  @doc """
  The funnel for a window: `[%{step:, count:, conversion:, drop:}]`.

  The first three steps are unique visitors; `settled` and `placed` are counts of
  money and orders. `conversion` is against the first step, `drop` the share lost
  against the previous one — the biggest leak is the largest drop.
  """
  @spec funnel(DateTime.t(), DateTime.t()) :: [map()]
  def funnel(from, to) do
    counts = [
      {"shop", uniques_on(from, to, @shop_paths)},
      {"offer", uniques_like(from, to, "/offers/%", ["/offers/%/checkout"])},
      {"checkout", uniques_like(from, to, "/offers/%/checkout", [])},
      {"settled", settled_payments(from, to)},
      {"placed", placed_orders(from, to)}
    ]

    build_funnel(counts, max(elem(hd(counts), 1), 1), nil)
  end

  @doc "Where the visitors came from: `utm_source`, else the referrer host, else direct."
  @spec sources(DateTime.t(), DateTime.t(), pos_integer()) :: [map()]
  def sources(from, to, limit \\ 10) do
    PageView
    |> where([p], p.at >= ^from and p.at < ^to)
    |> select([p], {p.utm_source, p.referrer})
    |> Repo.all()
    |> Enum.map(fn {utm, referrer} -> source_label(utm, referrer) end)
    |> Enum.frequencies()
    |> Enum.map(fn {label, visits} -> %{source: label, visits: visits} end)
    |> Enum.sort_by(& &1.visits, :desc)
    |> Enum.take(limit)
  end

  @doc "Visits by device class, busiest first."
  @spec devices(DateTime.t(), DateTime.t()) :: [map()]
  def devices(from, to) do
    PageView
    |> where([p], p.at >= ^from and p.at < ^to)
    |> group_by([p], p.device_class)
    |> select([p], {p.device_class, count(p.id)})
    |> Repo.all()
    |> Enum.map(fn {class, visits} -> %{device: class || "other", visits: visits} end)
    |> Enum.sort_by(& &1.visits, :desc)
  end

  @doc "Offer ids by how many times they were opened, for the viewed-against-bought gap."
  @spec offer_views(DateTime.t(), DateTime.t()) :: %{integer() => non_neg_integer()}
  def offer_views(from, to) do
    PageView
    |> where([p], p.at >= ^from and p.at < ^to and like(p.path, "/offers/%"))
    |> select([p], p.path)
    |> Repo.all()
    |> Enum.flat_map(&offer_id_from_path/1)
    |> Enum.frequencies()
  end

  @doc "Offer ids by how many orders they sold in the window."
  @spec offers_bought(DateTime.t(), DateTime.t()) :: %{integer() => non_neg_integer()}
  def offers_bought(from, to) do
    Order
    |> join(:inner, [o], l in assoc(o, :lane))
    |> where([o, _l], o.inserted_at >= ^from and o.inserted_at < ^to)
    |> group_by([o, l], l.offer_id)
    |> select([o, l], {l.offer_id, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "The rollup rows for a range, oldest first."
  @spec daily(Date.t(), Date.t()) :: [AnalyticsDaily.t()]
  def daily(from_date, to_date) do
    AnalyticsDaily
    |> where([d], d.day >= ^from_date and d.day <= ^to_date)
    |> order_by([d], asc: d.day)
    |> Repo.all()
  end

  @doc """
  Rebuilds one day's rollup from the raw rows and upserts it (scope.md §11).

  Rebuildable by design: running it again for a past day rewrites the numbers.
  """
  @spec rollup_day(Date.t()) :: {:ok, AnalyticsDaily.t()} | {:error, Ecto.Changeset.t()}
  def rollup_day(date) do
    {from, to} = day_bounds(date)
    revenue = Profit.revenue_cents(from, to)

    cost =
      Profit.cogs_cents(from, to) + Profit.fees_cents(from, to) + Profit.sms_cents(from, to) +
        Profit.other_cents(date, date)

    attrs = %{
      day: date,
      visits: visits(from, to),
      uniques: uniques(from, to),
      signups: signups(from, to),
      orders: Profit.captured_count(from, to),
      revenue_cents: revenue,
      cost_cents: cost,
      profit_cents: revenue - cost
    }

    %AnalyticsDaily{}
    |> AnalyticsDaily.changeset(attrs)
    |> Repo.insert(on_conflict: {:replace, @rolled ++ [:updated_at]}, conflict_target: :day)
  end

  @doc "Rebuilds a whole range of days, oldest first. The backfill."
  @spec rebuild(Date.t(), Date.t()) :: non_neg_integer()
  def rebuild(from_date, to_date) do
    from_date
    |> Date.range(to_date)
    |> Enum.reduce(0, fn date, rebuilt ->
      case rollup_day(date) do
        {:ok, _day} -> rebuilt + 1
        _error -> rebuilt
      end
    end)
  end

  # -- internals ---------------------------------------------------------

  defp signups(from, to) do
    Repo.one(
      from u in User, where: u.inserted_at >= ^from and u.inserted_at < ^to, select: count(u.id)
    )
  end

  defp settled_payments(from, to) do
    Repo.one(
      from p in Payment,
        where:
          p.purpose == :order and p.status == :settled and p.inserted_at >= ^from and
            p.inserted_at < ^to,
        select: count(p.id)
    )
  end

  defp placed_orders(from, to) do
    Repo.one(
      from e in OrderEvent,
        where: e.to_state == "placed" and e.inserted_at >= ^from and e.inserted_at < ^to,
        select: count(e.id)
    )
  end

  defp uniques_on(from, to, paths) do
    Repo.one(
      from p in PageView,
        where: p.at >= ^from and p.at < ^to and p.path in ^paths and not is_nil(p.visitor_hash),
        select: count(p.visitor_hash, :distinct)
    )
  end

  defp uniques_like(from, to, like_path, exclude) do
    query =
      from p in PageView,
        where:
          p.at >= ^from and p.at < ^to and like(p.path, ^like_path) and
            not is_nil(p.visitor_hash)

    query =
      Enum.reduce(exclude, query, fn pattern, q -> where(q, [p], not like(p.path, ^pattern)) end)

    Repo.one(from p in query, select: count(p.visitor_hash, :distinct))
  end

  defp build_funnel([], _anchor, _previous), do: []

  defp build_funnel([{step, count} | rest], anchor, previous) do
    conversion = count / anchor
    drop = if previous && previous > 0, do: 1 - count / previous, else: nil

    [
      %{step: step, count: count, conversion: conversion, drop: drop}
      | build_funnel(rest, anchor, count)
    ]
  end

  defp source_label(utm, _referrer) when is_binary(utm) and utm != "", do: utm
  defp source_label(_utm, nil), do: "direct"

  defp source_label(_utm, referrer) do
    case URI.parse(referrer) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> "direct"
    end
  end

  defp offer_id_from_path(path) do
    case Regex.run(~r{^/offers/(\d+)$}, path) do
      [_, id] -> [String.to_integer(id)]
      _ -> []
    end
  end

  defp day_bounds(date) do
    {DateTime.new!(date, ~T[00:00:00]), DateTime.new!(Date.add(date, 1), ~T[00:00:00])}
  end

  defp datetime_bounds(from_date, to_date) do
    {DateTime.new!(from_date, ~T[00:00:00]), DateTime.new!(Date.add(to_date, 1), ~T[00:00:00])}
  end
end
