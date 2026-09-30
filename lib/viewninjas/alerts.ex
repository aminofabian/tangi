defmodule ViewNinjas.Alerts do
  @moduledoc """
  The things a person should look at, announced once (scope.md §10, §11).

  M9 needs somewhere for the float and the stale lanes to land. This is the
  smallest thing that is honest: every alert is logged and broadcast, and the
  back office shows what it has heard since it opened. A durable, delivered
  digest is M11's job — nothing here is stored.
  """

  require Logger

  @pubsub ViewNinjas.PubSub
  @topic "alerts"

  @doc "Subscribes the caller to alerts raised while it is open."
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc "Raises an alert: one log line and one broadcast."
  @spec publish(atom(), String.t(), map()) :: :ok
  def publish(kind, message, meta \\ %{}) when is_atom(kind) and is_binary(message) do
    Logger.warning("alert #{kind}: #{message}")

    Phoenix.PubSub.broadcast(
      @pubsub,
      @topic,
      {:alert, %{kind: kind, message: message, meta: meta, at: DateTime.utc_now(:second)}}
    )
  end
end
