defmodule ViewNinjas.Workers.RefillOrder do
  @moduledoc """
  The one refill call (scope.md §10; build-plan.md M9).

  A customer asks to refill a completed order whose lane was sold with
  `refill: true`. Like `add`, `refill` is sent once from a job and never
  automatically retried, and the job is `unique` on the refill id so a duplicate
  cannot open a second one. A rejected refill stays rejected.

  A panel that is paused, or an order with no supplier id, is left `requested`
  for a person rather than guessed at.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [
      period: 300,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:refill_id]
    ]

  require Logger

  alias ViewNinjas.Orders
  alias ViewNinjas.Orders.{Order, Refill}
  alias ViewNinjas.Suppliers
  alias ViewNinjas.Suppliers.Supplier

  @doc "Queues the single refill call."
  def enqueue(refill_id), do: new(%{refill_id: refill_id}) |> Oban.insert()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"refill_id" => refill_id}}) do
    case Orders.get_refill(refill_id) do
      %Refill{state: :requested} = refill -> run(refill)
      _refill -> :ok
    end
  end

  defp run(%Refill{} = refill) do
    order = Orders.get_order(refill.order_id)

    with %Order{state: :completed} = order <- order,
         %Supplier{} = supplier <- supplier_of(order) do
      request(refill, supplier, order)
    else
      _ -> :ok
    end
  end

  defp supplier_of(%Order{supplier_id: nil}), do: nil
  defp supplier_of(%Order{supplier_id: id}), do: Suppliers.get_supplier(id)

  defp request(refill, supplier, order) do
    cond do
      is_nil(order.supplier_order_id) ->
        Logger.error("refill #{refill.id}: order #{order.id} has no supplier order id")

      Supplier.paused?(supplier) ->
        Logger.warning("refill #{refill.id}: #{supplier.slug} is paused; left for a person")

      not Supplier.capable?(supplier, :refill) ->
        Orders.mark_refill_rejected(refill, "#{supplier.slug} does not implement refill")

      true ->
        send_refill(refill, supplier, order)
    end
  end

  defp send_refill(refill, supplier, order) do
    case Suppliers.V2.refill(supplier, order.supplier_order_id) do
      {:ok, supplier_refill_id} ->
        Orders.mark_refill_requested(refill, supplier_refill_id)

      {:error, reason} ->
        classify(refill, supplier, reason)
    end
  rescue
    error ->
      Logger.warning("refill #{refill.id} left ambiguous: #{inspect(error)}")
      :ok
  end

  defp classify(refill, supplier, reason) do
    if Suppliers.definite_error?(reason) do
      Logger.warning("#{supplier.slug} rejected refill #{refill.id}: #{inspect(reason)}")
      Orders.mark_refill_rejected(refill, Suppliers.error_message(reason))
    else
      Logger.warning("#{supplier.slug} left refill #{refill.id} ambiguous: #{inspect(reason)}")
      :ok
    end
  end
end
