defmodule ViewNinjasWeb.HomeLiveTest do
  @moduledoc """
  The home surface (build-plan.md M6): the market at `/` for anyone signed out,
  the buyer dashboard for anyone signed in, and the same market at `/shop`.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import ViewNinjas.AccountsFixtures
  import ViewNinjas.CatalogFixtures

  alias ViewNinjas.Insight

  test "the shell carries the brand, main and the four tabs", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "nav.vn-tabbar a[aria-current='page'][href='/']")
    assert has_element?(view, "main.vn-main")

    assert has_element?(
             view,
             "header.vn-header a.vn-brand img.vn-brand__logo[src='/images/logo.png']"
           )

    for href <- ["/", "/shop", "/orders", "/account"] do
      assert has_element?(view, "nav.vn-tabbar a[href='#{href}']")
    end
  end

  test "signed out, the homepage is the market with the three grades", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#legend-cheap")
    assert has_element?(view, "#legend-moderate")
    assert has_element?(view, "#legend-quality")
    assert has_element?(view, "a[href='/users/register']")
  end

  test "the market shows a published offer with a real from-price", %{conn: conn} do
    offer = published_offer_fixture(%{title: "Instagram followers", platform: "instagram"})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#offer-#{offer.id}")
    # The tile is the link now, rather than a row wrapping one.
    assert has_element?(view, "#offer-#{offer.id}[href='/offers/#{offer.id}']")
    # The default §7 rate: 0.90 USD/1k -> KSh 276.
    assert render(view) =~ "KSh 276"
  end

  test "an offer with no published lane is not shown at all", %{conn: conn} do
    offer = offer_fixture(%{title: "Draft offer", published: true})
    lane = lane_fixture(%{offer: offer})

    {:ok, view, _html} = live(conn, ~p"/")

    refute has_element?(view, "#offer-#{offer.id}")
    refute render(view) =~ "Draft offer"
    assert lane.id
  end

  test "two platforms, and a chip narrows the market", %{conn: conn} do
    ig =
      published_offer_fixture(%{
        title: "IG followers",
        platform: "instagram",
        outcome: "followers"
      })

    tt =
      published_offer_fixture(%{
        title: "TikTok likes",
        platform: "tiktok",
        outcome: "likes",
        service_attrs: %{external_id: "777"}
      })

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#chip-instagram")
    assert has_element?(view, "#chip-tiktok")

    html = view |> element("#chip-tiktok") |> render_click()

    # Grouped by platform, and the tile names the outcome — the group header
    # already says TikTok, so repeating it in every tile is wasted space.
    assert html =~ "Likes"
    refute has_element?(view, "#offer-#{ig.id}")
    assert has_element?(view, "#offer-#{tt.id}")
    # With one platform chosen there is no reason to repeat its name as a header.
    refute has_element?(view, "#group-tiktok .vn-group__name")

    html = view |> element("#chip-all") |> render_click()
    assert has_element?(view, "#group-instagram .vn-group__name")
    assert html =~ "Followers"
  end

  test "a target separates two offers that would otherwise be the same row", %{conn: conn} do
    page =
      published_offer_fixture(%{
        title: "Facebook page likes",
        platform: "facebook",
        outcome: "likes",
        target: "page"
      })

    post =
      published_offer_fixture(%{
        title: "Facebook post likes",
        platform: "facebook",
        outcome: "likes",
        target: "post",
        service_attrs: %{external_id: "778"}
      })

    {:ok, view, _html} = live(conn, ~p"/")

    # Both are on the market at once, each naming what it actually is.
    assert has_element?(view, "#offer-#{page.id}")
    assert has_element?(view, "#offer-#{post.id}")
    assert render(view) =~ "Page Likes"
    assert render(view) =~ "Post Likes"

    # And the platform is a heading above them, not repeated on every tile.
    assert has_element?(view, "#group-facebook")
  end

  test "signed in, the homepage is the dashboard with the stubbed strip", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#wallet-card")
    assert has_element?(view, "#stat-wallet")
    assert has_element?(view, "#stat-delivered")
    assert has_element?(view, "#orders-card")
    assert has_element?(view, "nav.vn-tabbar a[aria-current='page'][href='/']")
    refute has_element?(view, "#legend-cheap")
  end

  test "/shop is the market even when signed in", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    published_offer_fixture(%{title: "Instagram followers"})

    {:ok, view, _html} = live(conn, ~p"/shop")

    assert has_element?(view, "nav.vn-tabbar a[aria-current='page'][href='/shop']")
    assert render(view) =~ "Instagram followers"
    refute has_element?(view, "#wallet-card")
  end

  test "/shop leads with both product lines, so airtime is not buried", %{conn: conn} do
    published_offer_fixture(%{title: "Instagram followers"})

    {:ok, view, _html} = live(conn, ~p"/shop")

    # Airtime is a peer of social growth at the top, and links to its own screen.
    assert has_element?(view, "#shop-lines a#line-airtime[href='/airtime']")
    assert has_element?(view, "#line-airtime .hero-device-phone-mobile")

    # Social growth jumps to the offers it sits above.
    assert has_element?(view, "a#line-growth[href='#offers-card']")
    assert has_element?(view, "#line-growth .hero-arrow-trending-up")

    # The order down the page: product lines, then the catalog, then the explanation.
    html = render(view)
    assert index_of(html, "shop-lines") < index_of(html, "offers-card")
    assert index_of(html, "offers-card") < index_of(html, "grades-card")
  end

  test "/shop keeps the platform filter with the offers it filters", %{conn: conn} do
    published_offer_fixture(%{title: "IG followers", platform: "instagram"})
    published_offer_fixture(%{title: "TikTok likes", platform: "tiktok"})

    {:ok, view, _html} = live(conn, ~p"/shop")

    assert has_element?(view, "#offers-card #offer-filters #chip-all")
    assert has_element?(view, "#offers-card #offer-filters #chip-tiktok")

    html = view |> element("#chip-tiktok") |> render_click()

    assert html =~ "TikTok likes"
    refute html =~ "IG followers"
  end

  test "the market records a page view", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/")

    assert [%{path: "/"}] = Insight.list_page_views()
  end

  defp index_of(html, needle) do
    {at, _len} = :binary.match(html, needle)
    at
  end
end
