defmodule ViewNinjasWeb.Plugs.TrailingSlash do
  @moduledoc """
  Redirects a trailing-slash URL to the same path without it, so every page has
  one address.

  A page can be reached as `/blog/` and `/blog`, and a crawler that sees both
  has to be told which is the real one. Rather than declare a canonical URL for
  each variant, the extra slash is dropped with a permanent redirect, and the
  canonical URL the pages already emit stays the single address.

  Only `GET` and `HEAD` are rewritten — a form post to `/users/log-in/` should
  not be silently turned into a `GET` — and the root path is left alone.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{method: method, request_path: path} = conn, _opts)
      when method in ["GET", "HEAD"] do
    trimmed = String.trim_trailing(path, "/")

    if trimmed != "" and trimmed != path do
      redirect(conn, trimmed)
    else
      conn
    end
  end

  def call(conn, _opts), do: conn

  defp redirect(conn, path) do
    location = path <> query(conn)

    conn
    |> put_resp_header("location", location)
    |> send_resp(301, "")
    |> halt()
  end

  defp query(%Plug.Conn{query_string: ""}), do: ""
  defp query(%Plug.Conn{query_string: query}), do: "?" <> query
end
