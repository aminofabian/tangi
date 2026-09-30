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

  @platform_words %{
    "instagram" => "instagram",
    "ig" => "instagram",
    "insta" => "instagram",
    "tiktok" => "tiktok",
    "youtube" => "youtube",
    "yt" => "youtube",
    "facebook" => "facebook",
    "fb" => "facebook",
    "twitter" => "twitter",
    "telegram" => "telegram",
    "spotify" => "spotify",
    "whatsapp" => "whatsapp",
    "threads" => "threads",
    "linkedin" => "linkedin",
    "snapchat" => "snapchat",
    "pinterest" => "pinterest",
    "reddit" => "reddit",
    "twitch" => "twitch",
    "discord" => "discord",
    "kwai" => "kwai",
    "likee" => "likee",
    "soundcloud" => "soundcloud",
    "audiomack" => "audiomack",
    "boomplay" => "boomplay"
  }

  @outcome_words %{
    "followers" => "followers",
    "follower" => "followers",
    "likes" => "likes",
    "like" => "likes",
    "views" => "views",
    "view" => "views",
    "comments" => "comments",
    "comment" => "comments",
    "subscribers" => "subscribers",
    "subscriber" => "subscribers",
    "shares" => "shares",
    "share" => "shares",
    "plays" => "plays",
    "play" => "plays",
    "saves" => "saves",
    "members" => "members",
    "member" => "members"
  }

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
      <section class="vn-card vn-catalog-filters">
        <h2>Inventory</h2>
        <p class="vn-muted">
          {@total} matching · showing {length(@services)} · {@shortlisted_count} shortlisted
        </p>

        <.form for={@filter_form} id="filters" phx-change="filter" phx-submit="filter">
          <div class="vn-catalog-filters__grid">
            <.input field={@filter_form[:q]} label="Search" placeholder="follower" />
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
          <div class="vn-catalog-filters__flags">
            <.input field={@filter_form[:refill]} type="checkbox" label="Refill" />
            <.input field={@filter_form[:cancel]} type="checkbox" label="Cancel" />
            <.input field={@filter_form[:bounds]} type="checkbox" label="Sells 1,000" />
            <.input field={@filter_form[:shortlisted]} type="checkbox" label="Shortlisted only" />
          </div>
        </.form>
      </section>

      <section
        :if={@selected}
        class="vn-card"
        id="placement"
        phx-hook=".ScrollIntoView"
        data-service={@selected.id}
      >
        <h2>Put this on the shop</h2>
        <p>{service_label(@selected)}</p>
        <p class="vn-muted">Choose the grade a buyer will see this service as.</p>
        <div class="vn-grades-pick" id="grade-pick">
          <button
            :for={grade <- Grade.all()}
            type="button"
            id={"grade-#{grade}"}
            class={["vn-grade-card", grade_on?(@lane_form, grade) && "vn-grade-card--on"]}
            phx-click="place"
            phx-value-id={@selected.id}
            phx-value-grade={grade}
          >
            <span class="vn-grade">{Grade.label(grade)}</span>
            <span class="vn-muted">{grade_blurb(grade)}</span>
            <span
              :if={grade in grades_for(@on_shop, @selected.id)}
              class="vn-badge vn-badge--ok"
            >
              on the shop
            </span>
          </button>
        </div>
        <%!-- The build-up, not just the answer: the wholesale rate, the FX it is
              converted at, the landed cost and the margin are all on screen, so
              the selling price can be trusted rather than taken on faith. --%>
        <dl class="vn-build" id="placement-price">
          <div>
            <dt>Wholesale</dt>
            <dd>{usd(@selected.rate_micros)} USD / 1,000</dd>
          </div>
          <div>
            <dt>Converted at</dt>
            <dd>KSh {Pricing.format_fx_ppm(@params.fx_ppm)} per USD</dd>
          </div>
          <div>
            <dt>Landed cost</dt>
            <dd>
              {landed(@selected.rate_micros, @params)}
              <span class="vn-muted">incl. {Pricing.format_bps(@params.buffer_bps)} float</span>
            </dd>
          </div>
          <div class="vn-build__sell">
            <dt>Selling price / 1,000</dt>
            <dd>
              <span class="vn-catalog-sell">{selling(@selected.rate_micros, @params)}</span>
              <span class="vn-muted">+ {Pricing.format_bps(@params.margin_bps)} margin</span>
            </dd>
          </div>
        </dl>

        <div :if={@suggestions != []} class="vn-suggestions">
          <p class="vn-muted">Suggestions — never published for you:</p>
          <button
            :for={{reason, service} <- @suggestions}
            type="button"
            class="vn-chip"
            phx-click="select"
            phx-value-id={service.id}
            id={"suggest-#{service.id}"}
          >
            {Suggestions.label(reason)}: {service.supplier.slug}
            {service.external_id} · {selling(service.rate_micros, @params)}
          </button>
        </div>

        <.form for={@lane_form} id="lane-form" phx-submit="pin">
          <div class="vn-form-grid">
            <.input
              field={@lane_form[:offer_id]}
              type="select"
              label="Offer"
              options={offer_options(@offers)}
              prompt="New offer from this service"
            />
            <.input
              field={@lane_form[:grade]}
              type="select"
              label="Grade"
              options={grade_options()}
              prompt="Choose a grade"
            />
          </div>
          <div class="vn-form-grid">
            <.input field={@lane_form[:platform]} label="Platform" placeholder="instagram" />
            <.input field={@lane_form[:outcome]} label="Outcome" placeholder="views" />
            <.input field={@lane_form[:title]} label="Title" placeholder="Instagram views" />
          </div>
          <.input field={@lane_form[:manual_kes]} type="number" label="Manual price (KSh, optional)" />
          <.input field={@lane_form[:published]} type="checkbox" label="Show it on the shop" />
          <button class="vn-button" id="pin-submit">Put on the shop</button>
        </.form>
      </section>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollIntoView">
        export default {
          mounted() {
            this.service = this.el.dataset.service
            this.el.scrollIntoView({block: "start"})
          },
          updated() {
            if (this.el.dataset.service !== this.service) {
              this.service = this.el.dataset.service
              this.el.scrollIntoView({block: "start"})
            }
          }
        }
      </script>

      <section class="vn-card vn-catalog-inventory">
        <div class="vn-scroll">
          <table class="vn-table vn-catalog-table">
            <thead>
              <tr>
                <th>Panel</th>
                <th>ID</th>
                <th>Service</th>
                <th>Selling / 1k</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={service <- @services}
                id={"service-#{service.id}"}
                class={[
                  service.shortlisted_at && "vn-catalog-row--picked",
                  @selected && @selected.id == service.id && "vn-catalog-row--open"
                ]}
              >
                <td>{service.supplier.slug}</td>
                <td>{service.external_id}</td>
                <td>
                  <span class="vn-catalog-name">{service.name}</span>
                  <span :if={service.refill} class="vn-badge">refill</span>
                  <span :if={service.shortlisted_at} class="vn-badge vn-badge--ok">shortlisted</span>
                  <span
                    :for={grade <- grades_for(@on_shop, service.id)}
                    class="vn-badge vn-badge--ok"
                    id={"placed-#{service.id}-#{grade}"}
                  >
                    {Grade.label(grade)}
                  </span>
                </td>
                <td class="vn-catalog-price">
                  <span class="vn-catalog-sell">{selling(service.rate_micros, @params)}</span>
                  <span class="vn-muted">{usd(service.rate_micros)} USD</span>
                </td>
                <td class="vn-catalog-actions">
                  <button
                    type="button"
                    class={[
                      "vn-button vn-button--muted",
                      service.shortlisted_at && "vn-star--on"
                    ]}
                    phx-click="shortlist"
                    phx-value-id={service.id}
                    id={"shortlist-#{service.id}"}
                    aria-pressed={not is_nil(service.shortlisted_at)}
                  >
                    {if service.shortlisted_at, do: "Shortlisted", else: "Shortlist"}
                  </button>
                  <button
                    type="button"
                    class="vn-button"
                    phx-click="place"
                    phx-value-id={service.id}
                    id={"select-#{service.id}"}
                  >
                    {place_label(@on_shop, service.id)}
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

      <section class="vn-card" id="offers">
        <h2>Offers</h2>

        <div :for={offer <- @offers} class="vn-offer" id={"offer-#{offer.id}"}>
          <div class="vn-offer__head">
            <strong>{offer.title}</strong>
            <button
              type="button"
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
                {Pricing.format_selling_cents(Lane.selling_cents(lane, @params))}
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
          <div class="vn-form-grid">
            <.input field={@offer_form[:platform]} label="Platform" placeholder="instagram" />
            <.input field={@offer_form[:outcome]} label="Outcome" placeholder="followers" />
          </div>
          <.input field={@offer_form[:title]} label="Title" placeholder="Instagram followers" />
          <button class="vn-button" id="offer-create">Create offer</button>
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
    case Catalog.get_service_with_supplier(id) do
      nil -> {:noreply, put_flash(socket, :error, "That service is gone.")}
      service -> {:noreply, open_placement(socket, service)}
    end
  end

  def handle_event("place", %{"id" => id} = params, socket) do
    case Catalog.get_service_with_supplier(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That service is gone.")}

      service ->
        grade = params["grade"]
        socket = open_placement(socket, service, grade)

        if grade in [nil, ""] do
          {:noreply, socket}
        else
          place_as(socket, service, grade)
        end
    end
  end

  def handle_event("shortlist", %{"id" => id}, socket) do
    case Catalog.get_service(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "That service is gone.")}

      service ->
        shortlist(socket, service)
    end
  end

  def handle_event("pin", %{"lane" => params}, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, put_flash(socket, :error, "Pick a service first.")}

      service ->
        pin(socket, service, params)
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

  defp open_placement(socket, service, grade \\ nil) do
    draft = offer_draft(service)
    current = socket.assigns.lane_form.params

    same? = socket.assigns.selected && socket.assigns.selected.id == service.id

    assign(socket,
      selected: service,
      suggestions: Suggestions.for_service(service),
      lane_form:
        to_form(
          %{
            "offer_id" => if(same?, do: current["offer_id"], else: "") || "",
            "grade" => grade || if(same?, do: current["grade"], else: "") || "",
            "platform" =>
              if(same?, do: current["platform"], else: draft.platform) || draft.platform,
            "outcome" => if(same?, do: current["outcome"], else: draft.outcome) || draft.outcome,
            "title" => if(same?, do: current["title"], else: draft.title) || draft.title,
            "manual_kes" => if(same?, do: current["manual_kes"], else: "") || "",
            "published" => "true"
          },
          as: "lane"
        )
    )
  end

  defp place_as(socket, service, grade) do
    params = Map.put(socket.assigns.lane_form.params, "grade", grade)

    case put_on_shop(service, params, socket.assigns.params, explicit: true) do
      {:ok, lane, offer} ->
        {:noreply,
         socket
         |> put_flash(:info, placed_message(service, lane, offer, socket.assigns.params))
         |> assign(:lane_form, to_form(params, as: "lane"))
         |> refresh_offers()
         |> refresh_services()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp shortlist(socket, service) do
    case Catalog.toggle_shortlist(service) do
      {:ok, updated} ->
        note = if updated.shortlisted_at, do: "Shortlisted.", else: "Taken off the shortlist."
        {:noreply, socket |> put_flash(:info, note) |> refresh_services()}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  defp pin(socket, service, params) do
    case put_on_shop(service, params, socket.assigns.params, explicit: true) do
      {:ok, lane, offer} ->
        {:noreply,
         socket
         |> put_flash(:info, pinned_note(service, lane, offer, socket.assigns.params))
         |> assign(:lane_form, to_form(params, as: "lane"))
         |> refresh_offers()
         |> refresh_services()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp pinned_note(service, lane, offer, params) do
    if lane.published do
      placed_message(service, lane, offer, params)
    else
      "#{Grade.label(lane.grade)} lane pinned."
    end
  end

  # Place writes a published lane on a published offer. Without both, the shop
  # stays empty — a pinned lane on a draft offer is invisible to a buyer.
  defp put_on_shop(service, params, pricing, opts) do
    publish? = params["published"] == "true"

    with {:ok, manual} <- parse_manual_kes(params["manual_kes"]),
         {:ok, offer} <- ensure_offer(params),
         {:ok, grade} <- chosen_grade(offer, service, params["grade"], opts[:explicit]) do
      attrs = %{
        offer_id: offer.id,
        grade: grade,
        supplier_service_id: service.id,
        manual_kes_cents: manual,
        published: publish?
      }

      case Catalog.pin_lane(attrs, pricing) do
        {:ok, %{published: true} = lane} ->
          publish_pinned(offer, lane)

        {:ok, lane} when publish? ->
          {:error, unpublished_reason(lane, pricing)}

        {:ok, lane} ->
          {:ok, lane, offer}

        {:error, changeset} ->
          {:error, changeset_message(changeset)}
      end
    else
      {:error, message} when is_binary(message) -> {:error, message}
    end
  end

  # A pinned lane is only on the shop when its offer is published too.
  defp publish_pinned(offer, lane) do
    case ensure_published(offer) do
      {:ok, offer} -> {:ok, lane, offer}
      {:error, changeset} -> {:error, changeset_message(changeset)}
    end
  end

  defp ensure_offer(%{"offer_id" => offer_id}) when offer_id not in [nil, ""] do
    case parse_int(offer_id, "Choose an offer.") do
      {:ok, id} ->
        case Catalog.get_offer(id) do
          nil -> {:error, "That offer is gone."}
          _offer -> {:ok, Catalog.get_offer!(id)}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  defp ensure_offer(params) do
    platform = slug(params["platform"])
    outcome = slug(params["outcome"])
    title = String.trim(params["title"] || "")

    cond do
      platform == "" or outcome == "" or title == "" ->
        {:error, "Name the platform, the outcome and the title, then put it on the shop."}

      offer = Catalog.get_offer_by_slot(platform, outcome) ->
        {:ok, Catalog.get_offer!(offer.id)}

      true ->
        case Catalog.create_offer(%{platform: platform, outcome: outcome, title: title}) do
          {:ok, offer} -> {:ok, %{offer | lanes: []}}
          {:error, changeset} -> {:error, changeset_message(changeset)}
        end
    end
  end

  defp ensure_published(%{published: true} = offer), do: {:ok, offer}
  defp ensure_published(offer), do: Catalog.publish_offer(offer)

  defp chosen_grade(offer, service, preferred, explicit?) do
    case Grade.parse(preferred || "cheap") do
      {:ok, preferred} -> {:ok, pick_grade(offer, service, preferred, explicit?)}
      :error -> {:error, "Choose a grade."}
    end
  end

  defp pick_grade(_offer, _service, preferred, true), do: preferred

  defp pick_grade(offer, service, preferred, _explicit?) do
    lanes = offer.lanes || []

    cond do
      lane = Enum.find(lanes, &(&1.supplier_service_id == service.id)) ->
        lane.grade

      not grade_taken?(lanes, preferred) ->
        preferred

      free = Enum.find(Grade.all(), &(not grade_taken?(lanes, &1))) ->
        free

      true ->
        preferred
    end
  end

  defp grade_taken?(lanes, grade), do: Enum.any?(lanes, &(&1.grade == grade))

  defp unpublished_reason(lane, params) do
    reason =
      cond do
        is_nil(Lane.retail_kes_cents(lane, params)) -> :unpriceable
        Lane.underpriced?(lane, params) -> :underpriced
        true -> :underpriced
      end

    guardrail_message(lane, reason, params)
  end

  defp placed_message(service, lane, offer, params) do
    price =
      case parse_manual_display(lane) do
        nil -> selling(service.rate_micros, params)
        manual -> manual
      end

    "On the shop as #{Grade.label(lane.grade)} — #{offer.title}, #{price} / 1,000."
  end

  defp parse_manual_display(%{manual_kes_cents: cents}) when is_integer(cents),
    do: Pricing.format_selling_cents(cents)

  defp parse_manual_display(_lane), do: nil

  defp offer_draft(service) do
    text = "#{service.category} #{service.name}"
    tokens = text |> String.downcase() |> String.split(~r/[^a-z0-9]+/, trim: true)
    platform = Enum.find_value(tokens, &Map.get(@platform_words, &1)) || ""
    outcome = Enum.find_value(tokens, &Map.get(@outcome_words, &1)) || ""

    title =
      case {platform, outcome} do
        {"", _} -> clip_title(service.name)
        {_, ""} -> clip_title(service.name)
        {platform, outcome} -> "#{String.capitalize(platform)} #{outcome}"
      end

    %{platform: platform, outcome: outcome, title: title}
  end

  defp clip_title(nil), do: ""

  defp clip_title(name) do
    name
    |> String.replace(~r/\s*\[.*$/, "")
    |> String.trim()
    |> String.slice(0, 80)
  end

  defp slug(nil), do: ""

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

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

  defp refresh_offers(socket) do
    assign(socket, offers: Catalog.list_offers(), on_shop: Catalog.shop_grades())
  end

  defp refresh_services(socket) do
    filters = filters_from(socket.assigns.filter_params)
    params = socket.assigns.params

    assign(socket,
      services: Catalog.list_services(filters, limit: @service_limit, params: params),
      total: Catalog.count_services(filters, params: params),
      shortlisted_count: Catalog.count_services(%{shortlisted: true}, params: params)
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

  defp grades_for(grades, id), do: Map.get(grades, id, [])

  defp place_label(grades, id) do
    case grades_for(grades, id) do
      [] -> "Place"
      placed -> placed |> Enum.map(&Grade.label/1) |> Enum.join(" · ")
    end
  end

  defp grade_on?(form, grade), do: to_string(form[:grade].value) == Atom.to_string(grade)

  defp grade_blurb(:cheap), do: "The lowest price on this offer."
  defp grade_blurb(:moderate), do: "The middle grade."
  defp grade_blurb(:quality), do: "The fastest and dearest."

  defp selling(nil, _params), do: "—"

  defp selling(rate_micros, params) do
    rate_micros
    |> Pricing.display_kes_cents(1000, params)
    |> Pricing.format_selling_cents()
  end

  defp landed(nil, _params), do: "—"

  defp landed(rate_micros, params) do
    rate_micros
    |> Pricing.landed_display_cents(1000, params)
    |> Pricing.format_selling_cents()
  end

  defp usd(nil), do: "—"

  defp usd(rate_micros) do
    rate_micros
    |> Decimal.new()
    |> Decimal.div(1_000_000)
    |> Decimal.round(4)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
