defmodule ViewNinjas.Catalog do
  @moduledoc """
  Offers, lanes, and the workspace an admin curates them in (scope.md §9).

  Three tiers — ingested, shortlisted, published — are the whole selection
  model, and only the third is visible to a buyer. Shortlisting is a reading
  aid; pinning a service as a grade and publishing the lane is the decision.
  """
  import Ecto.Query

  alias ViewNinjas.Catalog.{Grade, Lane, Offer}
  alias ViewNinjas.Pricing
  alias ViewNinjas.Repo
  alias ViewNinjas.Suppliers
  alias ViewNinjas.Suppliers.SupplierService

  # The quantity the catalog quotes at, so a row is only suitable when its
  # min/max contains it (scope.md §9 "filter by … bounds").
  @quote_quantity 1000

  # -- offers ------------------------------------------------------------

  @doc """
  Offers with their lanes and pinned services.

  ## Options

    * `:published` - `true` to return only published offers.
  """
  def list_offers(opts \\ []) do
    Offer
    |> maybe_published(opts)
    |> order_by([o], asc: o.sort, asc: o.title)
    |> preload(lanes: [supplier_service: :supplier])
    |> Repo.all()
    |> Enum.map(&sort_lanes/1)
  end

  def get_offer!(id) do
    Offer
    |> preload(lanes: [supplier_service: :supplier])
    |> Repo.get!(id)
    |> sort_lanes()
  end

  def get_offer(id), do: Repo.get(Offer, id)

  # -- the market --------------------------------------------------------

  @doc """
  Published offers that carry at least one published lane, for a buyer.

  An offer with no published lane is not shown at all (scope.md §11) — the
  market never invents a price. Each offer's lanes are its published ones, in
  grade order. Pass `:platform` to narrow to one chip.
  """
  def list_market_offers(opts \\ []) do
    Offer
    |> where([o], o.published)
    |> maybe_platform(Keyword.get(opts, :platform))
    |> order_by([o], asc: o.sort, asc: o.title)
    |> preload(lanes: [supplier_service: :supplier])
    |> Repo.all()
    |> Enum.map(&with_published_lanes/1)
    |> Enum.reject(&(&1.lanes == []))
  end

  @doc "The platforms that currently have something for sale."
  def list_market_platforms do
    list_market_offers() |> Enum.map(& &1.platform) |> Enum.uniq() |> Enum.sort()
  end

  @doc "A published offer with at least one published lane, or nil."
  def get_market_offer(id) when is_integer(id) do
    case Repo.get(Offer, id) do
      nil ->
        nil

      offer ->
        offer
        |> Repo.preload(lanes: [supplier_service: :supplier])
        |> with_published_lanes()
        |> present_if_lanes()
    end
  end

  def get_market_offer(_id), do: nil

  @doc "The lowest published price on an offer, in KES cents, or nil."
  def from_kes_cents(%Offer{lanes: lanes}, params) do
    lanes
    |> Enum.map(&Lane.retail_kes_cents(&1, params))
    |> Enum.reject(&is_nil/1)
    |> Enum.min(fn -> nil end)
  end

  defp maybe_platform(query, nil), do: query
  defp maybe_platform(query, ""), do: query
  defp maybe_platform(query, platform), do: where(query, [o], o.platform == ^platform)

  # Only published lanes, cheapest grade first; an unpublished offer carries
  # none, so it drops out of the market entirely.
  defp with_published_lanes(%Offer{published: false} = offer), do: %{offer | lanes: []}

  defp with_published_lanes(%Offer{} = offer) do
    lanes =
      offer.lanes
      |> Enum.filter(& &1.published)
      |> Enum.sort_by(&Grade.rank(&1.grade))

    %{offer | lanes: lanes}
  end

  defp present_if_lanes(%Offer{lanes: []}), do: nil
  defp present_if_lanes(offer), do: offer

  def create_offer(attrs) do
    %Offer{}
    |> Offer.changeset(attrs)
    |> Repo.insert()
  end

  def change_offer(offer, attrs \\ %{}), do: Offer.changeset(offer, attrs)

  def update_offer(offer, attrs) do
    offer
    |> Offer.changeset(attrs)
    |> Repo.update()
  end

  def publish_offer(offer), do: update_offer(offer, %{published: true})
  def unpublish_offer(offer), do: update_offer(offer, %{published: false})

  # -- lanes -------------------------------------------------------------

  @doc """
  Pins a service as a grade on an offer, or re-pins the grade that is there.

  Re-pinning also clears the stale flag: an admin has looked at the change and
  accepted it (§9). A lane is always saved *unpublished*: publishing is the
  guarded step below (`publish_lane/2`), never a side effect of the upsert.

  When the caller asked to publish (`published: true`), the guardrail decides —
  so the returned lane's `published` flag is the truth about what happened.
  """
  def pin_lane(attrs, params \\ nil) do
    params = params || Pricing.current()
    wants_publish = Map.get(attrs, :published) == true

    attrs =
      attrs
      |> Map.put(:stale_at, nil)
      |> Map.put(:published, false)

    case upsert_lane(attrs) do
      {:ok, lane} -> maybe_publish_pinned(lane, wants_publish, params)
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp upsert_lane(attrs) do
    case Repo.get_by(Lane, offer_id: attrs[:offer_id], grade: attrs[:grade]) do
      nil -> %Lane{} |> Lane.changeset(attrs) |> Repo.insert()
      lane -> lane |> Lane.changeset(attrs) |> Repo.update()
    end
  end

  defp maybe_publish_pinned(lane, false, _params), do: {:ok, lane}

  defp maybe_publish_pinned(lane, true, params) do
    case publish_lane(lane, params) do
      {:ok, published} -> {:ok, published}
      # The guardrail kept it unpublished; the pin itself still stands.
      {:error, _reason} -> {:ok, lane}
    end
  end

  def get_lane(id), do: Repo.get(Lane, id)

  def get_lane!(id), do: Repo.get!(Lane, id)

  def change_lane(lane, attrs \\ %{}), do: Lane.changeset(lane, attrs)

  def update_lane(lane, attrs) do
    lane
    |> Lane.changeset(Map.put(attrs, :stale_at, nil))
    |> Repo.update()
  end

  @doc """
  Publishes a lane, unless it would sell at or under landed-plus-buffer (§7).

  The pinned service is loaded to price the lane. Returns `{:error, :underpriced}`
  when the retail price sits at or under the floor, and `{:error, :unpriceable}`
  when the pinned row has no rate to price from.
  """
  def publish_lane(lane, params \\ nil) do
    params = params || Pricing.current()
    lane = Repo.preload(lane, :supplier_service)

    cond do
      is_nil(Lane.retail_kes_cents(lane, params)) -> {:error, :unpriceable}
      Lane.underpriced?(lane, params) -> {:error, :underpriced}
      true -> lane |> Lane.changeset(%{published: true, stale_at: nil}) |> Repo.update()
    end
  end

  def unpublish_lane(lane), do: lane |> Lane.changeset(%{published: false}) |> Repo.update()

  @doc "Unpins a lane from its offer."
  def unpin_lane(lane), do: Repo.delete(lane)

  @doc """
  Flags every lane pinned to one of `external_ids` on `supplier_id` as stale.

  Called by the sync when a row's price, bounds or active flag actually changed;
  it is the whole point of §9's "flagged stale before the next customer is
  quoted".
  """
  @spec flag_stale_lanes(integer(), [String.t()]) :: non_neg_integer()
  def flag_stale_lanes(_supplier_id, []), do: 0

  def flag_stale_lanes(supplier_id, external_ids) when is_list(external_ids) do
    {count, _} =
      from(l in Lane,
        join: s in assoc(l, :supplier_service),
        where: s.supplier_id == ^supplier_id and s.external_id in ^external_ids
      )
      |> Repo.update_all(set: [stale_at: DateTime.utc_now(:second)])

    count
  end

  @doc """
  Takes the lanes pinned to changed rows off sale (scope.md §9, §10).

  A lane whose service moved under it must not be quoted at the old price, so it
  is unpublished until an admin re-pins it — which also clears the stale flag.
  """
  @spec unpublish_stale_lanes(integer(), [String.t()]) :: non_neg_integer()
  def unpublish_stale_lanes(_supplier_id, []), do: 0

  def unpublish_stale_lanes(supplier_id, external_ids) when is_list(external_ids) do
    {count, _} =
      from(l in Lane,
        join: s in assoc(l, :supplier_service),
        where: s.supplier_id == ^supplier_id and s.external_id in ^external_ids and l.published
      )
      |> Repo.update_all(set: [published: false])

    count
  end

  # -- the workspace -----------------------------------------------------

  @doc "The default filter set for the catalog workspace."
  def default_filters do
    %{
      q: "",
      supplier: nil,
      category: nil,
      refill: false,
      cancel: false,
      bounds: false,
      shortlisted: false,
      max_kes_cents: nil,
      sort: :cost
    }
  end

  @doc """
  The ingested inventory, filtered and sorted for the workspace.

  Filters are pure SQL, including the computed KES ceiling, which mirrors
  `ViewNinjas.Pricing.retail_kes_cents/3` exactly (a test asserts they agree).
  """
  def list_services(filters \\ %{}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    params = params_from(opts)

    SupplierService
    |> join(:inner, [s], sup in assoc(s, :supplier))
    |> apply_filters(filters, params)
    |> apply_sort(Map.get(filters, :sort, :cost))
    |> limit(^limit)
    |> preload([s, sup], supplier: sup)
    |> Repo.all()
  end

  def count_services(filters \\ %{}, opts \\ []) do
    params = params_from(opts)

    SupplierService
    |> join(:inner, [s], sup in assoc(s, :supplier))
    |> apply_filters(filters, params)
    |> select([s, _sup], count(s.id))
    |> Repo.one()
  end

  defp params_from(opts), do: Keyword.get(opts, :params) || Pricing.current()

  @doc "The categories present in the inventory, for the filter dropdown."
  def list_categories do
    SupplierService
    |> where([s], not is_nil(s.category))
    |> distinct(true)
    |> select([s], s.category)
    |> order_by([s], asc: s.category)
    |> Repo.all()
  end

  def list_panels, do: Suppliers.list_suppliers()

  def shortlist(%SupplierService{} = service) do
    service
    |> Ecto.Changeset.change(shortlisted_at: DateTime.utc_now(:second))
    |> Repo.update()
  end

  def unshortlist(%SupplierService{} = service) do
    service
    |> Ecto.Changeset.change(shortlisted_at: nil)
    |> Repo.update()
  end

  def toggle_shortlist(%SupplierService{shortlisted_at: nil} = service), do: shortlist(service)
  def toggle_shortlist(%SupplierService{} = service), do: unshortlist(service)

  def get_service(id), do: Repo.get(SupplierService, id)

  def get_service_with_supplier(id) do
    SupplierService
    |> preload(:supplier)
    |> Repo.get(id)
  end

  defp sort_lanes(%Offer{} = offer) do
    %{offer | lanes: Enum.sort_by(offer.lanes, &Grade.rank(&1.grade))}
  end

  defp maybe_published(query, opts) do
    if Keyword.get(opts, :published, false) do
      where(query, [o], o.published)
    else
      query
    end
  end

  # -- filters -----------------------------------------------------------

  defp apply_filters(query, filters, params) do
    query
    |> filter_search(filters[:q])
    |> filter_supplier(filters[:supplier])
    |> filter_category(filters[:category])
    |> filter_flag(:refill, filters[:refill])
    |> filter_flag(:cancel, filters[:cancel])
    |> filter_bounds(filters[:bounds])
    |> filter_shortlisted(filters[:shortlisted])
    |> filter_max_kes(filters[:max_kes_cents], params)
  end

  defp filter_search(query, q) when q in [nil, ""], do: query

  defp filter_search(query, q) do
    like = "%#{q}%"
    where(query, [s, _sup], ilike(s.name, ^like) or ilike(s.external_id, ^like))
  end

  defp filter_supplier(query, nil), do: query
  defp filter_supplier(query, ""), do: query
  defp filter_supplier(query, slug), do: where(query, [s, sup], sup.slug == ^slug)

  defp filter_category(query, category) when category in [nil, ""], do: query
  defp filter_category(query, category), do: where(query, [s, _sup], s.category == ^category)

  defp filter_flag(query, field, true), do: where(query, [s, _sup], field(s, ^field) == true)
  defp filter_flag(query, _field, _), do: query

  # Only rows that can actually sell the quantity we quote at.
  defp filter_bounds(query, true),
    do: where(query, [s, _sup], s.min <= ^@quote_quantity and s.max >= ^@quote_quantity)

  defp filter_bounds(query, _), do: query

  defp filter_shortlisted(query, true), do: where(query, [s, _sup], not is_nil(s.shortlisted_at))
  defp filter_shortlisted(query, _), do: query

  # The SQL twin of Pricing.retail_kes_cents/3: the same arithmetic, truncated at
  # every step so the two cannot disagree. An equivalence test in
  # catalog_test.exs holds this to the Elixir version.
  @retail_filter_sql """
  trunc(
    trunc(
      trunc(
        trunc(?::numeric * ?::numeric / 1000) * ?::numeric / 1000000
      ) * (?::numeric + 10000) / 10000
    ) * (?::numeric + 10000) / 10000
    / 1000000 + 0.5
  ) * 100 <= ?
  """

  defp filter_max_kes(query, nil, _params), do: query

  defp filter_max_kes(query, max_cents, params) when is_integer(max_cents) and max_cents > 0 do
    where(
      query,
      [s, _sup],
      fragment(
        @retail_filter_sql,
        s.rate_micros,
        ^1000,
        ^params.fx_ppm,
        ^params.buffer_bps,
        ^params.margin_bps,
        ^max_cents
      )
    )
  end

  defp filter_max_kes(query, _max_cents, _params), do: query

  defp apply_sort(query, :cost_desc), do: order_by(query, [s, _sup], desc: s.rate_micros)
  defp apply_sort(query, :name), do: order_by(query, [s, _sup], asc: s.name)
  defp apply_sort(query, :panel), do: order_by(query, [s, sup], asc: sup.slug, asc: s.rate_micros)
  defp apply_sort(query, :recent), do: order_by(query, [s, _sup], desc: s.last_seen_at)

  defp apply_sort(query, _cost_asc),
    do: order_by(query, [s, _sup], asc: s.rate_micros, asc: s.external_id)
end
