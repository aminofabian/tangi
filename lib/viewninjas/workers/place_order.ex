defmodule ViewNinjas.Workers.PlaceOrder do
  @moduledoc """
  The one `add` (scope.md §5, §10; build-plan.md M8).

  `add` is not idempotent, and this API has no trustworthy "orders I just placed"
  to reconcile against. So the intent is persisted first, `add` is sent exactly
  once with a short timeout, and it is **never** automatically retried:

    * `{order: id}` → `placed`
    * a definite API error → `failed`, and the wallet is credited back
    * a timeout, a 5xx or a garbled body → `needs_review`, for a person to reconcile

  The job is `unique` on the order id and only ever touches a `paid` order, so a
  duplicate job is a no-op rather than a second order.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 1,
    unique: [
      period: 300,
      states: [:available, :scheduled, :executing, :retryable],
      keys: [:order_id]
    ]

  require Logger

  alias ViewNinjas.Orders
  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Suppliers
  alias ViewNinjas.Suppliers.{Supplier, SupplierService}

  @doc "Queues placement for a paid order."
  def enqueue(order_id), do: new(%{order_id: order_id}) |> Oban.insert()

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    case Orders.get_order_with_lane(order_id) do
      nil -> :ok
      %Order{} = order -> place(order)
    end
  end

  # Only a paid order is placed. Anything else — already placing, already placed,
  # failed, refunded — is left exactly as it is.
  defp place(%Order{state: :paid} = order) do
    case pinned_service(order) do
      nil ->
        # Nothing was sent, but our own data is wrong: a person should look, and
        # we should not refund on a guess.
        Orders.mark_needs_review(order, "the order's pinned service could not be resolved")

      service ->
        persist_intent_and_add(order, service)
    end
  end

  defp place(%Order{}), do: :ok

  defp pinned_service(%Order{
         lane: %{supplier_service: %SupplierService{supplier: %Supplier{}} = service}
       }) do
    service
  end

  defp pinned_service(%Order{}), do: nil

  defp persist_intent_and_add(order, service) do
    supplier = service.supplier
    {:ok, placing} = Orders.mark_placing(order, supplier.id, service.id)

    if Supplier.capable?(supplier, :add) do
      send_add(placing, supplier, service)
    else
      # We never sent anything, so this is a definite failure and the money goes back.
      Orders.mark_failed_and_refund(placing, "#{supplier.slug} does not implement add")
    end
  end

  defp send_add(placing, supplier, service) do
    case Suppliers.V2.add(supplier, service.external_id, placing.link, placing.quantity) do
      {:ok, supplier_order_id} ->
        Orders.mark_placed(placing, supplier_order_id)

      {:error, reason} ->
        classify(placing, supplier, reason)
    end
  rescue
    # Anything unexpected after the request went out is ambiguous, so it becomes a
    # person's job — never a second `add`.
    error -> Orders.mark_needs_review(placing, "unexpected error: #{inspect(error)}")
  end

  defp classify(placing, supplier, reason) do
    if Suppliers.definite_error?(reason) do
      Logger.warning("#{supplier.slug} rejected order #{placing.id}: #{inspect(reason)}")
      Orders.mark_failed_and_refund(placing, Suppliers.error_message(reason))
    else
      Logger.warning("#{supplier.slug} left order #{placing.id} ambiguous: #{inspect(reason)}")
      Orders.mark_needs_review(placing, Suppliers.error_message(reason))
    end
  end
end
