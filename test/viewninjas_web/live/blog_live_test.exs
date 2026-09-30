defmodule ViewNinjasWeb.BlogLiveTest do
  @moduledoc """
  The blog (scope.md §11): the hub at `/blog`, one page per article, and the
  crawler surfaces — canonical URL, description, article and FAQ structured
  data, the sitemap entry and the trailing-slash redirect.
  """

  use ViewNinjasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias ViewNinjas.Blog
  alias ViewNinjas.Insight
  alias ViewNinjasWeb.SEO

  @pillar "buy-youtube-views-kenya"

  test "the hub lists the cluster, its pillar and its spokes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog")

    assert has_element?(view, "#cluster-buy-youtube-views-kenya")
    assert has_element?(view, "a[href='/blog/#{@pillar}']")

    for post <- Blog.spokes("buy-youtube-views-kenya") do
      assert has_element?(view, "a[href='/blog/#{post.slug}']")
    end
  end

  test "an article renders its title, contents, a section and its FAQ", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/#{@pillar}")

    assert has_element?(view, "h1.vn-article__title")
    assert render(view) =~ "The Complete Guide to Growing Your Videos"
    assert has_element?(view, "nav.vn-toc")
    assert has_element?(view, "#cost")
    assert has_element?(view, ".vn-table-wrap")
    assert has_element?(view, "ul.vn-prose__list")
    assert has_element?(view, "#faq")
    assert has_element?(view, ".vn-faq__item")
  end

  test "the pillar links down to every spoke", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/#{@pillar}")

    for post <- Blog.spokes("buy-youtube-views-kenya") do
      assert has_element?(view, "a[href='/blog/#{post.slug}']")
    end
  end

  test "a spoke links back up to its pillar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/how-to-buy-youtube-views-in-kenya")

    assert has_element?(view, "a[href='/blog/#{@pillar}']")
  end

  test "an unknown slug returns to the hub", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/blog"}}} = live(conn, ~p"/blog/does-not-exist")
  end

  test "an article carries a canonical URL, a description and article data", %{conn: conn} do
    conn = get(conn, ~p"/blog/#{@pillar}")
    html = html_response(conn, 200)

    assert html =~ ~s(href="#{Plug.Conn.request_url(conn)}")
    assert html =~ "Buy YouTube Views in Kenya"
    assert html =~ ~s(property="og:type" content="article")
    assert html =~ ~s("@type":"BlogPosting")
    assert html =~ ~s("@type":"FAQPage")
    assert html =~ ~s("@type":"BreadcrumbList")
  end

  test "the hub is a collection page a crawler can read", %{conn: conn} do
    html = conn |> get(~p"/blog") |> html_response(200)

    assert html =~ ~s(content="index, follow")
    assert html =~ ~s("@type":"CollectionPage")
    assert html =~ ~s(property="og:type" content="website")
  end

  test "a trailing slash is redirected to the canonical path", %{conn: conn} do
    conn = get(conn, "/blog/")

    assert conn.status == 301
    assert get_resp_header(conn, "location") == ["/blog"]
  end

  test "the sitemap lists the hub and every article with a lastmod", %{conn: conn} do
    body = conn |> get(~p"/sitemap.xml") |> response(200)

    assert body =~ "<loc>#{SEO.absolutize("/blog")}</loc>"

    for post <- Blog.list_posts() do
      assert body =~ "<loc>#{SEO.absolutize(Blog.Post.path(post))}</loc>"
    end

    assert body =~ "<lastmod>"
  end

  test "reading an article records a page view", %{conn: conn} do
    {:ok, _view, _html} = live(conn, ~p"/blog/#{@pillar}")

    assert [%{path: path}] = Insight.list_page_views()
    assert path == "/blog/#{@pillar}"
  end
end
