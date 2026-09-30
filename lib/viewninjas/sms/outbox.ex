defmodule ViewNinjas.Sms.Outbox do
  @moduledoc """
  Owns the in-memory SMS outbox used by `ViewNinjas.Sms.Providers.Test`.

  ETS tables die with their owner, so a table created lazily by whichever test
  happens to send first would vanish when that test finished and take other
  tests' messages with it. This process owns it for the life of the application
  instead.

  It is started only when the configured provider is the in-memory one (tests);
  in development and production there is nothing to own and nothing is started.
  """
  use GenServer

  alias ViewNinjas.Sms.Providers.Test

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The outbox table's name."
  def table, do: Test.table()

  @impl GenServer
  def init(_opts) do
    :ets.new(table(), [:named_table, :public, :bag])
    {:ok, %{}}
  end
end
