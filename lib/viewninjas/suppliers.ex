defmodule ViewNinjas.Suppliers do
  @moduledoc """
  The supplier boundary (scope.md §5, §9): the panel rows, the raw ingested
  inventory, and the balance probes.

  Ingestion is wholesale and unfiltered — nothing is judged on the way in.
  Outbound calls happen in Oban workers; nothing here is called from a rendered
  page (scope.md §13).
  """
  import Ecto.Query

  alias ViewNinjas.Repo
  alias ViewNinjas.Suppliers.{Supplier, SupplierService}

  @pubsub ViewNinjas.PubSub
  @topic "suppliers"

  # -- suppliers ---------------------------------------------------------

  def list_suppliers do
    Repo.all(from s in Supplier, order_by: [asc: s.slug])
  end

  def get_supplier(id), do: Repo.get(Supplier, id)
  def get_supplier!(id), do: Repo.get!(Supplier, id)
  def get_supplier_by_slug(slug), do: Repo.get_by(Supplier, slug: slug)

  def create_supplier(attrs) do
    %Supplier{}
    |> Supplier.changeset(attrs)
    |> Repo.insert()
  end

  def update_supplier(%Supplier{} = supplier, attrs) do
    supplier
    |> Supplier.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates or updates a panel by slug, so setup is idempotent. An existing row
  keeps its `active` flag unless one is supplied.
  """
  def upsert_supplier(attrs) do
    case get_supplier_by_slug(attrs.slug) do
      nil ->
        create_supplier(attrs)

      supplier ->
        supplier
        |> Supplier.changeset(Map.delete(attrs, :slug))
        |> Repo.update()
    end
  end

  @doc "Records a balance probe result, in micros of USD."
  def record_balance(%Supplier{} = supplier, micros) when is_integer(micros) do
    supplier
    |> Supplier.balance_changeset(%{
      last_balance_micros: micros,
      last_balance_at: DateTime.utc_now(:second)
    })
    |> Repo.update()
  end

  # -- the back office's panel form (scope.md §14) -----------------------

  @capability_flags ~w(services add status balance refill refill_status cancel)

  @doc "The capability keys the back office's panel form edits, in display order."
  @spec capability_flags() :: [String.t()]
  def capability_flags, do: @capability_flags

  @doc "The capability set a brand new v2 panel starts from."
  @spec default_capabilities() :: map()
  def default_capabilities, do: Supplier.default_capabilities()

  @doc """
  Saves a panel's configuration from the back office form.

  The API key is only touched when a value is typed: the form never shows the
  key back, so a blank box means "leave it as it is". Capabilities are rebuilt
  from the form's checkboxes and merged over the panel's existing set, so a key
  the form does not know about survives.
  """
  @spec update_supplier_config(Supplier.t(), map()) ::
          {:ok, Supplier.t()} | {:error, Ecto.Changeset.t() | :invalid_limit}
  def update_supplier_config(%Supplier{} = supplier, params) do
    with {:ok, limit} <- multi_status_limit(params["multi_status_limit"]) do
      supplier
      |> Supplier.changeset(config_attrs(supplier.capabilities, params, limit))
      |> Repo.update()
    end
  end

  @doc """
  Creates a panel row from the back office form — "a fourth panel is a row plus
  a key, not a new integration" (scope.md §14).
  """
  @spec create_supplier_config(map()) ::
          {:ok, Supplier.t()} | {:error, Ecto.Changeset.t() | :invalid_limit}
  def create_supplier_config(params) do
    with {:ok, limit} <- multi_status_limit(params["multi_status_limit"]) do
      params
      |> Map.take(["slug", "base_url", "active"])
      |> Map.put("capabilities", capabilities(%{}, params, limit))
      |> put_key(params)
      |> create_supplier()
    end
  end

  defp config_attrs(existing, params, limit) do
    params
    |> Map.take(["base_url", "active"])
    |> Map.put("capabilities", capabilities(existing, params, limit))
    |> put_key(params)
  end

  # The checkboxes decide the flags the form knows about; anything else the
  # panel already carried is kept.
  defp capabilities(existing, params, limit) do
    flags =
      for flag <- @capability_flags, into: %{} do
        {flag, params["cap_#{flag}"] == "true"}
      end

    (existing || %{})
    |> Map.merge(flags)
    |> put_limit(limit)
  end

  defp put_limit(capabilities, nil), do: capabilities
  defp put_limit(capabilities, limit), do: Map.put(capabilities, "multi_status_limit", limit)

  # A blank key is not a change; a typed one rotates it.
  defp put_key(attrs, %{"api_key" => key}) when is_binary(key) do
    case String.trim(key) do
      "" -> attrs
      trimmed -> Map.put(attrs, "api_key", trimmed)
    end
  end

  defp put_key(attrs, _params), do: attrs

  defp multi_status_limit(nil), do: {:ok, nil}
  defp multi_status_limit(""), do: {:ok, nil}
  defp multi_status_limit(value) when is_integer(value), do: {:ok, value}

  defp multi_status_limit(value) do
    case Integer.parse(String.trim(to_string(value))) do
      {limit, ""} when limit > 0 -> {:ok, limit}
      _other -> {:error, :invalid_limit}
    end
  end

  # -- the float (scope.md §10) ------------------------------------------

  @default_low_balance_micros 5_000_000

  @doc "The USD floor, in micros, a panel's balance may not fall under."
  @spec low_balance_micros() :: non_neg_integer()
  def low_balance_micros do
    :viewninjas
    |> Application.get_env(:suppliers, [])
    |> Keyword.get(:low_balance_micros, @default_low_balance_micros)
  end

  @doc "Whether a panel's balance is under its float."
  @spec low_balance?(integer() | nil) :: boolean()
  def low_balance?(nil), do: false
  def low_balance?(micros) when is_integer(micros), do: micros < low_balance_micros()

  @doc "Whether new placement on this panel is stopped (scope.md §10)."
  @spec paused?(Supplier.t() | nil) :: boolean()
  def paused?(supplier), do: Supplier.paused?(supplier)

  @doc "Stops new placement on a panel and records why, once."
  @spec pause(Supplier.t(), String.t()) :: {:ok, Supplier.t()} | {:error, Ecto.Changeset.t()}
  def pause(%Supplier{paused_at: nil} = supplier, reason) do
    set_paused(supplier, %{
      paused_at: DateTime.utc_now(:second)
    })
    |> tap_broadcast({:paused, supplier.slug, reason})
  end

  def pause(%Supplier{} = supplier, _reason), do: {:ok, supplier}

  @doc "Lets new placement on a panel resume."
  @spec resume(Supplier.t()) :: {:ok, Supplier.t()} | {:error, Ecto.Changeset.t()}
  def resume(%Supplier{paused_at: nil} = supplier), do: {:ok, supplier}

  def resume(%Supplier{} = supplier) do
    set_paused(supplier, %{paused_at: nil})
    |> tap_broadcast({:resumed, supplier.slug})
  end

  defp set_paused(supplier, attrs) do
    supplier
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  defp tap_broadcast({:ok, supplier}, event) do
    broadcast(event)
    {:ok, supplier}
  end

  defp tap_broadcast(other, _event), do: other

  # -- ingestion ---------------------------------------------------------

  @doc """
  Upserts one whole pull for a supplier, atomically.

  Every active row is first marked inactive, then the pull's rows are upserted
  back to active — so a service missing from this pull ends up inactive without
  relying on clock comparison, and a service that reappears comes back. Rows are
  never deleted: a lane may still be pinned to one.

  Returns the `external_id`s whose rate, bounds or active flag actually changed,
  which is what the caller flags stale on the lanes pinned to them (§9).
  """
  @spec ingest_services(Supplier.t(), [ViewNinjas.Suppliers.Panel.service()]) ::
          {:ok,
           %{
             received: non_neg_integer(),
             active: non_neg_integer(),
             deactivated: non_neg_integer(),
             changed: [String.t()]
           }}
  def ingest_services(%Supplier{} = supplier, services) when is_list(services) do
    now = DateTime.utc_now(:second)

    Repo.transact(fn ->
      existing = existing_snapshots(supplier)
      inactive_before = count_inactive_services(supplier)

      from(s in SupplierService, where: s.supplier_id == ^supplier.id and s.active)
      |> Repo.update_all(set: [active: false, updated_at: now])

      services
      |> Enum.map(&row(supplier, &1, now))
      |> Enum.chunk_every(500)
      |> Enum.each(&upsert_chunk/1)

      {:ok,
       %{
         received: length(services),
         active: count_active_services(supplier),
         deactivated: max(count_inactive_services(supplier) - inactive_before, 0),
         changed: changed_external_ids(services, existing)
       }}
    end)
  end

  defp existing_snapshots(%Supplier{} = supplier) do
    from(s in SupplierService,
      where: s.supplier_id == ^supplier.id,
      select: {s.external_id, {s.rate_micros, s.min, s.max, s.active}}
    )
    |> Repo.all()
    |> Map.new()
  end

  # A row is "changed" when it is new, when its rate or bounds moved, when it was
  # inactive and is back, or when it has gone missing from the pull.
  defp changed_external_ids(services, existing) do
    incoming = Map.new(services, &{&1.external_id, {&1.rate_micros, &1.min, &1.max, true}})

    moved =
      for {external_id, snapshot} <- incoming, Map.get(existing, external_id) != snapshot do
        external_id
      end

    withdrawn =
      for {external_id, {_rate, _min, _max, true}} <- existing,
          not Map.has_key?(incoming, external_id) do
        external_id
      end

    moved ++ withdrawn
  end

  defp upsert_chunk(chunk) do
    Repo.insert_all(SupplierService, chunk,
      on_conflict:
        {:replace,
         [
           :name,
           :category,
           :type,
           :rate_micros,
           :min,
           :max,
           :refill,
           :cancel,
           :active,
           :last_seen_at,
           :updated_at
         ]},
      conflict_target: [:supplier_id, :external_id]
    )
  end

  defp row(supplier, service, now) do
    %{
      supplier_id: supplier.id,
      external_id: service.external_id,
      name: service.name,
      category: service.category,
      type: service.type,
      rate_micros: service.rate_micros,
      min: service.min,
      max: service.max,
      refill: service.refill,
      cancel: service.cancel,
      active: true,
      last_seen_at: now,
      inserted_at: now,
      updated_at: now
    }
  end

  # -- reads for the back office ----------------------------------------

  def count_active_services(%Supplier{} = supplier) do
    Repo.one(
      from s in SupplierService,
        where: s.supplier_id == ^supplier.id and s.active,
        select: count(s.id)
    )
  end

  def count_services(%Supplier{} = supplier) do
    Repo.one(from s in SupplierService, where: s.supplier_id == ^supplier.id, select: count(s.id))
  end

  def count_inactive_services(%Supplier{} = supplier) do
    Repo.one(
      from s in SupplierService,
        where: s.supplier_id == ^supplier.id and not s.active,
        select: count(s.id)
    )
  end

  def last_seen_at(%Supplier{} = supplier) do
    Repo.one(
      from s in SupplierService, where: s.supplier_id == ^supplier.id, select: max(s.last_seen_at)
    )
  end

  @doc """
  The newest raw rows, for the M3 admin view.

  Pass `:supplier` to read one panel's feed rather than every panel's.
  """
  def list_recent_services(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    panel = Keyword.get(opts, :supplier)

    query =
      from s in SupplierService,
        join: supplier in assoc(s, :supplier),
        order_by: [desc: s.last_seen_at, asc: s.external_id],
        limit: ^limit,
        preload: [supplier: supplier]

    query =
      case panel do
        nil -> query
        %Supplier{id: id} -> from s in query, where: s.supplier_id == ^id
      end

    Repo.all(query)
  end

  # -- pubsub ------------------------------------------------------------

  @doc "Subscribes the caller to supplier job results."
  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  @doc "Broadcasts a job result to the back office."
  def broadcast(event) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:suppliers, event})
  end

  # -- helpers -----------------------------------------------------------

  @doc """
  Whether a failed call is worth retrying: a rejected key or a body we could not
  read will not fix itself, a transport error or a 5xx might.
  """
  def retryable_error?({:transport, _}), do: true
  def retryable_error?({:http_error, status, _}) when status >= 500, do: true
  def retryable_error?(_), do: false

  @doc """
  Whether a failed call is a definite no rather than an ambiguous one.

  `add` and `refill` are sent once and never retried, so the line between "the
  panel said no" and "we do not know" decides between refunding a customer and
  handing the order to a person (scope.md §5, §10).
  """
  def definite_error?({:api_error, _message}), do: true
  def definite_error?({:http_error, status, _body}), do: status < 500
  def definite_error?(_reason), do: false

  @doc "A short sentence for a normalized client error, safe to show an admin."
  def error_message({:api_error, message}), do: "the panel rejected the key: #{message}"
  def error_message({:http_error, status, _body}), do: "the panel answered HTTP #{status}"
  def error_message({:transport, reason}), do: "could not reach the panel (#{inspect(reason)})"

  def error_message({:invalid_response, _body}),
    do: "the panel answered something we could not read"

  def error_message(other), do: "unexpected error: #{inspect(other)}"

  @doc "Micros of USD as a two-place decimal string, e.g. 1_234_000 -> \"1.23\"."
  def format_usd_micros(nil), do: nil

  def format_usd_micros(micros) when is_integer(micros) do
    micros
    |> Decimal.new()
    |> Decimal.div(1_000_000)
    |> Decimal.round(2)
    |> Decimal.to_string(:normal)
  end
end
