defmodule ViewNinjasWeb.SitemapController do
  @moduledoc """
  `sitemap.xml`: the market's landing pages and every offer that is on sale right
  now.

  An offer is on sale only when it is published and carries at least one
  published lane (scope.md §11), which is exactly what the market shows — so an
  unpublished offer, or one waiting on a re-pin, is never advertised to a
  crawler either.
  """
  use ViewNinjasWeb, :controller

  alias ViewNinjas.Catalog
  alias ViewNinjasWeb.SEO

  @static_paths ~w(/ /shop /refunds)

  def index(conn, _params) do
    body = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.map_join(urls(), "\n", &entry/1)}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, body)
  end

  defp urls do
    Enum.map(@static_paths, &{&1, nil}) ++ Enum.map(Catalog.list_market_offers(), &offer/1)
  end

  defp offer(offer), do: {"/offers/#{offer.id}", offer.updated_at}

  defp entry({path, lastmod}) do
    "<url><loc>#{escape(SEO.absolutize(path))}</loc>#{lastmod_tag(lastmod)}</url>"
  end

  defp lastmod_tag(%DateTime{} = at) do
    "<lastmod>#{at |> DateTime.to_date() |> Date.to_iso8601()}</lastmod>"
  end

  defp lastmod_tag(_), do: ""

  # Locations are built from our own routes, but a query or a host could still
  # carry a character the XML grammar reserves, so escape the two that matter.
  defp escape(url) do
    url |> String.replace("&", "&amp;") |> String.replace("<", "&lt;")
  end
end
