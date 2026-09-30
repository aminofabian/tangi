defmodule ViewNinjasWeb.SEO do
  @moduledoc """
  The facts the public pages hand a crawler: one canonical URL, one description,
  and the schema.org data that says what ViewNinjas sells, who sells it, and
  where.

  All of it is written into the root layout, which is rendered on the server for
  every URL and is never touched by a live navigation — so a bot that fetches a
  page and never runs JavaScript still sees the whole thing. `encode!/1` uses
  `:html_safe` escaping so a `<`, `>` or `&` in a title can never break out of
  the JSON-LD `<script>` block.
  """

  use Gettext, backend: ViewNinjasWeb.Gettext

  alias ViewNinjasWeb.Endpoint

  @site_name "ViewNinjas"
  @currency "KES"

  @doc "The site's name, as search engines and cards should print it."
  @spec site_name() :: String.t()
  def site_name, do: @site_name

  @doc "The `<title>` for the market — the homepage and the shop."
  @spec default_title() :: String.t()
  def default_title do
    gettext("Buy Instagram Followers, TikTok Likes and YouTube Views in Kenya")
  end

  @doc "The site-wide meta description, and the fallback for any page without one."
  @spec default_description() :: String.t()
  def default_description do
    gettext(
      "Buy Instagram followers, TikTok likes and YouTube views in Kenya, priced in shillings. Three grades, M-Pesa checkout, and a refill when delivery falls short."
    )
  end

  @doc """
  An absolute URL for a path on this site.
  """
  @spec absolutize(String.t()) :: String.t()
  def absolutize(path), do: Endpoint.url() <> ensure_leading_slash(path)

  @doc """
  The absolute, query-free canonical URL for a request.

  `uri` is whatever `handle_params/3` supplies: a full URL on the first server
  render, a bare path on a live navigation. Both are accepted; a path is
  resolved against the configured endpoint, and any query or fragment (chip
  filters, `utm_*`) is dropped so every variant points at one URL.
  """
  @spec canonical_url(String.t() | nil) :: String.t()
  def canonical_url(uri) when is_binary(uri) do
    case URI.parse(uri) do
      %URI{host: host} = parsed when is_binary(host) ->
        %{parsed | query: nil, fragment: nil} |> URI.to_string()

      %URI{path: path} ->
        absolutize(path || "/")
    end
  end

  def canonical_url(_uri), do: absolutize("/")

  @doc """
  Encodes structured data for a `<script type="application/ld+json">` block.
  """
  @spec encode!(map()) :: String.t()
  def encode!(data), do: Jason.encode!(data, escape: :html_safe)

  @doc "The publisher, named once for every page."
  @spec organization() :: map()
  def organization do
    %{
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => @site_name,
      "url" => Endpoint.url(),
      "logo" => absolutize("/images/icon-512.png"),
      "description" => default_description(),
      "areaServed" => %{"@type" => "Country", "name" => "Kenya"}
    }
  end

  @doc "The site itself, so the pages bind to one name."
  @spec website() :: map()
  def website do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => @site_name,
      "url" => Endpoint.url(),
      "inLanguage" => "en-KE"
    }
  end

  @doc """
  A `Product` carrying an `AggregateOffer` for one offer's price span.

  `:prices` is the offer's lane prices in whole shillings, in any order; the
  cheapest and dearest become `lowPrice` and `highPrice`.
  """
  @spec product(map()) :: map()
  def product(%{name: name, description: description, url: url, prices: prices}) do
    %{
      "@context" => "https://schema.org",
      "@type" => "Product",
      "name" => name,
      "description" => description,
      "url" => url,
      "brand" => %{"@type" => "Brand", "name" => @site_name},
      "areaServed" => %{"@type" => "Country", "name" => "Kenya"},
      "offers" => aggregate_offer(prices, url)
    }
  end

  @doc "A breadcrumb trail from a list of `%{name: _, url: _}`, in order."
  @spec breadcrumbs([map()]) :: map()
  def breadcrumbs(items) do
    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" =>
        items
        |> Enum.with_index(1)
        |> Enum.map(fn {%{name: name, url: url}, position} ->
          %{"@type" => "ListItem", "position" => position, "name" => name, "item" => url}
        end)
    }
  end

  defp aggregate_offer([], url) do
    %{"@type" => "Offer", "url" => url, "priceCurrency" => @currency}
  end

  defp aggregate_offer(prices, url) do
    %{
      "@type" => "AggregateOffer",
      "url" => url,
      "priceCurrency" => @currency,
      "lowPrice" => Enum.min(prices),
      "highPrice" => Enum.max(prices),
      "offerCount" => length(prices),
      "availability" => "https://schema.org/InStock"
    }
  end

  defp ensure_leading_slash("/" <> _ = path), do: path
  defp ensure_leading_slash(path), do: "/" <> path
end
