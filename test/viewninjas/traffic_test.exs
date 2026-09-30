defmodule ViewNinjas.TrafficTest do
  @moduledoc """
  First-party traffic (build-plan.md M10, scope.md §11): the funnel, the sources,
  and the rebuildable daily rollup over the `page_views` from M6.
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.OrdersFixtures

  alias ViewNinjas.{Insight, Payments, Repo, Traffic}
  alias ViewNinjas.Insight.AnalyticsDaily

  test "visits and uniques over a window" do
    view("/", "1.1.1.1")
    view("/", "1.1.1.1")
    view("/shop", "2.2.2.2")

    {from, to} = today()

    assert Traffic.visits(from, to) == 3
    assert Traffic.uniques(from, to) == 2
  end

  test "the funnel counts visitors down to money and orders" do
    view("/", "1.1.1.1")
    view("/", "2.2.2.2")
    view("/offers/1", "1.1.1.1")
    view("/offers/1/checkout", "1.1.1.1")

    order = paid_order_with_lane_fixture()
    payment = payment_fixture(%{order: order})
    {:ok, sent} = Payments.mark_pending(payment, "malipo-f")
    {:ok, _} = Payments.settle(sent, "RCPTF")
    _placed = supplier_order_fixture()

    {from, to} = today()
    funnel = Traffic.funnel(from, to)

    counts = Map.new(funnel, &{&1.step, &1.count})
    assert counts["shop"] == 2
    assert counts["offer"] == 1
    assert counts["checkout"] == 1
    assert counts["settled"] == 1
    assert counts["placed"] >= 1

    # Conversion is against the first step; the drop is against the previous.
    shop = Enum.find(funnel, &(&1.step == "shop"))
    assert shop.conversion == 1.0
    assert shop.drop == nil

    offer = Enum.find(funnel, &(&1.step == "offer"))
    assert offer.conversion == 0.5
    assert offer.drop == 0.5
  end

  test "sources prefer utm_source, then the referrer host" do
    view("/", "1.1.1.1", %{utm_source: "whatsapp"})
    view("/", "2.2.2.2", %{referrer: "https://twitter.com/x"})
    view("/", "3.3.3.3")

    {from, to} = today()
    sources = Traffic.sources(from, to) |> Map.new(&{&1.source, &1.visits})

    assert sources["whatsapp"] == 1
    assert sources["twitter.com"] == 1
    assert sources["direct"] == 1
  end

  test "offer views are counted by offer id" do
    view("/offers/7", "1.1.1.1")
    view("/offers/7", "2.2.2.2")
    view("/offers/8", "1.1.1.1")

    {from, to} = today()
    views = Traffic.offer_views(from, to)

    assert views[7] == 2
    assert views[8] == 1
  end

  describe "rollup_day/1" do
    test "writes one row per day, and rewrites it on a rebuild" do
      order = paid_order_with_lane_fixture()
      view("/", "1.1.1.1")
      today = Date.utc_today()

      {:ok, day} = Traffic.rollup_day(today)
      assert day.visits == 1
      assert day.orders == 1
      assert day.revenue_cents == order.retail_cents
      assert day.profit_cents == day.revenue_cents - day.cost_cents

      # A rebuild sees the new visit and Rewrites the same row.
      view("/shop", "2.2.2.2")
      {:ok, rebuilt} = Traffic.rollup_day(today)

      assert rebuilt.id == day.id
      assert rebuilt.visits == 2
      assert Repo.aggregate(AnalyticsDaily, :count) == 1
    end
  end

  defp view(path, ip, opts \\ %{}) do
    Insight.record_page_view(%{
      path: path,
      at: DateTime.utc_now(:second),
      ip: ip,
      user_agent: Map.get(opts, :user_agent, "Mozilla/5.0 (iPhone)"),
      referrer: Map.get(opts, :referrer),
      utm: %{"utm_source" => Map.get(opts, :utm_source)}
    })
  end

  defp today do
    {DateTime.new!(Date.utc_today(), ~T[00:00:00]),
     DateTime.new!(Date.add(Date.utc_today(), 1), ~T[00:00:00])}
  end
end
