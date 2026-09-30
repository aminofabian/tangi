defmodule ViewNinjas.Workers.CheckSupplierBalance do
  @moduledoc """
  Probes one panel's balance and records it (build-plan.md M3, M9).

  This is the manual "prove all three keys work" trigger from admin, and the
  float check (scope.md §10): a panel under its configured floor is paused and
  raised as an alert, so a lane pinned to it stops taking money **before** a
  customer pays rather than failing after. A panel back above the floor resumes.

  A rejected key is reported once and not retried; a transport error or a 5xx is.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias ViewNinjas.{Alerts, Suppliers}
  alias ViewNinjas.Suppliers.Supplier

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"supplier_id" => id}}) do
    case Suppliers.get_supplier(id) do
      nil -> :ok
      supplier -> check(supplier)
    end
  end

  defp check(supplier) do
    case Suppliers.V2.balance(supplier) do
      {:ok, micros} ->
        {:ok, recorded} = Suppliers.record_balance(supplier, micros)
        Suppliers.broadcast({:balance, supplier.slug, micros})
        evaluate_float(recorded, micros)
        :ok

      {:error, reason} ->
        Suppliers.broadcast({:balance_failed, supplier.slug, reason})

        if Suppliers.retryable_error?(reason), do: {:error, reason}, else: :ok
    end
  end

  defp evaluate_float(%Supplier{} = supplier, micros) do
    if Suppliers.low_balance?(micros), do: pause(supplier, micros), else: resume(supplier)
  end

  defp pause(%Supplier{paused_at: nil} = supplier, micros) do
    reason = "balance #{Suppliers.format_usd_micros(micros)} USD is under the float"
    {:ok, _paused} = Suppliers.pause(supplier, reason)

    Alerts.publish(:supplier_paused, "#{supplier.slug} paused: #{reason}", %{
      slug: supplier.slug
    })
  end

  defp pause(%Supplier{}, _micros), do: :ok

  defp resume(%Supplier{paused_at: nil}), do: :ok

  defp resume(%Supplier{} = supplier) do
    {:ok, _resumed} = Suppliers.resume(supplier)

    Alerts.publish(:supplier_resumed, "#{supplier.slug} is back above its float", %{
      slug: supplier.slug
    })
  end
end
