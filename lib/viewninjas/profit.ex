defmodule ViewNinjas.Profit do
  @moduledoc """
  The P&L (scope.md §10, §11; build-plan.md M10).

  Revenue is recognised when an order is captured, once — whether it was paid by a
  prompt or from the wallet — and a partial earns only on the delivered share,
  because the rest went back to the wallet. Against it sit the real costs: the
  supplier's USD `charge` per order converted at **that order's snapshot FX**
  (the estimate when no charge has landed yet), the reconciled Malipo fee, the SMS
  that carried each OTP, and the fixed costs.

  Everything is integer KES cents. Nothing here is stored — it is read from the
  rows the earlier milestones already write.
  """

  import Ecto.Query

  alias ViewNinjas.Insight.Cost
  alias ViewNinjas.Margin
  alias ViewNinjas.Orders.{Order, OrderEvent}
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Pricing
  alias ViewNinjas.Repo
  alias ViewNinjas.Sms.SmsMessage
  alias ViewNinjas.Wallet.LedgerEntry

  @periods [:day, :week, :month]
  @micros_per_cent 10_000

  @doc "The periods a P&L is reported for."
  @spec periods() :: [atom()]
  def periods, do: @periods

  @doc """
  The P&L for a period ending on `at` (default today), as a map of KES cents.

  Keys: `:revenue_cents`, `:cogs_cents`, `:gross_cents`, `:fees_cents`,
  `:sms_cents`, `:other_cents`, `:cost_cents` (all costs together) and
  `:net_cents`, plus `:from`/`:to` (datetimes) and `:from_date`/`:to_date`.
  """
  @spec for_period(atom(), Date.t()) :: map()
  def for_period(period \\ :month, at \\ Date.utc_today()) do
    {from_date, to_date} = bounds(period, at)
    {from, to} = datetime_bounds(from_date, to_date)

    revenue = revenue_cents(from, to)
    cogs = cogs_cents(from, to)
    fees = fees_cents(from, to)
    sms = sms_cents(from, to)
    other = other_cents(from_date, to_date)
    total_cost = cogs + fees + sms + other

    %{
      period: period,
      from: from,
      to: to,
      from_date: from_date,
      to_date: to_date,
      revenue_cents: revenue,
      cogs_cents: cogs,
      gross_cents: revenue - cogs,
      fees_cents: fees,
      sms_cents: sms,
      other_cents: other,
      cost_cents: total_cost,
      net_cents: revenue - total_cost
    }
  end

  @doc "Revenue for a window: captured retail less refunds credited inside it."
  @spec revenue_cents(DateTime.t(), DateTime.t()) :: integer()
  def revenue_cents(from, to) do
    captured_retail(from, to) - refunds_cents(from, to)
  end

  @doc "Cost of goods: each captured order's real charge, or its estimate, at its own FX."
  @spec cogs_cents(DateTime.t(), DateTime.t()) :: integer()
  def cogs_cents(from, to) do
    Order
    |> where([o], o.id in subquery(captured_order_ids(from, to)))
    |> preload(:fx_rate)
    |> Repo.all()
    |> Enum.map(&cogs_kes_cents/1)
    |> Enum.sum()
  end

  @doc "The reconciled Malipo fees on the payments in the window."
  @spec fees_cents(DateTime.t(), DateTime.t()) :: integer()
  def fees_cents(from, to) do
    Repo.one(
      from p in Payment,
        where: p.inserted_at >= ^from and p.inserted_at < ^to and not is_nil(p.fee_cents),
        select: coalesce(sum(p.fee_cents), 0)
    )
  end

  @doc "The SMS that carried the period's OTPs and notices, in KES cents."
  @spec sms_cents(DateTime.t(), DateTime.t()) :: integer()
  def sms_cents(from, to) do
    micros =
      Repo.one(
        from m in SmsMessage,
          where: m.inserted_at >= ^from and m.inserted_at < ^to,
          select: coalesce(sum(coalesce(m.cost_micros, 0)), 0)
      )

    div(micros, @micros_per_cent)
  end

  @doc "The fixed and one-off costs recorded for a period, in KES cents."
  @spec other_cents(Date.t(), Date.t()) :: integer()
  def other_cents(from_date, to_date) do
    Repo.one(
      from c in Cost,
        where: c.incurred_on >= ^from_date and c.incurred_on <= ^to_date,
        select: coalesce(sum(c.amount_cents), 0)
    )
  end

  @doc """
  The cost of one order in KES cents: the panel's real charge at the order's
  snapshot FX, or the estimate we priced with when no charge has landed yet.
  """
  @spec cogs_kes_cents(Order.t()) :: integer()
  def cogs_kes_cents(%Order{charge_usd_micros: charge} = order) when is_integer(charge) do
    Margin.cost_kes_cents(order) || 0
  end

  def cogs_kes_cents(%Order{cost_usd_micros: nil}), do: 0

  def cogs_kes_cents(%Order{cost_usd_micros: usd, fx_rate: %{rate_ppm: fx}})
      when is_integer(usd) and is_integer(fx) and fx > 0 do
    params = %{Pricing.Params.defaults() | fx_ppm: fx}
    usd |> Pricing.cost_kes_ppm(params) |> div(@micros_per_cent)
  end

  def cogs_kes_cents(%Order{}), do: 0

  @doc """
  Break-even for a period: how many orders at the period's realised gross margin
  per order cover the fixed costs.

  `margin_per_order_cents` and `orders_needed` are `nil` when there is no margin
  to divide by.
  """
  @spec break_even(atom(), Date.t()) :: map()
  def break_even(period \\ :month, at \\ Date.utc_today()) do
    p = for_period(period, at)
    fixed = p.other_cents
    orders = captured_count(p.from, p.to)

    margin_per_order = if orders > 0, do: div(p.gross_cents, orders), else: nil

    needed =
      if is_integer(margin_per_order) and margin_per_order > 0,
        do: div(fixed + margin_per_order - 1, margin_per_order),
        else: nil

    %{fixed_cents: fixed, margin_per_order_cents: margin_per_order, orders_needed: needed}
  end

  @doc "How many orders were captured in a window."
  @spec captured_count(DateTime.t(), DateTime.t()) :: integer()
  def captured_count(from, to) do
    Repo.one(
      from e in OrderEvent,
        where: e.to_state == "paid" and e.inserted_at >= ^from and e.inserted_at < ^to,
        select: count(e.order_id, :distinct)
    )
  end

  # -- internals ---------------------------------------------------------

  @doc false
  # The orders whose money was taken inside the window.
  def captured_order_ids(from, to) do
    from e in OrderEvent,
      where: e.to_state == "paid" and e.inserted_at >= ^from and e.inserted_at < ^to,
      select: e.order_id,
      distinct: true
  end

  defp captured_retail(from, to) do
    Repo.one(
      from o in Order,
        where: o.id in subquery(captured_order_ids(from, to)),
        select: coalesce(sum(o.retail_cents), 0)
    )
  end

  defp refunds_cents(from, to) do
    Repo.one(
      from e in LedgerEntry,
        where: e.reason == :refund and e.inserted_at >= ^from and e.inserted_at < ^to,
        select: coalesce(sum(e.amount_cents), 0)
    )
  end

  @doc false
  def bounds(:day, at), do: {at, at}

  def bounds(:week, at),
    do: {Date.add(at, 1 - Date.day_of_week(at)), Date.add(at, 7 - Date.day_of_week(at))}

  def bounds(:month, at) do
    first = %{at | day: 1}
    {first, Date.end_of_month(first)}
  end

  defp datetime_bounds(from_date, to_date) do
    {DateTime.new!(from_date, ~T[00:00:00]), DateTime.new!(Date.add(to_date, 1), ~T[00:00:00])}
  end
end
