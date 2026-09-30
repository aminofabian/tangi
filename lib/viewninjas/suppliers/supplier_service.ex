defmodule ViewNinjas.Suppliers.SupplierService do
  @moduledoc """
  One raw service from one panel (scope.md §6, §9).

  Everything a panel sells lands here, unfiltered: the piped `external_id`, the
  name, category and type, the USD rate per 1,000 as integer micros, the
  quantity bounds, and whether refill and cancel are offered. Rows are never
  deleted — disappearing from a pull just sets `active: false`, because a lane
  may still be pinned to them.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Suppliers.Supplier

  @type t :: %__MODULE__{}

  schema "supplier_services" do
    belongs_to :supplier, Supplier
    field :external_id, :string
    field :name, :string
    field :category, :string
    field :type, :string
    field :rate_micros, :integer
    field :min, :integer
    field :max, :integer
    field :refill, :boolean, default: false
    field :cancel, :boolean, default: false
    field :active, :boolean, default: true
    field :shortlisted_at, :utc_datetime
    field :last_seen_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(service, attrs) do
    service
    |> cast(attrs, [
      :supplier_id,
      :external_id,
      :name,
      :category,
      :type,
      :rate_micros,
      :min,
      :max,
      :refill,
      :cancel,
      :active,
      :shortlisted_at,
      :last_seen_at
    ])
    |> validate_required([:supplier_id, :external_id])
    |> unique_constraint([:supplier_id, :external_id])
  end
end
