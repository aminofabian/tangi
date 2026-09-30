defmodule ViewNinjas.Workers.RollupDaily do
  @moduledoc """
  Rebuilds one day's `analytics_daily` rollup (scope.md §11; build-plan.md M10).

  Runs just after midnight for the day that has just ended, so the charts read one
  cheap row per day instead of summing the raw tables on a phone. Passing a `day`
  rebuilds that day — the rollup is derived and always rebuildable.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias ViewNinjas.Traffic

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    day = parse_day(args["day"])

    case Traffic.rollup_day(day) do
      {:ok, _row} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_day(nil), do: Date.add(Date.utc_today(), -1)

  defp parse_day(day) when is_binary(day) do
    case Date.from_iso8601(day) do
      {:ok, date} -> date
      _ -> Date.add(Date.utc_today(), -1)
    end
  end
end
