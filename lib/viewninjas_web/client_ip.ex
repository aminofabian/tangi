defmodule ViewNinjasWeb.ClientIp do
  @moduledoc """
  Resolves the client IP used to key rate limits (scope.md §13).

  Behind a proxy (Fly.io, a VPS) the peer address is the proxy, so the first
  `x-forwarded-for` entry is preferred when present. Only trust that header
  when the app genuinely sits behind a proxy that sets it; otherwise fall back
  to the peer address.
  """

  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(conn) do
    forwarded(Plug.Conn.get_req_header(conn, "x-forwarded-for")) ||
      format_address(conn.remote_ip)
  end

  @spec from_socket(Phoenix.LiveView.Socket.t()) :: String.t()
  def from_socket(socket) do
    forwarded(x_forwarded_values(socket)) || format_address(socket_peer_address(socket))
  end

  defp x_forwarded_values(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :x_headers) do
      headers when is_list(headers) ->
        for {name, value} <- headers,
            String.downcase(to_string(name)) == "x-forwarded-for",
            do: value

      _ ->
        []
    end
  end

  defp socket_peer_address(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address
      _ -> nil
    end
  end

  # "client, proxy1, proxy2" -> "client"
  defp forwarded([value | _]) when is_binary(value) do
    case value |> String.split(",") |> List.first() |> String.trim() do
      "" -> nil
      ip -> ip
    end
  end

  defp forwarded(_), do: nil

  defp format_address(nil), do: "unknown"

  defp format_address(address) do
    case :inet.ntoa(address) do
      {:error, _} -> "unknown"
      charlist -> to_string(charlist)
    end
  end
end
