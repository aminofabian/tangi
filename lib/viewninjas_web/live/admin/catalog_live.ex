defmodule ViewNinjasWeb.Admin.CatalogLive do
  @moduledoc """
  The catalog workspace (build-plan.md M4, scope.md §9): the whole ingested
  inventory, the shortlist, and the lane being placed.

  Three tiers, and only the third is visible to a buyer — ingested, shortlisted,
  published. Suggestions never publish on their own.
  """
  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Catalog
  alias ViewNinjas.Catalog.{Grade, Lane, Suggestions}
  alias ViewNinjas.Pricing

  @service_limit 50

  @blank_filters %{
    "q" => "",
    "supplier" => "",
    "category" => "",
    "refill" => "false",
    "cancel" => "false",
    "bounds" => "false",
    "shortlisted" => "false",
    "max_kes" => "",
    "sort" => "cost"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Catalog")}
      admin={:catalog}
    >
      <section class="vn-card">
        <h2>Offers</h2>

        <div :for={offer <- @offers} class="vn-offer" id={"offer-#{offer.id}"}>
          <div class="flex items-center justify-between gap-2">
            <strong>{offer.title}</strong>
            <button
              class="vn-button vn-button--muted"
              phx-click="toggle_offer"
              phx-value-id={offer.id}
              id={"offer-publish-#{offer.id}"}
            >
              {if offer.published, do: "Unpublish", else: "Publish"}
            </button>
          </div>
          <p class="vn-muted">{offer.platform} · {offer.outcome}</p>

          <ul class="vn-lanes">
            <li :for={lane <- offer.lanes} id={"lane-#{lane.id}"}>
              <span class="vn-grade">{Grade.label(lane.grade)}</span>
              <span>{service_label(lane.supplier_service)}</span>
              <span class="vn-muted">
                {Pricing.format_kes_cents(Lane.retail_kes_cents(lane, @params))}
              </span>
              <span :if={Lane.stale?(lane)} class="vn-badge vn-badge--warn">stale</span>
              <span :if={Lane.underpriced?(lane, @params)} class="vn-badge vn-badge--warn">
                below landed
              </span>
              <span :if={lane.published} class="vn-badge vn-badge--ok">published</span>
              <button
                class="vn-link-btn"
                phx-click="toggle_lane"
                phx-value-id={lane.id}
                id={"lane-publish-#{lane.id}"}
              >
                {if lane.published, do: "Unpublish", else: "Publish"}
              </button>
              <button
                class="vn-link-btn"
                phx-click="unpin_lane"
                phx-value-id={lane.id}
                id={"lane-unpin-#{lane.id}"}
              >
                Unpin
              </button>
            </li>
          </ul>
          <p :if={offer.lanes == []} class="vn-muted">No lanes yet.</p>
        </div>

        <p :if={@offers == []} class="vn-muted">No offers yet. Create one below.</p>

        <.form for={@offer_form} id="offer-form" phx-submit="new_offer">
          <div class="grid grid-cols-2 gap-2">
            <.input field={@offer_form[:platform]} label="Platform" placeholder="instagram" />
            <.input field={@offer_form[:outcome]} label="Outcome" placeholder="followers" />
          </div>
          <.input field={@offer_form[:title]} label="Title" placeholder="Instagram followers" />
          <button class="vn-button" id="offer-create">Create offer</button>
        </.form>
      </section>

      <section class="vn-card">
        <h2>Inventory</h2>

        <.form for={@filter_form} id="filters" phx-change="filter" phx-submit="filter">
          <.input field={@filter_form[:q]} label="Search" placeholder="follower" />
          <div class="grid grid-cols-2 gap-2">
            <.input
              field={@filter_form[:supplier]}
              type="select"
              label="Panel"
              options={panel_options(@panels)}
              prompt="All panels"
            />
            <.input
              field={@filter_form[:category]}
              type="select"
              label="Category"
              options={@categories}
              prompt="All categories"
            />
          </div>
          <div class="grid grid-cols-2 gap-2">
            <.input field={@filter_form[:max_kes]} type="number" label="Max KSh" />
            <.input
              field={@filter_form[:sort]}
              type="select"
              label="Sort"
              options={[
                {"Cost (low first)", "cost"},
                {"Cost (high first)", "cost_desc"},
                {"Name", "name"},
                {"Panel", "panel"},
                {"Newest", "recent"}
              ]}
            />
          </div>
          <div class="flex gap-3">
            <.input field={@filter_form[:refill]} type="checkbox" label="Refill" />
            <.input field={@filter_form[:cancel]} type="checkbox" label="Cancel" />
            <.input field={@filter_form[:bounds]} type="checkbox" label="Sells 1,000" />
            <.input field={@filter_form[:shortlisted]} type="checkbox" label="Shortlisted only" />
          </div>
        </.form>

        <p class="vn-muted">{@total} matching · showing {@service_limit}</p>

        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>Panel</th>
                <th>ID</th>
                <th>Name</th>
                <th>USD/1k</th>
                <th>KSh</th>
                <th>Refill</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={service <- @services} id={"service-#{service.id}"}>
                <td>{service.supplier.slug}</td>
                <td>{service.external_id}</td>
                <td>
                  {service.name}
                  <span :if={service.shortlisted_at} class="vn-badge">shortlisted</span>
                </td>
                <td>{usd(service.rate_micros)}</td>
                <td>{kes(service.rate_micros, @params)}</td>
                <td>{service.refill}</td>
                <td>
                  <button
                    class="vn-link-btn"
                    phx-click="select"
                    phx-value-id={service.id}
                    id={"select-#{service.id}"}
                  >
                    Select
                  </button>
                  <button
                    class="vn-link-btn"
                    phx-click="shortlist"
                    phx-value-id={service.id}
                    id={"shortlist-#{service.id}"}
                  >
                    {if service.shortlisted_at, do: "Unshortlist", else: "Shortlist"}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <p :if={@services == []} class="vn-muted">
          Nothing matches. Sync a panel from the Suppliers screen first.
        </p>
      </section>

      <section :if={@selected} class="vn-card" id="placement">
        <h2>Placement</h2>
        <p>{service_label(@selected)}</p>
        <p class="vn-muted">
          {usd(@selected.rate_micros)} USD/1k · {kes(@selected.rate_micros, @params)} · min {@selected.min} · max {@selected.max}
        </p>

        <div :if={@suggestions != []} class="vn-suggestions">
          <p class="vn-muted">Suggestions — never published for you:</p>
          <button
            :for={{reason, service} <- @suggestions}
            class="vn-chip"
            phx-click="select"
            phx-value-id={service.id}
            id={"suggest-#{service.id}"}
          >
            {Suggestions.label(reason)}: {service.supplier.slug}
            {service.external_id} · {kes(service.rate_micros, @params)}
          </button>
        </div>

        <.form for={@lane_form} id="lane-form" phx-submit="pin">
          <div class="grid grid-cols-2 gap-2">
            <.input
              field={@lane_form[:offer_id]}
              type="select"
              label="Offer"
              options={offer_options(@offers)}
              prompt="Choose an offer"
            />
            <.input
              field={@lane_form[:grade]}
              type="select"
              label="Grade"
              options={grade_options()}
            />
          </div>
          <.input field={@lane_form[:manual_kes]} type="number" label="Manual price (KSh, optional)" />
          <.input field={@lane_form[:published]} type="checkbox" label="Publish this lane" />
          <button class="vn-button" id="pin-submit">Pin as this grade</button>
        </.form>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Pricing.subscribe()

    {:ok,
     socket
     |> assign(:page_title, gettext("Catalog"))
     |> assign(:filter_params, @blank_filters)
     |> assign(:filter_form, to_form(@blank_filters, as: "filters"))
     |> assign(:offer_form, to_form(%{}, as: "offer"))
     |> assign(:lane_form, to_form(%{}, as: "lane"))
     |> assign(:selected, nil)
     |> assign(:suggestions, [])
     |> assign(:service_limit, @service_limit)
     |> assign(:panels, Catalog.list_panels())
     |> assign(:categories, Catalog.list_categories())
     |> assign(:params, Pricing.current())
     |> refresh_offers()
     |> refresh_services()}
  end

  @impl true
  def handle_info({:pricing, :changed}, socket) do
    # A super-admin moved a knob; re-quote the inventory with the new parameters.
    {:noreply, socket |> assign(:params, Pricing.current()) |> refresh_services()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    {:noreply,
     socket
     |> assign(:filter_params, Map.merge(@blank_filters, params))
     |> assign(:filter_form, to_form(Map.merge(@blank_filters, params), as: "filters"))
     |> refresh_services()}
  end

  def handle_event("select", %{"id" => id}, socket) do
    service = Catalog.get_service_with_supplier(id)

    {:noreply,
     assign(socket,
       selected: service,
       suggestions: if(service, do: Suggestions.for_service(service), else: [])
     )}
  end

  def handle_event("shortlist", %{"id" => id}, socket) do
    case Catalog.get_service(id) do
      nil -> {:noreply, put_flash(socket, :error, "That service is gone.")}
      service -> Catalog.toggle_shortlist(service)
    end

    {:noreply, refresh_services(socket)}
  end

  def handle_event("pin", %{"lane" => params}, socket) do
    case pin_attrs(params, socket) do
      {:ok, attrs} ->
        case Catalog.pin_lane(attrs, socket.assigns.params) do
          {:ok, lane} ->
            {:noreply,
             socket
             |> put_flash(:info, pin_message(attrs, lane))
             |> refresh_offers()}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, changeset_message(changeset))}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("new_offer", %{"offer" => params}, socket) do
    case Catalog.create_offer(params) do
      {:ok, offer} ->
        {:noreply,
         socket
         |> put_flash(:info, "Offer \"#{offer.title}\" created.")
         |> assign(:offer_form, to_form(%{}, as: "offer"))
         |> refresh_offers()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  def handle_event("toggle_offer", %{"id" => id}, socket) do
    case Catalog.get_offer(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That offer is gone.")}

      offer ->
        if offer.published, do: Catalog.unpublish_offer(offer), else: Catalog.publish_offer(offer)
        {:noreply, refresh_offers(socket)}
    end
  end

  def handle_event("toggle_lane", %{"id" => id}, socket) do
    case Catalog.get_lane(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That lane is gone.")}

      lane ->
        if lane.published do
          {:ok, _} = Catalog.unpublish_lane(lane)
          {:noreply, refresh_offers(socket)}
        else
          publish_lane(socket, lane)
        end
    end
  end

  def handle_event("unpin_lane", %{"id" => id}, socket) do
    case Catalog.get_lane(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That lane is gone.")}

      lane ->
        Catalog.unpin_lane(lane)
        {:noreply, refresh_offers(socket)}
    end
  end

  # -- internals ---------------------------------------------------------

  defp pin_attrs(%{"offer_id" => offer_id} = params, socket) do
    selected = socket.assigns.selected

    with {:ok, offer_id} <- parse_int(offer_id, "Choose an offer."),
         {:ok, grade} <- Grade.parse(params["grade"] || ""),
         {:ok, manual} <- parse_manual_kes(params["manual_kes"]) do
      {:ok,
       %{
         offer_id: offer_id,
         grade: grade,
         supplier_service_id: selected.id,
         manual_kes_cents: manual,
         published: params["published"] == "true"
       }}
    end
  end

  defp pin_attrs(_params, _socket), do: {:error, "Choose an offer and a grade."}

  defp parse_int(value, message) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, message}
    end
  end

  defp parse_int(_value, message), do: {:error, message}

  defp parse_manual_kes(value) when value in [nil, ""], do: {:ok, nil}

  defp parse_manual_kes(value) when is_binary(value) do
    case Integer.parse(value) do
      {shillings, ""} when shillings > 0 -> {:ok, shillings * 100}
      _ -> {:error, "The manual price must be a whole number of shillings."}
    end
  end

  defp parse_manual_kes(_value),
    do: {:error, "The manual price must be a whole number of shillings."}

  defp refresh_offers(socket), do: assign(socket, :offers, Catalog.list_offers())

  defp refresh_services(socket) do
    filters = filters_from(socket.assigns.filter_params)
    params = socket.assigns.params

    assign(socket,
      services: Catalog.list_services(filters, limit: @service_limit, params: params),
      total: Catalog.count_services(filters, params: params)
    )
  end

  # Publish a lane, and say plainly when the guardrail refused.
  defp publish_lane(socket, lane) do
    case Catalog.publish_lane(lane, socket.assigns.params) do
      {:ok, _lane} ->
        {:noreply, refresh_offers(socket)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, guardrail_message(lane, reason, socket.assigns.params))}
    end
  end

  defp pin_message(%{published: true}, %{published: true}), do: "Lane pinned and published."

  defp pin_message(%{published: true}, _lane),
    do: "Lane pinned but left unpublished — its price sits at or under landed-plus-buffer."

  defp pin_message(attrs, _lane), do: "#{Grade.label(attrs.grade)} lane pinned."

  defp guardrail_message(lane, reason, params) do
    price = Pricing.format_kes_cents(Lane.retail_kes_cents(lane, params))

    case reason do
      :underpriced ->
        "#{price} sits at or under landed-plus-buffer; that lane cannot be published."

      :unpriceable ->
        "That service has no rate to price from; the lane cannot be published."
    end
  end

  defp filters_from(params) do
    %{
      q: params["q"] || "",
      supplier: blank_to_nil(params["supplier"]),
      category: blank_to_nil(params["category"]),
      refill: params["refill"] == "true",
      cancel: params["cancel"] == "true",
      bounds: params["bounds"] == "true",
      shortlisted: params["shortlisted"] == "true",
      max_kes_cents: max_kes_cents(params["max_kes"]),
      sort: sort_atom(params["sort"])
    }
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp max_kes_cents(value) when value in [nil, ""], do: nil

  defp max_kes_cents(value) do
    case Integer.parse(value) do
      {shillings, ""} when shillings > 0 -> shillings * 100
      _ -> nil
    end
  end

  defp sort_atom("cost_desc"), do: :cost_desc
  defp sort_atom("name"), do: :name
  defp sort_atom("panel"), do: :panel
  defp sort_atom("recent"), do: :recent
  defp sort_atom(_), do: :cost

  defp panel_options(panels), do: Enum.map(panels, &{&1.slug, &1.slug})
  defp offer_options(offers), do: Enum.map(offers, &{&1.title, &1.id})
  defp grade_options, do: Enum.map(Grade.all(), &{Grade.label(&1), Atom.to_string(&1)})

  defp service_label(%{supplier: %{slug: slug}, external_id: external_id, name: name}) do
    "#{slug} #{external_id} — #{name}"
  end

  defp service_label(_), do: "unknown service"

  defp kes(nil, _params), do: "—"

  defp kes(rate_micros, params) do
    rate_micros |> Pricing.retail_kes_cents(1000, params) |> Pricing.format_kes_cents()
  end

  defp usd(nil), do: "—"

  defp usd(rate_micros) do
    rate_micros
    |> Decimal.new()
    |> Decimal.div(1_000_000)
    |> Decimal.round(4)
    |> Decimal.to_string(:normal)
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
