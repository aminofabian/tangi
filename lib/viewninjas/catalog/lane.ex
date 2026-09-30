defmodule ViewNinjas.Catalog.Lane do
  @moduledoc """
  A grade on an offer, backed by one pinned wholesale service (scope.md §6).

  Unique on `(offer, grade)` and published separately from its offer. It carries
  an optional manual KES price — the escape hatch for psychological points. A
  lane whose pinned row changed price, bounds or active flag is flagged
  `stale_at` by the next sync; re-pinning acknowledges it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Catalog.{Grade, Offer}
  alias ViewNinjas.Pricing
  alias ViewNinjas.Suppliers.{Supplier, SupplierService}

  @type t :: %__MODULE__{}

  schema "lanes" do
    belongs_to :offer, Offer
    belongs_to :supplier_service, SupplierService
    field :grade, Ecto.Enum, values: Grade.all()
    field :manual_kes_cents, :integer
    field :published, :boolean, default: false
    field :stale_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(lane, attrs) do
    lane
    |> cast(attrs, [
      :offer_id,
      :grade,
      :supplier_service_id,
      :manual_kes_cents,
      :published,
      :stale_at
    ])
    |> validate_required([:offer_id, :grade, :supplier_service_id])
    |> validate_number(:manual_kes_cents, greater_than: 0)
    |> unique_constraint([:offer_id, :grade])
  end

  @doc "Whether the pinned row changed under this lane and an admin should look."
  @spec stale?(t()) :: boolean()
  def stale?(%__MODULE__{stale_at: nil}), do: false
  def stale?(%__MODULE__{}), do: true

  @doc "Whether the lane's panel is paused, so it takes no new money (scope.md §10)."
  @spec paused?(t() | map()) :: boolean()
  def paused?(%{supplier_service: %{supplier: supplier}}), do: Supplier.paused?(supplier)
  def paused?(_lane), do: false

  @doc "Whether a buyer may start a new order on this lane right now."
  @spec on_sale?(t() | map()) :: boolean()
  def on_sale?(%{published: true} = lane), do: not paused?(lane)
  def on_sale?(_lane), do: false

  @doc """
  The retail price in KES cents for `quantity` units: the manual override when one
  is set, otherwise the flat-margin formula over the pinned rate (scope.md §7),
  all quoted from the given `Params`.

  A manual price is pinned per 1,000 units and scales linearly, rounded to a
  whole shilling; the formula scales exactly.
  """
  @spec retail_kes_cents(t() | map(), Pricing.Params.t(), integer()) :: integer() | nil
  def retail_kes_cents(lane, params, quantity \\ 1000)

  def retail_kes_cents(%{manual_kes_cents: cents}, _params, quantity) when is_integer(cents) do
    cents |> Kernel.*(quantity) |> div(1000) |> round_cents_to_shilling()
  end

  def retail_kes_cents(%{supplier_service: %{rate_micros: rate}}, params, quantity)
      when is_integer(rate),
      do: Pricing.retail_kes_cents(rate, quantity, params)

  def retail_kes_cents(_lane, _params, _quantity), do: nil

  @doc """
  The price to show a person: the shilling quote, or the cent quote when that
  shilling quote would be zero.
  """
  @spec selling_cents(t() | map(), Pricing.Params.t(), integer()) :: integer() | nil
  def selling_cents(lane, params, quantity \\ 1000)

  def selling_cents(%{manual_kes_cents: cents}, _params, quantity) when is_integer(cents) do
    cents |> Kernel.*(quantity) |> div(1000)
  end

  def selling_cents(%{supplier_service: %{rate_micros: rate}}, params, quantity)
      when is_integer(rate),
      do: Pricing.display_kes_cents(rate, quantity, params)

  def selling_cents(_lane, _params, _quantity), do: nil

  defp round_cents_to_shilling(cents), do: div(cents + 50, 100) * 100

  @doc """
  Whether the lane would sell at or under landed cost plus buffer (scope.md §7).
  The publish guardrail refuses such a lane; the workspace warns as you pin.
  """
  @spec underpriced?(t() | map(), Pricing.Params.t()) :: boolean()
  # A hand-set price is compared in shillings, the same way a buyer is charged.
  def underpriced?(%{manual_kes_cents: cents, supplier_service: %{rate_micros: rate}}, params)
      when is_integer(cents) and is_integer(rate) do
    case Pricing.landed_kes_cents(rate, 1000, params) do
      nil -> false
      floor -> cents <= floor
    end
  end

  # The formula already includes the margin. Compare it before shilling
  # rounding, or a sub-shilling service looks free and cannot be published.
  def underpriced?(%{supplier_service: %{rate_micros: rate}}, params) when is_integer(rate) do
    not Pricing.beats_landed?(rate, params)
  end

  def underpriced?(_lane, _params), do: false
end
