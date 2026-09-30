defmodule ViewNinjasWeb.Analytics do
  @moduledoc """
  Bridges a LiveView to `ViewNinjas.Insight` (scope.md §13): it pulls the request
  facts off the socket — address, user agent, and, on the entry view only, the
  referrer and any `utm_*` — and records one PII-free page view.

  LiveView only exposes `connect_info` while mounting, so a LiveView calls
  `capture/2` in `mount/3` and assigns the result; `record_page_view/2` and
  `record_event/2` then work from any callback.

  The referrer and `utm_*` describe how a visitor *arrived*, so they are only
  attached when the view being recorded is the request's own entry path; a later
  live navigation carries none.
  """
  alias ViewNinjas.Insight
  alias ViewNinjasWeb.ClientIp

  @doc "Captures the request facts to assign in `mount/3`."
  @spec capture(Phoenix.LiveView.Socket.t(), map()) :: map()
  def capture(socket, session) do
    %{
      ip: ClientIp.from_socket(socket),
      user_agent: Phoenix.LiveView.get_connect_info(socket, :user_agent),
      user_id: user_id(socket),
      referrer: session["referrer"],
      entry_path: entry_path(socket),
      utm: utm_params(socket)
    }
  end

  @doc "Records the page view for a navigation, given its `uri`."
  @spec record_page_view(Phoenix.LiveView.Socket.t(), String.t()) :: :ok
  def record_page_view(socket, uri) when is_binary(uri) do
    path = uri |> URI.parse() |> Map.get(:path) |> Kernel.||("/")
    record(socket, path)
  end

  @doc """
  Records a synthetic view — a funnel step with no page of its own, like
  "checkout started" (scope.md §11).
  """
  @spec record_event(Phoenix.LiveView.Socket.t(), String.t()) :: :ok
  def record_event(socket, path), do: record(socket, path)

  defp record(socket, path) do
    if Phoenix.LiveView.connected?(socket) do
      analytics = socket.assigns[:analytics] || %{}
      entry? = analytics[:entry_path] == path

      Insight.record_page_view(%{
        path: path,
        ip: analytics[:ip],
        user_agent: analytics[:user_agent],
        user_id: analytics[:user_id],
        referrer: if(entry?, do: analytics[:referrer]),
        utm: if(entry?, do: analytics[:utm], else: %{})
      })
    end

    :ok
  end

  defp entry_path(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :uri) do
      %URI{path: path} -> path
      _ -> nil
    end
  end

  defp utm_params(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :uri) do
      %URI{query: query} when is_binary(query) ->
        query
        |> URI.decode_query()
        |> Map.take(["utm_source", "utm_medium", "utm_campaign"])

      _ ->
        %{}
    end
  end

  defp user_id(socket) do
    case socket.assigns[:current_scope] do
      %{user: %{id: id}} -> id
      _ -> nil
    end
  end
end
