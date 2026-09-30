defmodule ViewNinjasWeb.RobotsController do
  @moduledoc """
  `robots.txt`, generated rather than static so the `Sitemap:` line is absolute
  on whatever host the app is served from — `localhost` in development, the real
  host in production.

  The market is meant to be crawled; the transactional surfaces behind a login
  (`/admin`, `/users`, the wallet, orders and checkout) are not, and a few of
  them also send `noindex` themselves.
  """
  use ViewNinjasWeb, :controller

  alias ViewNinjasWeb.SEO

  @disallow ~w(/admin /users /account /orders /wallet /checkout)

  def index(conn, _params) do
    body = """
    User-agent: *
    Allow: /
    #{disallow_lines()}
    Sitemap: #{SEO.absolutize("/sitemap.xml")}
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  defp disallow_lines do
    @disallow
    |> Enum.map_join("\n", &"Disallow: #{&1}")
  end
end
