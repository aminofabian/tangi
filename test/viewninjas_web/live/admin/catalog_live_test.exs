defmodule ViewNinjasWeb.Admin.CatalogLiveTest do
  @moduledoc """
  The catalog workspace (build-plan.md M4): the role gate, the inventory filters,
  and the pin/publish path from an ingested row to a live lane.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.CatalogFixtures

  alias ViewNinjas.Catalog
  alias ViewNinjas.Pricing

  test "a signed out visitor is sent to log in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/admin/catalog")
  end

  test "a signed in customer is bounced to the shop", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/catalog")
  end

  test "an admin sees the ingested inventory", %{conn: conn} do
    service = service_fixture(%{name: "IG followers - refill"})
    conn = log_in_user(conn, admin_fixture())

    {:ok, lv, html} = live(conn, ~p"/admin/catalog")

    assert html =~ "IG followers - refill"
    assert has_element?(lv, "#service-#{service.id}")
    assert has_element?(lv, "#select-#{service.id}")
    assert has_element?(lv, "#shortlist-#{service.id}")
  end

  test "an admin creates an offer", %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    lv
    |> form("#offer-form", offer: %{platform: "instagram", outcome: "followers", title: "IG"})
    |> render_submit()

    assert [offer] = Catalog.list_offers()
    assert offer.title == "IG"
    assert has_element?(lv, "#offer-#{offer.id}")
  end

  test "filtering the inventory narrows the rows", %{conn: conn} do
    service_fixture(%{name: "IG followers", external_id: "111"})
    service_fixture(%{name: "TikTok likes", external_id: "222"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    html = lv |> form("#filters", filters: %{q: "TikTok"}) |> render_change()

    assert html =~ "TikTok likes"
    refute html =~ "IG followers"
  end

  test "the bounds filter hides rows that cannot sell 1,000", %{conn: conn} do
    sells = service_fixture(%{external_id: "1", min: 100, max: 10_000, name: "Sells 1000"})
    service_fixture(%{external_id: "2", min: 5_000, max: 50_000, name: "Big only"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    html = lv |> form("#filters", filters: %{bounds: "true"}) |> render_change()

    assert html =~ "Sells 1000"
    refute html =~ "Big only"
    assert has_element?(lv, "#service-#{sells.id}")
  end

  test "shortlisting a row changes nothing a buyer sees", %{conn: conn} do
    service = service_fixture()
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    html = lv |> element("#shortlist-#{service.id}") |> render_click()

    assert Catalog.get_service(service.id).shortlisted_at
    assert html =~ "Shortlisted."
    assert has_element?(lv, "#service-#{service.id}.vn-catalog-row--picked")
    assert has_element?(lv, "#shortlist-#{service.id}.vn-star--on")
  end

  test "the filters fold away, and the summary counts what is on", %{conn: conn} do
    service_fixture(%{name: "IG followers", external_id: "111"})
    service_fixture(%{name: "TikTok likes", external_id: "222"})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, html} = live(conn, ~p"/admin/catalog")

    assert has_element?(lv, "#filters-panel")
    # The form is still in the DOM (just folded), so the filters keep working.
    assert has_element?(lv, "#filters")
    assert html =~ "none — search, panel, category"
    refute has_element?(lv, "#filters-clear")

    html = lv |> form("#filters", filters: %{q: "TikTok"}) |> render_change()

    assert html =~ "1 on"
    assert has_element?(lv, "#filters-clear")

    lv |> element("#filters-clear") |> render_click()

    html = render(lv)
    assert html =~ "none — search, panel, category"
    assert html =~ "IG followers"
    refute has_element?(lv, "#filters-clear")
  end

  test "selecting a row opens the placement form with suggestions", %{conn: conn} do
    cheaper = service_fixture(%{external_id: "1", rate_micros: 100_000, refill: true})
    subject = service_fixture(%{external_id: "9", name: "IG followers", rate_micros: 900_000})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    refute has_element?(lv, "#lane-form")

    lv |> element("#select-#{subject.id}") |> render_click()

    assert has_element?(lv, "#placement")
    assert has_element?(lv, "#lane-form")
    assert has_element?(lv, "#grade-cheap", "Lowest")
    assert has_element?(lv, "#grade-moderate", "Middle")
    assert has_element?(lv, "#grade-quality", "Expensive")
    assert has_element?(lv, "#suggest-#{cheaper.id}")
    assert has_element?(lv, "#service-#{subject.id}")

    lv |> element("#placement-close") |> render_click()

    refute has_element?(lv, "#placement")
    assert has_element?(lv, "#service-#{subject.id}")
  end

  test "placing a row puts it on the shop at the converted selling price", %{conn: conn} do
    service =
      service_fixture(%{
        name: "Instagram Views [Max: 60K]",
        category: "Instagram",
        rate_micros: 1_200,
        external_id: "339"
      })

    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, html} = live(conn, ~p"/admin/catalog")

    assert html =~ "KSh 0.37"
    refute html =~ ">KSh 0<"

    lv |> element("#select-#{service.id}") |> render_click()

    assert has_element?(lv, "#grade-pick")
    # Opening the drawer places nothing; the first free grade is armed by default.
    assert has_element?(lv, "#grade-cheap.vn-grade-card--on")
    assert Catalog.list_market_offers() == []

    # Choosing a shelf only arms the confirm — nothing lands until it is submitted.
    lv |> element("#grade-cheap") |> render_click()
    assert Catalog.list_market_offers() == []

    html = lv |> form("#lane-form") |> render_submit()

    assert html =~ "On the shop as Cheap"
    assert html =~ "Instagram views"
    assert html =~ "KSh 0.37"

    assert [offer] = Catalog.list_market_offers()
    assert offer.title == "Instagram views"
    assert offer.published
    assert [%{published: true, grade: :cheap}] = offer.lanes
    assert has_element?(lv, "#placed-#{service.id}-cheap", "Cheap")
    assert has_element?(lv, "#grade-cheap.vn-grade-card--on")
  end

  test "the placement card shows the conversion and the margin behind the price", %{conn: conn} do
    service = service_fixture(%{name: "IG followers", rate_micros: 900_000})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    html = lv |> element("#select-#{service.id}") |> render_click()

    assert has_element?(lv, "#placement-price")
    # Wholesale -> FX -> landed -> selling, with the knobs in force on screen.
    assert html =~ "0.9 USD / 1,000"
    assert html =~ "KSh 129.40 per USD"
    assert html =~ "KSh 120"
    assert html =~ "KSh 276"
    assert html =~ "130% margin"
    assert html =~ "3% float"
  end

  test "pinning a grade publishes a lane a buyer will eventually see", %{conn: conn} do
    service = service_fixture(%{rate_micros: 900_000})
    offer = offer_fixture()
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    lv |> element("#select-#{service.id}") |> render_click()
    lv |> element("#grade-quality") |> render_click()

    lv
    |> form("#lane-form",
      lane: %{
        offer_id: offer.id,
        grade: "quality",
        manual_kes: "",
        published: "true"
      }
    )
    |> render_submit()

    assert [lane] = Catalog.get_offer!(offer.id).lanes
    assert lane.grade == :quality
    assert lane.published
    assert has_element?(lv, "#lane-#{lane.id}")
  end

  test "a lane publishes and unpublishes from the offer card", %{conn: conn} do
    lane = lane_fixture(%{grade: :cheap})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    lv |> element("#lane-publish-#{lane.id}") |> render_click()
    assert Catalog.get_lane!(lane.id).published

    lv |> element("#lane-publish-#{lane.id}") |> render_click()
    refute Catalog.get_lane!(lane.id).published
  end

  test "unpinning a lane removes it from the offer", %{conn: conn} do
    lane = lane_fixture()
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/catalog")

    assert has_element?(lv, "#lane-#{lane.id}")

    lv |> element("#lane-unpin-#{lane.id}") |> render_click()

    assert Catalog.get_lane(lane.id) == nil
    refute has_element?(lv, "#lane-#{lane.id}")
  end

  test "a change to the knobs re-quotes the inventory", %{conn: conn} do
    service_fixture(%{rate_micros: 900_000})
    conn = log_in_user(conn, admin_fixture())
    {:ok, lv, html} = live(conn, ~p"/admin/catalog")

    assert html =~ "KSh 276"

    {:ok, _version} = Pricing.append_settings(%{margin_bps: 15_000, buffer_bps: 300}, nil)
    _ = :sys.get_state(lv.pid)

    assert render(lv) =~ "KSh 300"
  end
end
