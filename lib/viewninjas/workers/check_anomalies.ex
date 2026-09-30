defmodule ViewNinjas.Workers.CheckAnomalies do
  @moduledoc """
  The anomaly pass (scope.md §11; build-plan.md M10).

  A settled-rate drop, a spike in one failure kind, OTP delivery slipping, a lane
  gone negative, traffic falling off a cliff — each becomes one alert, not a chart
  nobody notices. The checks are pure data in `ViewNinjas.Analysis`; this job only
  raises what it finds.
  """

  use Oban.Worker, queue: :default, max_attempts: 1

  alias ViewNinjas.{Alerts, Analysis}

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Enum.each(Analysis.anomalies(), fn {kind, message} ->
      Alerts.publish(kind, message)
    end)

    :ok
  end
end
