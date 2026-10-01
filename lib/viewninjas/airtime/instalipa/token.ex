defmodule ViewNinjas.Airtime.Instalipa.Token do
  @moduledoc """
  Caches the Instalipa bearer (scope: `docs/instalipa-airtime.md` §3.1).

  Instalipa issues a token good for an hour from `POST /api/v1/token`, authenticated
  with HTTP Basic `base64(consumer_key:consumer_secret)`. Fetching it on every call
  would double the requests and lean on the rail's rate limits, so it is held in memory
  and refreshed a few minutes early. It is never written to the database and never
  logged.

  The HTTP call runs in the **calling** process, not in this process: this one only owns
  the table for the app's lifetime. That keeps the request out of a single mailbox and
  lets a caller mint on a cold cache without a round trip to here.
  """
  use GenServer

  @table :viewninjas_airtime_token
  @key :bearer
  # Refresh this long before the hour is up, so a token is never used at its edge.
  @margin_seconds 300

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "A live token, minting one when the cache is cold or the token is stale."
  @spec fetch() :: {:ok, String.t()} | {:error, term()}
  def fetch do
    case cached() do
      {:ok, token} -> {:ok, token}
      :miss -> mint()
    end
  end

  @doc "Mints a fresh token, discarding the cached one. This is what a `401` calls."
  @spec refresh() :: {:ok, String.t()} | {:error, term()}
  def refresh do
    reset()
    fetch()
  end

  @doc "Forgets the cached token. For tests, and for a forced re-auth."
  @spec reset() :: :ok
  def reset do
    :ets.delete(@table, @key)
    :ok
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  defp cached do
    case :ets.lookup(@table, @key) do
      [{@key, token, expires_at}] ->
        if System.monotonic_time(:second) < expires_at, do: {:ok, token}, else: :miss

      [] ->
        :miss
    end
  end

  defp mint do
    case ViewNinjas.Airtime.Instalipa.request_token() do
      {:ok, token, expires_in} ->
        expires_at = System.monotonic_time(:second) + expires_in - @margin_seconds
        :ets.insert(@table, {@key, token, expires_at})
        {:ok, token}

      {:error, _reason} = error ->
        error
    end
  end
end
