defmodule ViewNinjasWeb.Plugs.Referrer do
  @moduledoc """
  Stashes an external referrer in the session so a LiveView can record it with
  the page view (build-plan.md M6).

  Only a referrer from another host is kept — a same-site navigation would
  otherwise rewrite the session cookie on every request and would not describe
  how the visitor arrived anyway.
  """
  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_req_header(conn, "referer") do
      [referrer | _] -> maybe_put(conn, referrer)
      [] -> conn
    end
  end

  defp maybe_put(conn, referrer) do
    if external?(referrer, conn.host), do: put_session(conn, :referrer, referrer), else: conn
  end

  defp external?(referrer, host) do
    case URI.parse(referrer) do
      %URI{host: nil} -> false
      %URI{host: referrer_host} -> referrer_host != host
    end
  end
end
