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
  @airtime "buy-airtime-kenya"

  test "the hub lists the cluster, its pillar and its spokes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog")

    assert has_element?(view, "#cluster-buy-youtube-views-kenya")
    assert has_element?(view, "a[href='/blog/#{@pillar}']")

    for post <- Blog.spokes("buy-youtube-views-kenya") do
      assert has_element?(view, "a[href='/blog/#{post.slug}']")
    end
  end

  test "the hub lists every cluster", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog")

    for cluster <- Blog.list_clusters() do
      assert has_element?(view, "#cluster-#{cluster.slug}")
    end
  end

  test "every post slug is unique across clusters" do
    slugs = Enum.map(Blog.list_posts(), & &1.slug)

    assert slugs == Enum.uniq(slugs)
  end

  test "the providers pillar compares Tangi and links to its own shop", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/top-youtube-views-providers-kenya")

    assert has_element?(view, "#tangi")
    assert has_element?(view, ".vn-table-wrap")
    assert render(view) =~ "Tangi"
    assert has_element?(view, "a[href='/shop']")
  end

  test "the providers pillar links down to every spoke and across to the guide", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/top-youtube-views-providers-kenya")

    for post <- Blog.spokes("top-youtube-views-providers-kenya") do
      assert has_element?(view, "a[href='/blog/#{post.slug}']")
    end

    assert has_element?(view, "a[href='/blog/#{@pillar}']")
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

  test "the top 10 article renders, discloses Tangi and links to the pillar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/top-10-youtube-views-providers-kenya")

    assert has_element?(view, "h1.vn-article__title")
    assert has_element?(view, ".vn-table-wrap")
    assert render(view) =~ "Tangi"
    assert has_element?(view, "a[href='/blog/top-youtube-views-providers-kenya']")
  end

  test "the TikTok followers pillar compares Tangi and links to its spokes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/top-tiktok-followers-providers-kenya")

    assert has_element?(view, "#how-we-compare")
    assert has_element?(view, "#tangi")
    assert has_element?(view, ".vn-table-wrap")
    assert render(view) =~ "Tangi"
    assert has_element?(view, "a[href='/shop']")

    for post <- Blog.spokes("top-tiktok-followers-providers-kenya") do
      assert has_element?(view, "a[href='/blog/#{post.slug}']")
    end
  end

  test "a spoke links back up to its TikTok pillar", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/tiktok-followers-vs-views")

    assert has_element?(view, "a[href='/blog/top-tiktok-followers-providers-kenya']")
  end

  test "the hub lists the airtime cluster and every airtime article", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog")

    assert has_element?(view, "#cluster-#{@airtime}")
    assert has_element?(view, "a[href='/blog/#{@airtime}']")

    for post <- Blog.spokes(@airtime) do
      assert has_element?(view, "a[href='/blog/#{post.slug}']")
    end
  end

  test "the airtime pillar links down to every spoke and carries a table and FAQ", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/#{@airtime}")

    assert has_element?(view, "h1.vn-article__title")
    assert has_element?(view, ".vn-table-wrap")
    assert has_element?(view, "#faq")

    for post <- Blog.spokes(@airtime) do
      assert has_element?(view, "a[href='/blog/#{post.slug}']")
    end
  end

  test "an airtime spoke links up to the pillar and down to the buy screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/blog/buy-safaricom-airtime")

    assert has_element?(view, "a[href='/blog/#{@airtime}']")
    assert has_element?(view, "a[href='/airtime']")
  end

  test "every airtime spoke carries its own FAQs" do
    for post <- Blog.spokes(@airtime) do
      refute post.faqs == [], "#{post.slug} has no FAQs"
    end
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
