defmodule ViewNinjasWeb.AirtimeHistoryLiveTest do
  @moduledoc """
  A customer's airtime history: every top-up they have bought, newest first, with the
  money accounted for above it and a timeline they can open under each row.

  Two things this page is really for, and so two things this file really tests: a
  refund has to be *believed* (the row says the money went back, and the summary
  carries the figure outright), and one customer must never see another's airtime.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AirtimeFixtures

  alias ViewNinjas.Airtime
  alias ViewNinjas.Wallet

  # -- who gets in --------------------------------------------------------

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn(), ~p"/airtime/history")
  end

  # -- the empty page -----------------------------------------------------

  test "a customer who has never bought airtime is told so, and offered the buy screen", %{
    conn: conn
  } do
    conn = log_in_user(conn, funded_user(50_000))

    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    assert has_element?(lv, "#airtime-history-empty")
    assert has_element?(lv, "#airtime-history-buy")
    assert has_element?(lv, "#airtime-history-summary")
    # Zero means zero, not a blank space where a number should be.
    assert has_element?(lv, "#airtime-history-spent .vn-stat__value", "KSh 0")
    assert has_element?(lv, "#airtime-history-refunded-stat .vn-stat__value", "KSh 0")
    assert has_element?(lv, "#airtime-history-delivered-stat .vn-stat__value", "0")
    # Nothing to explain away yet.
    refute has_element?(lv, "#airtime-history-refunded")
    refute has_element?(lv, "#airtime-history-problems")
  end

  # -- the list -----------------------------------------------------------

  test "a delivered top-up is listed with its number, its amount and the rail's receipt", %{
    conn: conn
  } do
    user = funded_user(50_000)
    order = delivered_order!(%{user: user})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    assert has_element?(lv, "#airtime-history-#{order.id}")
    assert has_element?(lv, "#airtime-history-head-#{order.id}", "+254 712 345 678")
    assert has_element?(lv, "#airtime-history-head-#{order.id}", "KSh 100")
    assert has_element?(lv, "#airtime-history-#{order.id} .vn-state--delivered")
    assert has_element?(lv, "#airtime-history-net-#{order.id}", "Safaricom")

    # The pill speaks airtime's words. `OrderComponents` knows the social-order
    # vocabulary, so without airtime's own map the rail states print as the raw
    # lowercase atom next to a capitalised timeline.
    assert has_element?(lv, "#airtime-history-#{order.id} .vn-state--delivered", "Delivered")

    # The rail's own proof, so "it says delivered" is checkable later.
    assert has_element?(lv, "#airtime-history-receipt-#{order.id}", "R251")
    assert has_element?(lv, "#airtime-history-delivered-stat .vn-stat__value", "1")
    assert has_element?(lv, "#airtime-history-spent .vn-stat__value", "KSh 100")
  end

  test "the refund story: the money is back, the row says so, and the summary counts it", %{
    conn: conn
  } do
    user = funded_user(50_000)
    order = airtime_order_fixture(%{user: user, amount_cents: 10_000})
    {:ok, sending} = Airtime.mark_sending(order)

    {:ok, refunded} = Airtime.fail_and_refund(sending, "insufficient_float", "Float is empty")

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    assert refunded.state == :refunded
    # The money really is back, not merely claimed to be.
    assert Wallet.balance(user) == 50_000

    assert has_element?(lv, "#airtime-history-#{order.id}")
    assert has_element?(lv, "#airtime-history-#{order.id} .vn-state--refunded")

    # The one line on this page nobody should have to ask about.
    assert has_element?(lv, "#airtime-history-refund-#{order.id}", "went back to your wallet")
    assert has_element?(lv, "#airtime-history-refund-#{order.id}", "KSh 100")

    # What came back is carried outright, as a figure of its own.
    assert has_element?(lv, "#airtime-history-refunded-stat .vn-stat__value", "KSh 100")
    assert has_element?(lv, "#airtime-history-refunded", "Back in your wallet")
    assert has_element?(lv, "#airtime-history-refunded .vn-summary__total", "KSh 100")
  end

  # -- the filters --------------------------------------------------------

  test "every filter is offered and the active one is marked on", %{conn: conn} do
    conn = log_in_user(conn, funded_user(50_000))

    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    for name <- ~w(all delivered refunded failed going) do
      assert has_element?(lv, "#history-filter-#{name}"), "expected the #{name} chip"
    end

    assert has_element?(lv, "#history-filter-all.vn-chip--on")

    for name <- ~w(delivered refunded failed going) do
      refute has_element?(lv, "#history-filter-#{name}.vn-chip--on"), "expected #{name} to be off"
    end
  end

  test "the all filter shows every top-up", %{conn: conn} do
    user = funded_user(200_000)
    orders = every_state(user)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime/history?filter=all")

    for {_state, order} <- orders do
      assert has_element?(lv, "#airtime-history-#{order.id}"), "expected the #{order.id} row"
    end

    assert has_element?(lv, "#history-filter-all.vn-chip--on")
    refute has_element?(lv, "#airtime-history-empty")
  end

  test "the delivered filter shows only the delivered top-ups", %{conn: conn} do
    user = funded_user(200_000)
    orders = every_state(user)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime/history?filter=delivered")

    assert has_element?(lv, "#airtime-history-#{orders.delivered.id}")
    assert has_element?(lv, "#airtime-history-#{orders.delivered.id} .vn-state--delivered")

    for key <- [:paid, :sending, :submitted, :review, :failed, :refunded] do
      refute has_element?(lv, "#airtime-history-#{orders[key].id}"),
             "expected no row for the #{key} order"
    end

    assert has_element?(lv, "#history-filter-delivered.vn-chip--on")
  end

  test "the refunded filter shows only the top-ups whose money came back", %{conn: conn} do
    user = funded_user(200_000)
    orders = every_state(user)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime/history?filter=refunded")

    assert has_element?(lv, "#airtime-history-#{orders.refunded.id}")
    assert has_element?(lv, "#airtime-history-refund-#{orders.refunded.id}")

    for key <- [:paid, :sending, :submitted, :review, :failed, :delivered] do
      refute has_element?(lv, "#airtime-history-#{orders[key].id}"),
             "expected no row for the #{key} order"
    end

    assert has_element?(lv, "#history-filter-refunded.vn-chip--on")
  end

  test "the failed filter shows the top-ups that never arrived, and the ones being checked", %{
    conn: conn
  } do
    user = funded_user(200_000)
    orders = every_state(user)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime/history?filter=failed")

    # `needs_review` is in here deliberately: it is not airtime in their hand either.
    assert has_element?(lv, "#airtime-history-#{orders.failed.id}")
    assert has_element?(lv, "#airtime-history-#{orders.review.id}")

    for key <- [:paid, :sending, :submitted, :delivered, :refunded] do
      refute has_element?(lv, "#airtime-history-#{orders[key].id}"),
             "expected no row for the #{key} order"
    end

    assert has_element?(lv, "#history-filter-failed.vn-chip--on")
    assert has_element?(lv, "#airtime-history-problems")
  end

  test "the going filter shows the top-ups whose airtime is still owed", %{conn: conn} do
    user = funded_user(200_000)
    orders = every_state(user)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime/history?filter=going")

    # Money taken, airtime not delivered — including the ambiguous send, which is
    # still being looked after.
    for key <- [:paid, :sending, :submitted, :review] do
      assert has_element?(lv, "#airtime-history-#{orders[key].id}"),
             "expected the #{key} order to still be going"
    end

    for key <- [:delivered, :refunded, :failed] do
      refute has_element?(lv, "#airtime-history-#{orders[key].id}"),
             "expected no row for the #{key} order"
    end

    assert has_element?(lv, "#history-filter-going.vn-chip--on")
  end

  test "an unknown filter falls back to everything, not to an empty page", %{conn: conn} do
    user = funded_user(200_000)
    orders = every_state(user)
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime/history?filter=nonsense")

    for {_state, order} <- orders do
      assert has_element?(lv, "#airtime-history-#{order.id}"), "expected the #{order.id} row"
    end

    # The fallback names itself, so the customer is not left guessing which chip is on.
    assert has_element?(lv, "#history-filter-all.vn-chip--on")
    refute has_element?(lv, "#airtime-history-empty")
  end

  test "a filter with nothing in it says so instead of showing an unexplained blank", %{
    conn: conn
  } do
    user = funded_user(50_000)
    order = delivered_order!(%{user: user})
    conn = log_in_user(conn, user)

    {:ok, lv, _html} = live(conn, ~p"/airtime/history?filter=refunded")

    refute has_element?(lv, "#airtime-history-#{order.id}")
    # They do have airtime, it is just not in this group — so it is not the "never
    # bought any" message, and the way out is still there.
    assert has_element?(lv, "#airtime-history-empty", "Try another one")
    assert has_element?(lv, "#airtime-history-buy")
  end

  # -- the timeline -------------------------------------------------------

  test "a row's timeline opens and lists the states it actually passed through", %{conn: conn} do
    user = funded_user(50_000)
    order = delivered_order!(%{user: user})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    assert has_element?(lv, "#history-timeline-#{order.id}")
    refute has_element?(lv, "#airtime-timeline-#{order.id}")

    lv |> element("#history-timeline-#{order.id}") |> render_click()

    assert has_element?(lv, "#airtime-timeline-#{order.id}")

    events = Airtime.timeline(order)
    assert length(events) >= 2

    for event <- events do
      assert has_element?(lv, "#airtime-timeline-event-#{event.id}"),
             "expected timeline event #{event.id}"
    end
  end

  test "the timeline closes again when the same link is tapped", %{conn: conn} do
    user = funded_user(50_000)
    order = delivered_order!(%{user: user})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    lv |> element("#history-timeline-#{order.id}") |> render_click()
    assert has_element?(lv, "#airtime-timeline-#{order.id}")

    lv |> element("#history-timeline-#{order.id}") |> render_click()
    refute has_element?(lv, "#airtime-timeline-#{order.id}")
    # The row it was hanging off is untouched.
    assert has_element?(lv, "#airtime-history-#{order.id}")
  end

  # -- a failure is told honestly -----------------------------------------

  test "a failure carries the rail's own words, so nothing is left to guess", %{conn: conn} do
    user = funded_user(50_000)
    order = failed_order!(%{user: user})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    assert has_element?(lv, "#airtime-history-#{order.id}")
    assert has_element?(lv, "#airtime-history-failure-#{order.id}", "Float is empty")
    assert has_element?(lv, "#airtime-history-failure-#{order.id}.vn-muted")

    # And the page says, in as many words, that they are not out of pocket.
    assert has_element?(lv, "#airtime-history-problems", "not out of pocket")
    assert has_element?(lv, "#airtime-history-failed-stat .vn-stat__value", "1")
  end

  test "an order with nothing wrong with it carries no failure note", %{conn: conn} do
    user = funded_user(50_000)
    order = delivered_order!(%{user: user})

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    refute has_element?(lv, "#airtime-history-failure-#{order.id}")
    refute has_element?(lv, "#airtime-history-problems")
  end

  # -- one customer, their airtime only -----------------------------------

  test "a customer never sees another customer's top-up", %{conn: conn} do
    mine = funded_user(50_000)
    theirs = funded_user(50_000)

    my_order = delivered_order!(%{user: mine})
    their_order = refunded_order!(%{user: theirs})

    conn = log_in_user(conn, mine)
    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    assert has_element?(lv, "#airtime-history-#{my_order.id}")
    refute has_element?(lv, "#airtime-history-#{their_order.id}")
    # Their money is not in the totals either.
    assert has_element?(lv, "#airtime-history-refunded-stat .vn-stat__value", "KSh 0")
    refute has_element?(lv, "#airtime-history-refunded")
  end

  test "a customer's history lists only their own top-ups", %{conn: conn} do
    mine = funded_user(200_000)
    theirs = funded_user(50_000)

    my_orders = every_state(mine)
    _their_order = delivered_order!(%{user: theirs})

    conn = log_in_user(conn, mine)
    {:ok, lv, _html} = live(conn, ~p"/airtime/history")

    for {_state, order} <- my_orders do
      assert has_element?(lv, "#airtime-history-#{order.id}")
    end

    assert length(Airtime.list_for_user(mine, limit: 100)) == map_size(my_orders)
  end

  # -- helpers ------------------------------------------------------------

  # One customer holding one order in every state the filters care about, so a
  # filter test can say what it left out as well as what it kept in.
  defp every_state(user) do
    %{
      paid: airtime_order_fixture(%{user: user}),
      sending: sending_order!(%{user: user}),
      submitted: submitted_order!(%{user: user}),
      review: needs_review_order!(%{user: user}),
      failed: failed_order!(%{user: user}),
      delivered: delivered_order!(%{user: user}),
      refunded: refunded_order!(%{user: user})
    }
  end

  defp sending_order!(attrs) do
    order = airtime_order_fixture(attrs)
    {:ok, sending} = Airtime.mark_sending(order)
    sending
  end

  defp submitted_order!(attrs) do
    order = airtime_order_fixture(attrs)
    {:ok, sending} = Airtime.mark_sending(order)

    {:ok, submitted} =
      Airtime.mark_submitted(sending, %{id: "INSTAid_#{order.id}", status: :submitted})

    submitted
  end

  defp delivered_order!(attrs) do
    order = airtime_order_fixture(attrs)
    {:ok, sending} = Airtime.mark_sending(order)

    {:ok, submitted} =
      Airtime.mark_submitted(sending, %{id: "INSTAid_#{order.id}", status: :submitted})

    {:ok, delivered} =
      Airtime.mark_delivered(submitted, %{
        id: "INSTAid_#{order.id}",
        status: :submitted,
        receipt: "R251"
      })

    delivered
  end

  defp needs_review_order!(attrs) do
    order = airtime_order_fixture(attrs)
    {:ok, parked} = Airtime.mark_needs_review(order, "the send never resolved")
    parked
  end

  defp failed_order!(attrs) do
    order = airtime_order_fixture(attrs)
    {:ok, sending} = Airtime.mark_sending(order)
    {:ok, failed} = Airtime.mark_failed(sending, "insufficient_float", "Float is empty")
    failed
  end

  defp refunded_order!(attrs) do
    order = airtime_order_fixture(attrs)
    {:ok, sending} = Airtime.mark_sending(order)
    {:ok, refunded} = Airtime.fail_and_refund(sending, "insufficient_float", "Float is empty")
    refunded
  end
end
