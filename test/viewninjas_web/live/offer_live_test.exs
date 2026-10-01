defmodule ViewNinjasWeb.OfferLiveTest do
  @moduledoc """
  The offer page (build-plan.md M6): three grades, a link, a quantity, and a live
  total that is a promise, not a charge.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.CatalogFixtures

  alias ViewNinjas.Catalog
  alias ViewNinjas.Insight

  defp three_grade_offer do
    offer = offer_fixture(%{title: "Instagram followers", published: true})

    for {grade, rate, external_id} <- [
          {:cheap, 900_000, "1"},
          {:moderate, 2_000_000, "2"},
          {:quality, 3_000_000, "3"}
        ] do
      service = service_fixture(%{rate_micros: rate, external_id: external_id})

      {:ok, _lane} =
        Catalog.pin_lane(%{
          offer_id: offer.id,
          grade: grade,
          supplier_service_id: service.id,
          published: true
        })
    end

    Catalog.get_offer!(offer.id)
  end

  test "shows the three grades with their bounds and refill", %{conn: conn} do
    offer = three_grade_offer()
    {:ok, view, _html} = live(conn, ~p"/offers/#{offer.id}")

    assert has_element?(view, "#journey")
    assert has_element?(view, "#journey-now")
    refute render(view) =~ "next release"
    assert has_element?(view, "#pick-cheap")
    assert has_element?(view, "#pick-moderate")
    assert has_element?(view, "#pick-quality")
    assert render(view) =~ "100–10000"
    assert render(view) =~ "Refill"
  end

  test "the total updates live as the quantity changes", %{conn: conn} do
    offer = three_grade_offer()
    {:ok, view, _html} = live(conn, ~p"/offers/#{offer.id}")

    # 1,000 units at 0.90 USD/1k is the §7 example: KSh 276.
    assert has_element?(view, "#total", "KSh 276")

    html = view |> form("#order-form") |> render_change(order: %{link: "", quantity: "2000"})
    assert html =~ "KSh 552"
  end

  test "switching grade re-quotes", %{conn: conn} do
    offer = three_grade_offer()
    {:ok, view, _html} = live(conn, ~p"/offers/#{offer.id}")

    quality = Enum.find(offer.lanes, &(&1.grade == :quality))

    expected =
      ViewNinjas.Pricing.format_kes_cents(
        ViewNinjas.Catalog.Lane.retail_kes_cents(quality, ViewNinjas.Pricing.current())
      )

    html = view |> element("#pick-quality") |> render_click()

    assert html =~ expected
    assert has_element?(view, "#pick-quality[aria-pressed='true']")
  end

  test "a quantity outside the lane's bounds is refused, with the bound", %{conn: conn} do
    offer = three_grade_offer()
    {:ok, view, _html} = live(conn, ~p"/offers/#{offer.id}")

    html = view |> form("#order-form") |> render_change(order: %{link: "", quantity: "50"})

    assert html =~ "This one starts at 100"
    assert has_element?(view, "#checkout[disabled]")
  end

  test "a link that is not https is refused on continue", %{conn: conn} do
    offer = three_grade_offer()
    {:ok, view, _html} = live(conn, ~p"/offers/#{offer.id}")

    html =
      view
      |> form("#order-form", order: %{link: "http://instagram.com/x", quantity: "1000"})
      |> render_submit()

    assert html =~ "https"
    refute Enum.any?(Insight.list_page_views(), &(&1.path =~ "checkout"))
  end

  test "a guest continuing is sent to sign up, and the funnel step is recorded", %{conn: conn} do
    offer = three_grade_offer()
    {:ok, view, _html} = live(conn, ~p"/offers/#{offer.id}")

    result =
      view
      |> form("#order-form", order: %{link: "https://instagram.com/viewninjas", quantity: "1000"})
      |> render_submit()

    assert {:error, {:live_redirect, %{to: "/users/register"}}} = result
    assert Enum.any?(Insight.list_page_views(), &(&1.path == "/offers/#{offer.id}/checkout"))
  end

  test "a signed-in buyer continuing creates the order and goes to checkout", %{conn: conn} do
    offer = three_grade_offer()
    user = verified_user_fixture()
    conn = log_in_user(conn, user)
    {:ok, view, _html} = live(conn, ~p"/offers/#{offer.id}")

    result =
      view
      |> form("#order-form", order: %{link: "https://instagram.com/viewninjas", quantity: "1000"})
      |> render_submit()

    order = ViewNinjas.Orders.list_orders(user) |> List.first()
    assert order.state == :awaiting_payment
    assert order.retail_cents == ViewNinjas.Pricing.retail_kes_cents(900_000)

    checkout = "/checkout/#{order.id}"
    assert {:error, {:live_redirect, %{to: ^checkout}}} = result
  end

  test "the offer page records a page view", %{conn: conn} do
    offer = three_grade_offer()
    {:ok, _view, _html} = live(conn, ~p"/offers/#{offer.id}")

    assert Enum.any?(Insight.list_page_views(), &(&1.path == "/offers/#{offer.id}"))
  end

  test "an offer that is not for sale goes back to the shop", %{conn: conn} do
    offer = offer_fixture(%{title: "Draft", published: false})
    lane_fixture(%{offer: offer})

    assert {:error, {:live_redirect, %{to: "/shop"}}} = live(conn, ~p"/offers/#{offer.id}")
  end

  test "an unknown id goes back to the shop", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/shop"}}} = live(conn, ~p"/offers/999999")
  end

  test "a high-demand grade says so and refuses checkout, without naming a supplier", %{
    conn: conn
  } do
    offer = three_grade_offer()
    cheap = Enum.find(offer.lanes, &(&1.grade == :cheap))
    {:ok, _} = ViewNinjas.Suppliers.pause(cheap.supplier_service.supplier, "under the float")

    {:ok, view, html} = live(conn, ~p"/offers/#{offer.id}")

    assert has_element?(view, "#grade-paused")
    assert html =~ "In demand"
    refute html =~ "supplier"

    html =
      view
      |> form("#order-form", order: %{link: "https://instagram.com/x", quantity: "1000"})
      |> render_submit()

    assert html =~ "high demand"
    assert ViewNinjas.Repo.aggregate(ViewNinjas.Orders.Order, :count) == 0
  end
end
