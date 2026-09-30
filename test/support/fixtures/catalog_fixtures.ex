defmodule ViewNinjas.CatalogFixtures do
  @moduledoc """
  Test helpers for the catalog: offers, ingested services to pin, and the lanes
  that join them (build-plan.md M4).
  """

  alias ViewNinjas.Catalog
  alias ViewNinjas.Repo
  alias ViewNinjas.Suppliers.SupplierService
  alias ViewNinjas.SuppliersFixtures

  @doc "An offer. Defaults are unique so a test may create more than one."
  def offer_fixture(attrs \\ %{}) do
    suffix = System.unique_integer([:positive])

    attrs =
      Enum.into(attrs, %{
        platform: "platform#{suffix}",
        outcome: "outcome#{suffix}",
        title: "Offer #{suffix}"
      })

    {:ok, offer} = Catalog.create_offer(attrs)
    offer
  end

  @doc """
  An ingested service, with its supplier preloaded.

  Pass `:supplier` to hang several services off one panel; otherwise a fresh
  panel is created for each service.
  """
  def service_fixture(attrs \\ %{}) do
    supplier = Map.get(attrs, :supplier) || SuppliersFixtures.supplier_fixture()
    service = attrs |> Map.drop([:supplier]) |> SuppliersFixtures.service_attrs()

    {:ok, _stats} = ViewNinjas.Suppliers.ingest_services(supplier, [service])

    SupplierService
    |> Repo.get_by!(supplier_id: supplier.id, external_id: service.external_id)
    |> Repo.preload(:supplier)
  end

  @doc "A lane pinned to `:offer` and `:service` (both created when absent)."
  def lane_fixture(attrs \\ %{}) do
    offer = Map.get(attrs, :offer) || offer_fixture()
    service = Map.get(attrs, :service) || service_fixture()

    attrs =
      attrs
      |> Map.drop([:offer, :service])
      |> Enum.into(%{
        offer_id: offer.id,
        grade: :cheap,
        supplier_service_id: service.id
      })

    {:ok, lane} = Catalog.pin_lane(attrs)
    Repo.preload(lane, :supplier_service)
  end

  @doc """
  A published offer carrying one published lane — what the market shows.

  Pass `:grade` to pick the grade, `:service_attrs` to shape the pinned row,
  and any `offer_fixture/1` attributes to name it.
  """
  def published_offer_fixture(attrs \\ %{}) do
    grade = Map.get(attrs, :grade, :cheap)
    service_attrs = Map.get(attrs, :service_attrs, %{})

    offer =
      attrs
      |> Map.drop([:grade, :service_attrs])
      |> Map.put_new(:published, true)
      |> offer_fixture()

    service = service_fixture(service_attrs)

    {:ok, _lane} =
      Catalog.pin_lane(%{
        offer_id: offer.id,
        grade: grade,
        supplier_service_id: service.id,
        published: true
      })

    Catalog.get_offer!(offer.id)
  end
end
