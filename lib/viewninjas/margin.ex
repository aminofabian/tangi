defmodule ViewNinjas.Margin do
  @moduledoc """
  Realised margin: retail in KES against the panel's real USD charge (scope.md
  §10; build-plan.md M9).

  The status job writes the supplier's actual `charge` onto every order. Convert
  it at the FX rate **snapshotted on that order** — never today's rate — and the
  difference from the captured retail is the gross profit for that order. Summed
  by lane and by week, this is the per-order detail behind M10's headline.

  An order with no charge yet, or no snapshot rate to convert one, has no
  realised margin and is left out.
  """

  import Ecto.Query

  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Pricing
  alias ViewNinjas.Repo

  @charged ~w(placed in_progress partial completed canceled)a

  @doc "One row per charged order, newest first: retail, cost and profit in KES cents."
  @spec by_order(keyword()) :: [map()]
  def by_order(opts \\ []) do
    Order
    |> where([o], o.state in ^@charged and not is_nil(o.charge_usd_micros))
    |> where([o], not is_nil(o.fx_rate_id))
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(^Keyword.get(opts, :limit, 200))
    |> preload(:fx_rate)
    |> Repo.all()
    |> Enum.map(&row/1)
  end

  @doc "The same margin summed per lane, best first."
  @spec by_lane() :: [map()]
  def by_lane do
    by_order(limit: 1_000)
    |> Enum.group_by(& &1.lane_id)
    |> Enum.map(fn {lane_id, rows} -> Map.put(summarise(rows), :lane_id, lane_id) end)
    |> Enum.sort_by(& &1.profit_cents, :desc)
  end

  @doc "The same margin summed per ISO week, newest first."
  @spec by_week() :: [map()]
  def by_week do
    by_order(limit: 1_000)
    |> Enum.group_by(&week_of(&1.at))
    |> Enum.map(fn {week, rows} -> Map.put(summarise(rows), :week, week) end)
    |> Enum.sort_by(& &1.week, :desc)
  end

  @doc "The cost in KES cents of an order's real USD charge, at its snapshot FX."
  @spec cost_kes_cents(Order.t()) :: non_neg_integer() | nil
  def cost_kes_cents(%Order{charge_usd_micros: nil}), do: nil

  def cost_kes_cents(%Order{charge_usd_micros: usd, fx_rate: %{rate_ppm: fx}})
      when is_integer(usd) and is_integer(fx) and fx > 0 do
    params = %{Pricing.Params.defaults() | fx_ppm: fx}
    usd |> Pricing.cost_kes_ppm(params) |> div(10_000)
  end

  def cost_kes_cents(%Order{}), do: nil

  defp row(%Order{} = order) do
    cost = cost_kes_cents(order)

    %{
      order: order,
      order_id: order.id,
      lane_id: order.lane_id,
      at: order.inserted_at,
      retail_cents: order.retail_cents,
      cost_cents: cost,
      profit_cents: profit(order.retail_cents, cost)
    }
  end

  defp profit(_retail, nil), do: nil
  defp profit(retail, cost), do: retail - cost

  defp summarise(rows) do
    %{
      orders: length(rows),
      retail_cents: sum(rows, :retail_cents),
      cost_cents: sum(rows, :cost_cents),
      profit_cents: sum(rows, :profit_cents)
    }
  end

  defp sum(rows, field) do
    rows
    |> Enum.map(&Map.get(&1, field))
    |> Enum.reject(&is_nil/1)
    |> Enum.sum()
  end

  defp week_of(%DateTime{} = at) do
    {year, week} = :calendar.iso_week_number(Date.to_erl(DateTime.to_date(at)))
    "#{year}-W#{String.pad_leading(Integer.to_string(week), 2, "0")}"
  end

  defp week_of(_at), do: nil
end
