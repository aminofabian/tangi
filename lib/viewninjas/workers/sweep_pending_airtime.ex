defmodule ViewNinjas.Workers.SweepPendingAirtime do
  @moduledoc """
  Backstop for a lost confirmation (scope: `docs/instalipa-airtime.md` §12).

  Every minute, re-enqueue the confirming status query for anything still
  `submitted` past a short grace period. Past an hour the rail is not going to
  answer on its own, so the row is parked as `needs_review` for a person to
  reconcile against the portal — the same "an unknown state is first-class" rule
  the supplier boundary uses (scope.md §5).

  `unique` on the confirming job drops any probe already in flight, so this is
  cheap and never asks twice.
  """

  use Oban.Worker, queue: :airtime, max_attempts: 3

  alias ViewNinjas.Airtime
  alias ViewNinjas.Workers.ConfirmAirtime

  # Give the confirming job's own window a chance before butting in.
  @recheck_after 60
  @give_up_after 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now(:second)

    for order <- Airtime.list_pollable() do
      age = DateTime.diff(now, order.inserted_at, :second)

      cond do
        age > @give_up_after -> Airtime.mark_needs_review(order, "no final status within an hour")
        age > @recheck_after -> ConfirmAirtime.enqueue(order.id)
        true -> :ok
      end
    end

    :ok
  end
end
