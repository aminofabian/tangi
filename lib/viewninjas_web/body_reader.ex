defmodule ViewNinjasWeb.BodyReader do
  @moduledoc """
  Keeps the exact bytes of a request body, so a signed webhook can be checked.

  `Plug.Parsers` consumes the body, so this reader runs first and stashes each
  chunk in `conn.assigns[:raw_body]`. The Malipo signature is an HMAC of the raw
  body — a re-serialized object would not match (scope.md §8).
  """

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()} | {:more, binary(), Plug.Conn.t()} | {:error, term()}
  def read_body(conn, opts) do
    with {:ok, body, conn} <- Plug.Conn.read_body(conn, opts) do
      conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
      {:ok, body, conn}
    end
  end

  @doc "The raw body collected so far, as one binary."
  @spec raw_body(Plug.Conn.t()) :: binary()
  def raw_body(conn) do
    conn.assigns
    |> Map.get(:raw_body, [])
    |> List.wrap()
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end
end
