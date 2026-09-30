defmodule ViewNinjas.Workers.SyncSupplierServices do
  @moduledoc """
  Pulls one panel's whole inventory and ingests it (build-plan.md M3,
  scope.md §9).

  Ingestion is wholesale and unfiltered, and a row missing from the pull becomes
  inactive. It runs as a job because the pull can be tens of thousands of rows
  and must never happen on a page load. A rejected key is reported once and not
  retried; a transport error or a 5xx is.
  """
  use Oban.Worker, queue: :default, max_attempts: 3

  alias ViewNinjas.{Alerts, Catalog, Suppliers}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"supplier_id" => id}}) do
    case Suppliers.get_supplier(id) do
      nil -> :ok
      supplier -> sync(supplier)
    end
  end

  defp sync(supplier) do
    case Suppliers.V2.services(supplier) do
      {:ok, services} ->
        {:ok, stats} = Suppliers.ingest_services(supplier, services)

        # A row whose price or bounds moved flags the lanes pinned to it, before
        # the next customer is quoted, and takes them off sale until an admin
        # looks (§9, §10).
        stale = Catalog.flag_stale_lanes(supplier.id, stats.changed)
        unpublished = Catalog.unpublish_stale_lanes(supplier.id, stats.changed)
        alert_stale(supplier, unpublished)

        Suppliers.broadcast(
          {:synced, supplier.slug, Map.merge(stats, %{stale: stale, unpublished: unpublished})}
        )

        :ok

      {:error, reason} ->
        Suppliers.broadcast({:sync_failed, supplier.slug, reason})

        if Suppliers.retryable_error?(reason), do: {:error, reason}, else: :ok
    end
  end

  defp alert_stale(_supplier, 0), do: :ok

  defp alert_stale(supplier, unpublished) do
    Alerts.publish(
      :lanes_unpublished,
      "#{unpublished} lane(s) on #{supplier.slug} came off sale after a price or bounds change",
      %{slug: supplier.slug, lanes: unpublished}
    )
  end
end
