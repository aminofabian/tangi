defmodule ViewNinjasWeb.SeoTest do
  @moduledoc """
  The crawler surfaces (build-plan.md M12): the head tags a bot reads without
  running JavaScript — title, description, canonical, cards and structured data —
  plus the sitemap and robots.txt.

  The head tags live in the root layout, which `render/1` on a LiveView does not
  include, so these assert against the server-rendered document from a plain
  `GET`, exactly what a crawler that never opens a socket receives.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.CatalogFixtures

  alias ViewNinjasWeb.SEO

  test "the shop leads with the search terms in its title, description and cards", %{conn: conn} do
    conn = get(conn, ~p"/shop")
    html = html_response(conn, 200)

    assert html =~ "Buy Instagram Followers, TikTok Likes and YouTube Views in Kenya"
    assert html =~ ~s(content="Buy Instagram followers, TikTok likes and YouTube views in Kenya)
    # The canonical URL is the URL the page was served from, not a hard-coded host.
    assert html =~ ~s(href="#{Plug.Conn.request_url(conn)}")
    assert html =~ ~s(content="index, follow")
    assert html =~ ~s(property="og:title")
    assert html =~ ~s(name="twitter:card")
  end

  test "every page names the publisher as structured data", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ "application/ld+json"
    assert html =~ ~s("@type":"Organization")
    assert html =~ ~s("@type":"WebSite")
  end

  test "every page carries the Search Console verification tag", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(content="WDnKb4dvZxdQyOUiSsfB94HWTdVcOmwDfnsCV7iY8bU")
    assert html =~ ~s(name="google-site-verification")
  end

  test "an offer page names the offer, its price and a product", %{conn: conn} do
    offer = published_offer_fixture(%{title: "Instagram followers"})

    conn = get(conn, ~p"/offers/#{offer.id}")
    html = html_response(conn, 200)

    assert html =~ "Buy Instagram followers in Kenya"
    assert html =~ ~s(href="#{Plug.Conn.request_url(conn)}")
    assert html =~ ~s(content="product")
    assert html =~ ~s("@type":"Product")
    assert html =~ ~s("@type":"AggregateOffer")
    assert html =~ ~s("priceCurrency":"KES")
    assert html =~ ~s("@type":"BreadcrumbList")
  end

  test "the sitemap lists the public pages and the offers on sale", %{conn: conn} do
    offer = published_offer_fixture(%{title: "Instagram followers"})

    conn = get(conn, ~p"/sitemap.xml")
    body = response(conn, 200)

    assert conn |> get_resp_header("content-type") |> hd() =~ "application/xml"
    assert body =~ "<loc>#{SEO.absolutize("/")}</loc>"
    assert body =~ "<loc>#{SEO.absolutize("/shop")}</loc>"
    assert body =~ "<loc>#{SEO.absolutize("/refunds")}</loc>"
    assert body =~ "<loc>#{SEO.absolutize("/offers/#{offer.id}")}</loc>"
  end

  test "an offer that is not on sale is not in the sitemap", %{conn: conn} do
    offer = offer_fixture(%{title: "Draft", published: false})
    _lane = lane_fixture(%{offer: offer})

    body = conn |> get(~p"/sitemap.xml") |> response(200)

    refute body =~ "/offers/#{offer.id}"
  end

  test "robots.txt steers crawlers at the sitemap and away from the private rooms", %{conn: conn} do
    body = conn |> get(~p"/robots.txt") |> response(200)

    assert body =~ "User-agent: *"
    assert body =~ "Allow: /"
    assert body =~ "Disallow: /admin"
    assert body =~ "Sitemap: #{SEO.absolutize("/sitemap.xml")}"
  end

  test "the signed-in dashboard is kept out of the index", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())

    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(content="noindex, nofollow")
    refute html =~ ~s(rel="canonical")
  end
end
