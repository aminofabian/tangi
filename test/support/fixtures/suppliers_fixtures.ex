defmodule ViewNinjas.SuppliersFixtures do
  @moduledoc """
  Test helpers for the supplier boundary.
  """

  alias ViewNinjas.Suppliers
  alias ViewNinjas.Suppliers.Supplier

  def supplier_fixture(attrs \\ %{}) do
    slug = "panel#{System.unique_integer([:positive])}"

    attrs =
      Enum.into(attrs, %{
        slug: slug,
        base_url: "https://#{slug}.test/api/v2",
        api_key: "key-#{slug}",
        capabilities: Supplier.default_capabilities()
      })

    {:ok, supplier} = Suppliers.create_supplier(attrs)
    supplier
  end

  @doc "A service map shaped the way the panel client returns one."
  def service_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      external_id: to_string(System.unique_integer([:positive])),
      name: "IG followers",
      category: "Instagram",
      type: "Default",
      rate_micros: 900_000,
      min: 100,
      max: 10_000,
      refill: true,
      cancel: false
    })
  end
end
