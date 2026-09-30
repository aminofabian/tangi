defmodule ViewNinjas.Sms.Providers.Test do
  @moduledoc """
  Test provider: records sent messages in a public ETS table so tests can read
  the body — and therefore the OTP — without it ever touching the database.

  The table is owned by `ViewNinjas.Sms.Outbox`, which the application starts
  when this provider is configured, so messages survive for the whole run.
  Messages are keyed by the phone number, which is unique per test, so tests do
  not see each other's.
  """
  @behaviour ViewNinjas.Sms.Provider

  @table :viewninjas_sms_test_outbox

  @doc "The outbox table's name."
  def table, do: @table

  @impl true
  def send_sms(to, body) do
    table = ensure_table()
    ref = "test-#{System.unique_integer([:positive])}"
    :ets.insert(table, {to, ref, body, System.monotonic_time(:millisecond)})

    {:ok, %{provider_ref: ref, status: :sent, cost_micros: 0}}
  end

  @doc "All messages sent to `to`, oldest first, as `{provider_ref, body}`."
  def messages(to) do
    ensure_table()
    |> :ets.tab2list()
    |> Enum.flat_map(fn
      {^to, ref, body, at} -> [{at, ref, body}]
      _ -> []
    end)
    |> Enum.sort()
    |> Enum.map(fn {_at, ref, body} -> {ref, body} end)
  end

  @doc "The most recent message sent to `to`, as `{provider_ref, body}`, or nil."
  def last_message(to), do: to |> messages() |> List.last()

  @doc "The most recent 6-digit code sent to `to`, or nil."
  def last_code(to) do
    case last_message(to) do
      {_ref, body} ->
        case Regex.run(~r/\b(\d{6})\b/, body) do
          [_, code] -> code
          _ -> nil
        end

      nil ->
        nil
    end
  end

  # `ViewNinjas.Sms.Outbox` normally owns the table. The fallback only matters
  # if this provider is used without it having been started.
  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :bag])
        rescue
          ArgumentError -> @table
        end

      _ ->
        @table
    end

    @table
  end
end
