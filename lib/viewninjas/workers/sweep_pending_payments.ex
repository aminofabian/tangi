defmodule ViewNinjas.Workers.SweepPendingPayments do
  @moduledoc """
  Backstop for a dropped callback or a dead poll (docs/malipo-connect.md §9).

  Every minute, re-enqueue `ConfirmPayment` for payments still `pending` past the
  prompt window. `unique` drops the work when a confirmation is already in
  flight, so this is cheap and never prompts twice.

  The upper bound is what keeps it honest: past an hour, a payment the rail never
  resolved is a job for a human, not for the poller — the same "an unknown state
  is first-class" rule the supplier boundary uses (scope.md §5).
  """

  use Oban.Worker, queue: :payments, max_attempts: 3

  alias ViewNinjas.Payments
  alias ViewNinjas.Workers.ConfirmPayment

  # The prompt window; past this the rail is done.
  @stale_after 90
  # Past an hour, stop probing and surface it to a person.
  @give_up_after 3_600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now(:second)
    from = DateTime.add(now, -@give_up_after, :second)
    to = DateTime.add(now, -@stale_after, :second)

    for payment <- Payments.list_stale_pending(from, to, limit: 500) do
      _ = ConfirmPayment.enqueue(payment.id)
    end

    :ok
  end
end
