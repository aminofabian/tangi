defmodule ViewNinjasWeb.BlogLive do
  @moduledoc """
  The blog (scope.md §11): a hub at `/blog` and one page per article at
  `/blog/:slug`.

  Articles are public and read by crawlers, so the head tags — title,
  description, canonical URL and `BlogPosting` / `FAQPage` structured data — are
  set exactly as the market sets them, and the whole page is a plain server
  render. The prose comes from `ViewNinjas.Blog` as data; this module turns the
  blocks into HTML and renders the table of contents, the FAQ and the related
  links.
  """
  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Blog
  alias ViewNinjas.Blog.Post
  alias ViewNinjasWeb.{Analytics, SEO}

  @inline_link ~r/\[([^\]]+)\]\(([^)]+)\)/

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:page_title, gettext("Guides"))
     |> assign(:page_robots, "index, follow")
     |> assign(:og_type, "website")
     |> assign(:canonical_url, nil)
     |> assign(:structured_data, [])
     |> assign(:clusters, [])
     |> assign(:post, nil)
     |> assign(:related, [])}
  end

  @impl true
  def handle_params(params, uri, socket) do
    Analytics.record_page_view(socket, uri)

    socket =
      case socket.assigns.live_action do
        :show -> show(socket, params, uri)
        _ -> index(socket, uri)
      end

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section={:blog} title={@page_title}>
      <%= if @post do %>
        <.article post={@post} related={@related} />
      <% else %>
        <.hub clusters={@clusters} />
      <% end %>
    </Layouts.app>
    """
  end

  # -- the hub -----------------------------------------------------------

  defp index(socket, uri) do
    canonical = SEO.canonical_url(uri)
    description = hub_description()

    clusters =
      Enum.map(Blog.list_clusters(), fn cluster ->
        %{
          cluster: cluster,
          pillar: Blog.pillar(cluster.slug),
          spokes: Blog.spokes(cluster.slug)
        }
      end)

    items =
      Enum.map(Blog.list_posts(), &%{name: &1.title, url: SEO.absolutize(Post.path(&1))})

    socket
    |> assign(:meta_title, gettext("YouTube Growth Guides for Kenyan Creators | Tangi"))
    |> assign(:page_description, description)
    |> assign(:canonical_url, canonical)
    |> assign(:clusters, clusters)
    |> assign(:structured_data, [
      SEO.collection_page(%{
        name: gettext("YouTube growth guides"),
        description: description,
        url: canonical,
        items: items
      }),
      SEO.breadcrumbs([
        %{name: gettext("Home"), url: SEO.absolutize("/")},
        %{name: gettext("Guides"), url: canonical}
      ])
    ])
  end

  # -- one article -------------------------------------------------------

  defp show(socket, %{"slug" => slug}, uri) do
    case Blog.get_post(slug) do
      nil ->
        push_navigate(socket, to: ~p"/blog")

      post ->
        canonical = SEO.canonical_url(uri)

        socket
        |> assign(:post, post)
        |> assign(:related, Blog.related(post))
        |> assign(:meta_title, post.meta_title)
        |> assign(:page_description, post.description)
        |> assign(:canonical_url, canonical)
        |> assign(:og_type, "article")
        |> assign(:structured_data, structured_data(post, canonical))
    end
  end

  defp show(socket, _params, _uri), do: push_navigate(socket, to: ~p"/blog")

  defp structured_data(post, canonical) do
    base = [
      SEO.article(%{
        headline: post.title,
        description: post.description,
        url: canonical,
        date_published: post.updated_on,
        date_modified: post.updated_on,
        keywords: post.keywords
      }),
      SEO.breadcrumbs([
        %{name: gettext("Home"), url: SEO.absolutize("/")},
        %{name: gettext("Guides"), url: SEO.absolutize("/blog")},
        %{name: post.title, url: canonical}
      ])
    ]

    if post.faqs == [], do: base, else: base ++ [SEO.faq_page(post.faqs)]
  end

  # -- hub rendering -----------------------------------------------------

  attr :clusters, :list, required: true

  defp hub(assigns) do
    ~H"""
    <section class="vn-hero vn-blog-hero">
      <p class="vn-eyebrow">{gettext("Guides")}</p>
      <h1 class="vn-hero__title">{gettext("YouTube growth guides")}</h1>
      <p class="vn-hero__tagline">
        {gettext(
          "Practical guides on buying YouTube views in Kenya, growing a channel organically, and promoting your videos — written for Kenyan creators."
        )}
      </p>
    </section>

    <section :for={entry <- @clusters} class="vn-card vn-cluster" id={"cluster-#{entry.cluster.slug}"}>
      <p class="vn-eyebrow">{entry.cluster.eyebrow}</p>
      <h2>{entry.cluster.title}</h2>
      <p class="vn-muted">{entry.cluster.description}</p>

      <.pillar_link :if={entry.pillar} post={entry.pillar} />

      <ul :if={entry.spokes != []} class="vn-post-list">
        <li :for={post <- entry.spokes}>
          <.link navigate={~p"/blog/#{post.slug}"} class="vn-post-list__link">
            <span class="vn-post-list__eyebrow">{post.eyebrow}</span>
            <span class="vn-post-list__title">{post.title}</span>
          </.link>
        </li>
      </ul>
    </section>

    <section class="vn-card">
      <h2>{gettext("Ready to grow?")}</h2>
      <p class="vn-muted">
        {gettext(
          "Guides are free. When you want to give a video a head start, the shop sells YouTube views in Kenya priced in shillings."
        )}
      </p>
      <.link navigate={~p"/shop"} class="vn-button">{gettext("Go to the shop")}</.link>
    </section>
    """
  end

  attr :post, :any, required: true

  defp pillar_link(assigns) do
    ~H"""
    <.link navigate={~p"/blog/#{@post.slug}"} class="vn-feature">
      <span class="vn-feature__eyebrow">{@post.eyebrow || gettext("Start here")}</span>
      <span class="vn-feature__title">{@post.title}</span>
      <span class="vn-feature__excerpt">{@post.description}</span>
    </.link>
    """
  end

  # -- article rendering -------------------------------------------------

  attr :post, :any, required: true
  attr :related, :list, required: true

  defp article(assigns) do
    assigns =
      assigns
      |> assign(:toc, Post.toc(assigns.post))
      |> assign(:reading, Post.reading_minutes(assigns.post))

    ~H"""
    <article class="vn-article">
      <nav class="vn-crumbs" aria-label={gettext("Breadcrumb")}>
        <.link navigate={~p"/blog"} class="vn-crumbs__link">{gettext("Guides")}</.link>
        <span class="vn-crumbs__sep" aria-hidden="true">/</span>
        <span class="vn-crumbs__here">{@post.eyebrow}</span>
      </nav>

      <header class="vn-article__header">
        <h1 class="vn-article__title">{@post.title}</h1>
        <p class="vn-article__meta">
          {updated_label(@post.updated_on)} · {gettext("%{minutes} min read", minutes: @reading)}
        </p>
      </header>

      <p :for={paragraph <- @post.intro} class="vn-article__lead">
        <.rich text={paragraph} />
      </p>

      <nav :if={@toc != []} class="vn-toc" aria-label={gettext("On this page")}>
        <p class="vn-toc__title">{gettext("On this page")}</p>
        <ol class="vn-toc__list">
          <li :for={section <- @toc}>
            <a href={"##{section.id}"}>{section.heading}</a>
          </li>
        </ol>
      </nav>

      <section :for={section <- @post.sections} id={section.id} class="vn-article__section">
        <h2>{section.heading}</h2>
        <.block :for={block <- section.blocks} block={block} />
      </section>

      <section :if={@post.faqs != []} id="faq" class="vn-article__section">
        <h2>{gettext("Frequently Asked Questions")}</h2>
        <div class="vn-faq">
          <div :for={faq <- @post.faqs} class="vn-faq__item">
            <h3 class="vn-faq__q">{faq.question}</h3>
            <p class="vn-faq__a">{faq.answer}</p>
          </div>
        </div>
      </section>

      <aside :if={@related != []} class="vn-related">
        <h2>{gettext("Keep reading")}</h2>
        <ul class="vn-post-list">
          <li :for={post <- @related}>
            <.link navigate={~p"/blog/#{post.slug}"} class="vn-post-list__link">
              <span class="vn-post-list__eyebrow">{post.eyebrow}</span>
              <span class="vn-post-list__title">{post.title}</span>
            </.link>
          </li>
        </ul>
      </aside>
    </article>
    """
  end

  # -- blocks ------------------------------------------------------------

  attr :block, :any, required: true

  defp block(assigns) do
    ~H"""
    <%= case @block do %>
      <% {:p, text} -> %>
        <p class="vn-prose__p"><.rich text={text} /></p>
      <% {:h3, text} -> %>
        <h3><.rich text={text} /></h3>
      <% {:ul, items} -> %>
        <ul class="vn-prose__list">
          <li :for={item <- items}><.rich text={item} /></li>
        </ul>
      <% {:ol, items} -> %>
        <ol class="vn-prose__list vn-prose__list--ordered">
          <li :for={item <- items}><.rich text={item} /></li>
        </ol>
      <% {:callout, text} -> %>
        <p class="vn-callout"><.rich text={text} /></p>
      <% {:table, %{head: head, rows: rows}} -> %>
        <div class="vn-table-wrap">
          <table class="vn-table">
            <thead>
              <tr>
                <th :for={cell <- head}>{cell}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={row <- rows}>
                <td :for={cell <- row}>{cell}</td>
              </tr>
            </tbody>
          </table>
        </div>
      <% {:cta, %{text: text, href: href, label: label}} -> %>
        <aside class="vn-cta">
          <p><.rich text={text} /></p>
          <.link navigate={href} class="vn-button">{label}</.link>
        </aside>
    <% end %>
    """
  end

  # -- inline links ------------------------------------------------------

  attr :text, :string, required: true

  defp rich(assigns) do
    assigns = assign(assigns, :segments, rich_segments(assigns.text))

    ~H"""
    <.segment :for={segment <- @segments} segment={segment} />
    """
  end

  attr :segment, :any, required: true

  defp segment(assigns) do
    ~H"""
    <%= case @segment do %>
      <% {:text, text} -> %>
        {text}
      <% {:link, label, href} -> %>
        <.link :if={internal?(href)} navigate={href} class="text-brand hover:underline">
          {label}
        </.link>
        <.link :if={!internal?(href)} href={href} rel="noopener" class="text-brand hover:underline">
          {label}
        </.link>
    <% end %>
    """
  end

  # Splits `text` into runs of plain text and `[label](href)` links, so the
  # prose can carry internal links without embedding HTML in the content data.
  defp rich_segments(text) when is_binary(text), do: do_rich(text, [])

  defp do_rich("", acc), do: Enum.reverse(acc)

  defp do_rich(text, acc) do
    case Regex.run(@inline_link, text, return: :index) do
      nil ->
        Enum.reverse([{:text, text} | acc])

      [{start, length} | [{label_at, label_len}, {href_at, href_len}]] ->
        before = binary_part(text, 0, start)
        rest_at = start + length
        rest = binary_part(text, rest_at, byte_size(text) - rest_at)
        acc = if before == "", do: acc, else: [{:text, before} | acc]
        label = binary_part(text, label_at, label_len)
        href = binary_part(text, href_at, href_len)

        do_rich(rest, [{:link, label, href} | acc])
    end
  end

  defp internal?(href), do: String.starts_with?(href, "/")

  # -- helpers -----------------------------------------------------------

  defp updated_label(date) do
    gettext("Updated %{date}", date: friendly_date(date))
  end

  defp friendly_date(%Date{day: day, month: month, year: year}) do
    "#{day} #{Enum.at(months(), month - 1)} #{year}"
  end

  defp months do
    ~w(January February March April May June July August September October November December)
  end

  defp hub_description do
    gettext(
      "Guides on buying YouTube views in Kenya, growing a channel organically and promoting your videos, written for Kenyan creators."
    )
  end
end
