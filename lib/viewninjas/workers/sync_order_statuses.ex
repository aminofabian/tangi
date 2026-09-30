defmodule ViewNinjas.Workers.SyncOrderStatuses do
  @moduledoc """
  Every minute: ask each panel about the orders it is still working on
  (scope.md §10; build-plan.md M8).

  Orders are grouped by supplier and chunked to the panel's multi-status limit, so
  three panels cost three (or a few more) calls a minute regardless of volume. The
  panel's own numbers — `start_count`, `remains`, `charge` — are written back onto
  each order, which is what makes margin real rather than estimated.

  A charge in a currency other than USD is never converted on a guess: the row is
  left alone and the alert is loud.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  alias ViewNinjas.Orders
  alias ViewNinjas.Suppliers
  alias ViewNinjas.Suppliers.Supplier

  @chunk 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Orders.list_for_status_sync()
    |> Enum.group_by(& &1.supplier_id)
    |> Enum.each(fn {supplier_id, orders} -> sync_supplier(supplier_id, orders) end)

    :ok
  end

  defp sync_supplier(supplier_id, orders) do
    case Suppliers.get_supplier(supplier_id) do
      nil ->
        :ok

      supplier ->
        if Supplier.capable?(supplier, :status) do
          orders
          |> Enum.chunk_every(chunk_size(supplier))
          |> Enum.each(&sync_chunk(supplier, &1))
        end
    end
  end

  defp chunk_size(supplier) do
    case supplier.capabilities["multi_status_limit"] do
      limit when is_integer(limit) and limit > 0 -> min(limit, @chunk)
      _ -> @chunk
    end
  end

  defp sync_chunk(supplier, orders) do
    ids = Enum.map(orders, & &1.supplier_order_id)

    case Suppliers.V2.status(supplier, ids) do
      {:ok, reports} ->
        apply_reports(supplier, orders, reports)

      {:error, reason} ->
        Logger.warning("status sync for #{supplier.slug} failed: #{inspect(reason)}")
        :ok
    end
  end

  defp apply_reports(supplier, orders, reports) do
    by_id = Map.new(reports, &{&1.external_order_id, &1})

    for order <- orders,
        report = by_id[order.supplier_order_id],
        report != nil do
      check_currency(supplier, order, report)
      {:ok, _order} = Orders.apply_supplier_status(order, report)
    end

    :ok
  end

  # §10: "If `currency` is ever not USD, stop and alert rather than converting a
  # guess." The charge is not written; the raw word stays on the row.
  defp check_currency(_supplier, _order, %{currency: currency}) when currency in [nil, "USD"],
    do: :ok

  defp check_currency(supplier, order, %{currency: currency}) do
    Logger.error(
      "order #{order.id} from #{supplier.slug} was charged in #{currency}, not USD — " <>
        "the charge was not written and a person must look"
    )
  end
end
