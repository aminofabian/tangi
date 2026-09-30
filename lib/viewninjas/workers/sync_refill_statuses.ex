defmodule ViewNinjas.Workers.SyncRefillStatuses do
  @moduledoc """
  Every minute: ask each panel about the refills it is still working on
  (scope.md §10; build-plan.md M9).

  A refill that has answered but is not yet `Completed` or `Rejected` keeps its
  `requested` state and is asked again. Reads are safe to repeat, so unlike the
  refill itself this job is retried on a transport error.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias ViewNinjas.Orders
  alias ViewNinjas.Suppliers
  alias ViewNinjas.Suppliers.Supplier

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Orders.list_refills_for_status_sync()
    |> Enum.group_by(& &1.order.supplier)
    |> Enum.each(fn {supplier, refills} -> sync_panel(supplier, refills) end)

    :ok
  end

  defp sync_panel(nil, _refills), do: :ok

  defp sync_panel(%Supplier{} = supplier, refills) do
    if Supplier.capable?(supplier, :refill_status) do
      Enum.each(refills, &poll(supplier, &1))
    end
  end

  defp poll(supplier, refill) do
    case Suppliers.V2.refill_status(supplier, refill.supplier_refill_id) do
      {:ok, status} ->
        {:ok, _refill} = Orders.apply_refill_status(refill, status)

      {:error, reason} ->
        Logger.warning("refill status for #{refill.id} failed: #{inspect(reason)}")
    end
  end
end
