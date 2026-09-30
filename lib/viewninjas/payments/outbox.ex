defmodule ViewNinjas.Payments.Outbox do
  @moduledoc """
  Owns the in-memory payment table used by `ViewNinjas.Payments.Providers.Test`.

  ETS tables die with their owner, so a table created lazily by whichever test
  runs first would vanish and take other tests' payments with it. Started only
  when the configured payments provider is the in-memory one (tests).
  """
  use GenServer

  alias ViewNinjas.Payments.Providers.Test

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "The table's name."
  def table, do: Test.table()

  @impl GenServer
  def init(_opts) do
    :ets.new(table(), [:named_table, :public, :set])
    {:ok, %{}}
  end
end
