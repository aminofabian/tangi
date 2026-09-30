defmodule ViewNinjas.Workers.WeeklyDigest do
  @moduledoc """
  Sends the Sunday digest to the super-admin (scope.md §11; build-plan.md M10).

  Composed and sent by `ViewNinjas.Digest`; this job only decides when. With no
  super-admin to send to it is a quiet no-op.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias ViewNinjas.Digest

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    case Digest.deliver(digest_day(args)) do
      0 ->
        Logger.info("weekly digest: no super-admin to send to")
        :ok

      count ->
        Logger.info("weekly digest sent to #{count} super-admin(s)")
        :ok
    end
  end

  defp digest_day(%{"at" => day}) when is_binary(day) do
    case Date.from_iso8601(day) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  defp digest_day(_args), do: Date.utc_today()
end
