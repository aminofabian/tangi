defmodule ViewNinjasWeb.Admin.AirtimeLiveTest do
  @moduledoc """
  The airtime back office (docs/instalipa-airtime.md §9, §10, §12): the float and the
  kill switch, the money still owed, the queue and the two ways a person resolves a
  row waiting on them. Super-admin only.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.AirtimeFixtures

  alias ViewNinjas.{Airtime, Settings, Wallet}

  setup do
    # The kill switch is a database row, so the sandbox transaction already rolls it
    # back when a case ends. This is the belt to that pair of braces: nothing a case
    # turns on is still on for the next one, whatever order they happen to run in.
    #
    # It lives here rather than in `on_exit` because ExUnit runs those callbacks in a
    # separate process, which an async (`shared: false`) sandbox does not allow to
    # touch the database.
    :ok = Settings.clear("instalipa_paused")
    :ok
  end

  # -- who gets in --------------------------------------------------------

  test "a signed out visitor is sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/airtime")
  end

  test "a signed in customer is bounced to the shop", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/", flash: _}}} = live(conn, ~p"/admin/airtime")
  end

  test "an ordinary admin is bounced too, the screen is super-admin only", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())
    assert {:error, {:redirect, %{to: "/", flash: _}}} = live(conn, ~p"/admin/airtime")
  end

  test "a super-admin gets in", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert has_element?(lv, "#airtime-float")
    assert has_element?(lv, "#airtime-owed")
  end

  # -- the float and the kill switch --------------------------------------

  test "the float says unknown when the rail has never reported one", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert Airtime.float() == nil
    assert has_element?(lv, "#airtime-float-unknown")
    refute has_element?(lv, "#airtime-float-now")
    # The floor is still stated, so an unknown float is not read as "no floor".
    assert has_element?(lv, "#airtime-floor")
    refute has_element?(lv, "#airtime-float-low")
  end

  test "the newest float the rail reported is stated, never estimated", %{conn: conn} do
    order = airtime_order_fixture()
    {:ok, sending} = Airtime.mark_sending(order)

    {:ok, _submitted} =
      Airtime.mark_submitted(sending, %{id: "FLOATREAD1", status: "Success", balance: 900_000})

    conn = log_in_user(conn, super_admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert Airtime.float().cents == 900_000
    assert has_element?(lv, "#airtime-float-now")
    refute has_element?(lv, "#airtime-float-unknown")
    # 900,000 is above the 500,000 floor, so selling is untouched.
    refute has_element?(lv, "#airtime-float-low")
    assert has_element?(lv, "#airtime-selling")
  end

  test "the kill switch stops selling and the button flips to resume", %{conn: conn} do
    customer = funded_user(50_000)
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    refute Airtime.paused?()
    assert has_element?(lv, "#airtime-pause")
    refute has_element?(lv, "#airtime-resume")

    lv |> element("#airtime-pause") |> render_click()

    assert Airtime.paused?()
    # The buy screen refuses before it takes any money.
    assert Airtime.buy(customer, %{amount_cents: 1_000, phones: ["0712345678"]}) ==
             {:error, :paused}

    assert has_element?(lv, "#airtime-resume")
    refute has_element?(lv, "#airtime-pause")
    assert has_element?(lv, "#airtime-paused-by-hand")
    assert has_element?(lv, "#flash-info")
  end

  test "resuming puts selling back on", %{conn: conn} do
    customer = funded_user(50_000)
    {:ok, _setting} = Settings.put("instalipa_paused", "true", nil)
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert Airtime.paused?()
    assert has_element?(lv, "#airtime-resume")
    refute has_element?(lv, "#airtime-pause")

    lv |> element("#airtime-resume") |> render_click()

    refute Airtime.paused?()

    assert {:ok, [_order]} =
             Airtime.buy(customer, %{amount_cents: 1_000, phones: ["0712345678"]})

    assert has_element?(lv, "#airtime-pause")
    refute has_element?(lv, "#airtime-resume")
    refute has_element?(lv, "#airtime-paused-by-hand")
  end

  # -- the money still owed ----------------------------------------------

  test "nothing is owed when the queue is clean", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert Airtime.outstanding_refund_cents() == 0
    assert has_element?(lv, "#airtime-owed-amount", "KSh 0")
    assert has_element?(lv, "#airtime-owed-clear")
    refute has_element?(lv, "#airtime-owed-open")
  end

  test "money parked in the queue is stated as still owed", %{conn: conn} do
    _review = needs_review_order!(%{user: funded_user(50_000)})
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert Airtime.outstanding_refund_cents() == 10_000
    assert has_element?(lv, "#airtime-owed-amount", "KSh 100")
    assert has_element?(lv, "#airtime-owed-open")
    # The failed filter is one tap away.
    assert has_element?(lv, "#airtime-owed-failed")
    refute has_element?(lv, "#airtime-owed-clear")
  end

  # -- the filters --------------------------------------------------------

  test "every filter chip is offered and the active one is marked on", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    for label <- ~w(needs_review failed open recent all) do
      assert has_element?(lv, "#filter-#{label}"), "expected the #{label} chip"
    end

    # needs_review is the default, so it is the one carrying the on state.
    assert has_element?(lv, "#filter-needs_review.vn-chip--on")

    for label <- ~w(failed open recent all) do
      refute has_element?(lv, "#filter-#{label}.vn-chip--on"), "expected #{label} to be off"
    end

    lv |> element("#filter-failed") |> render_click()

    assert has_element?(lv, "#filter-failed.vn-chip--on")
    refute has_element?(lv, "#filter-needs_review.vn-chip--on")
  end

  test "the failed filter shows the failed orders and not the ones being checked", %{conn: conn} do
    failed = failed_order!()
    review = needs_review_order!()
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime?state=failed")

    assert has_element?(lv, "#airtime-#{failed.id}")
    refute has_element?(lv, "#airtime-#{review.id}")
    assert has_element?(lv, "#filter-failed.vn-chip--on")
  end

  test "an unknown filter falls back to the queue waiting on a person", %{conn: conn} do
    review = needs_review_order!()
    failed = failed_order!()
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime?state=nonsense")

    assert has_element?(lv, "#airtime-#{review.id}")
    refute has_element?(lv, "#airtime-#{failed.id}")
    assert has_element?(lv, "#filter-needs_review.vn-chip--on")
  end

  test "the counters say where the orders are", %{conn: conn} do
    _review = needs_review_order!()
    _failed = failed_order!()
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime?state=all")

    assert has_element?(lv, "#count-needs_review .vn-stat__value", "1")
    assert has_element?(lv, "#count-failed .vn-stat__value", "1")
    assert has_element?(lv, "#count-refunded .vn-stat__value", "0")
  end

  # -- reconciling a row --------------------------------------------------

  test "a needs_review order is refunded from its row and the customer is made whole", %{
    conn: conn
  } do
    user = funded_user(50_000)
    order = needs_review_order!(%{user: user})
    original = Wallet.balance(user)

    assert order.state == :needs_review
    assert original == 40_000

    conn = log_in_user(conn, super_admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert has_element?(lv, "#airtime-refund-#{order.id}")
    assert has_element?(lv, "#airtime-form-#{order.id}")

    lv |> element("#airtime-refund-#{order.id}") |> render_click()

    assert Airtime.get_order(order.id).state == :refunded
    assert Wallet.balance(user) == 50_000
    assert has_element?(lv, "#flash-info")
    # It leaves the queue.
    refute has_element?(lv, "#airtime-#{order.id}")
  end

  test "a needs_review order is reconciled as delivered against the rail transaction id", %{
    conn: conn
  } do
    order = needs_review_order!()
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert has_element?(lv, "#airtime-form-#{order.id}")
    assert has_element?(lv, "#airtime-delivered-#{order.id}")

    lv
    |> form("#airtime-form-#{order.id}",
      airtime: %{order_id: order.id, instalipa_id: "INSTAid_9"}
    )
    |> render_submit()

    delivered = Airtime.get_order(order.id)
    assert delivered.state == :delivered
    assert delivered.instalipa_id == "INSTAid_9"
    assert has_element?(lv, "#flash-info")
    # It leaves the queue.
    refute has_element?(lv, "#airtime-#{order.id}")
  end

  test "a blank transaction id is refused and the order stays waiting on a person", %{
    conn: conn
  } do
    order = needs_review_order!()
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    lv
    |> form("#airtime-form-#{order.id}", airtime: %{order_id: order.id, instalipa_id: ""})
    |> render_submit()

    assert Airtime.get_order(order.id).state == :needs_review
    assert has_element?(lv, "#flash-error")
    # Still on the queue, still reconcilable.
    assert has_element?(lv, "#airtime-#{order.id}")
    assert has_element?(lv, "#airtime-form-#{order.id}")
  end

  test "a failed order is refunded from its row and the customer is made whole", %{conn: conn} do
    user = funded_user(50_000)
    order = failed_order!(%{user: user})
    original = Wallet.balance(user)

    assert order.state == :failed
    assert original == 40_000

    conn = log_in_user(conn, super_admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/airtime?state=failed")

    assert has_element?(lv, "#airtime-refund-failed-#{order.id}")
    # A failed row is not reconciled, only made whole.
    refute has_element?(lv, "#airtime-form-#{order.id}")

    lv |> element("#airtime-refund-failed-#{order.id}") |> render_click()

    assert Airtime.get_order(order.id).state == :refunded
    assert Wallet.balance(user) == 50_000
    assert has_element?(lv, "#flash-info")
    refute has_element?(lv, "#airtime-#{order.id}")
  end

  # -- the queue itself ----------------------------------------------------

  test "an empty queue says so", %{conn: conn} do
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert has_element?(lv, "#no-airtime")
  end

  test "every row carries its own timeline", %{conn: conn} do
    order = needs_review_order!()
    conn = log_in_user(conn, super_admin_fixture())

    {:ok, lv, _html} = live(conn, ~p"/admin/airtime")

    assert has_element?(lv, "#airtime-#{order.id}")
    assert has_element?(lv, "#timeline-#{order.id}")

    events = Airtime.timeline(order)
    assert length(events) >= 2

    for event <- events do
      assert has_element?(lv, "#airtime-event-#{event.id}"), "expected timeline event #{event.id}"
    end
  end

  # -- helpers ------------------------------------------------------------

  defp needs_review_order!(attrs \\ %{}) do
    order = airtime_order_fixture(attrs)
    {:ok, parked} = Airtime.mark_needs_review(order, "the send never resolved")
    parked
  end

  defp failed_order!(attrs \\ %{}) do
    order = airtime_order_fixture(attrs)
    {:ok, sending} = Airtime.mark_sending(order)
    {:ok, failed} = Airtime.mark_failed(sending, "invalid_phone", "the rail refused the number")
    failed
  end
end
