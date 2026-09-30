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
        <div class="vn-filters__intro">
          <div>
            <h2>Inventory</h2>
            <p class="vn-muted">
              {@total} matching · showing {length(@services)} · {@shortlisted_count} shortlisted
            </p>
          </div>
          <button
            :if={@active_filters > 0}
            type="button"
            class="vn-link-btn"
            phx-click="clear_filters"
            id="filters-clear"
          >
            Clear filters
          </button>
        </div>

        <%!-- The filters fold away so the table starts high on the page. The summary
              keeps a count, so an applied filter is never invisible. --%>
        <details class="vn-filters" id="filters-panel">
          <summary class="vn-filters__summary">
            <span>Filters</span>
            <span :if={@active_filters > 0} class="vn-badge vn-badge--ok">
              {@active_filters} on
            </span>
            <span :if={@active_filters == 0} class="vn-filters__hint">
              none — search, panel, category
            </span>
          </summary>

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
        </details>
      </section>

      <%!-- Placement is a drawer, not another page: the inventory stays put behind
            it, and the scrim, the close button or Escape bring it back. The body is
            a short, numbered walk — price, shelf, where it lives, fine tuning — and
            the primary action sticks to the foot, always saying what it will do. --%>
      <div
        :if={@selected}
        class="vn-drawer"
        id="placement-root"
        phx-window-keydown="close_placement"
        phx-key="escape"
      >
        <button
          type="button"
          class="vn-drawer__scrim"
          phx-click="close_placement"
          aria-label="Close placement"
        ></button>

        <aside
          id="placement"
          class="vn-drawer__sheet"
          role="dialog"
          aria-modal="true"
          aria-labelledby="placement-title"
          phx-hook=".Drawer"
          tabindex="-1"
          data-service={@selected.id}
        >
          <span class="vn-drawer__grabber" aria-hidden="true"></span>
          <header class="vn-drawer__head">
            <div class="vn-drawer__headline">
              <p class="vn-drawer__kicker">Place on the shop</p>
              <h2 id="placement-title">{drawer_title(@lane_form, @selected)}</h2>
              <p class="vn-drawer__source">
                <span class="vn-drawer__panel">{@selected.supplier.slug}</span>
                <span aria-hidden="true">·</span>
                <span>#{@selected.external_id}</span>
                <span aria-hidden="true">·</span>
                <span>{clip_title(@selected.name)}</span>
              </p>
            </div>
            <button
              type="button"
              id="placement-close"
              class="vn-drawer__close"
              phx-click="close_placement"
              aria-label={gettext("Close")}
            >
              <.icon name="hero-x-mark" class="vn-drawer__icon" />
            </button>
          </header>

          <.form
            for={@lane_form}
            id="lane-form"
            class="vn-drawer__form"
            phx-change="lane_preview"
            phx-submit="pin"
          >
            <div class="vn-drawer__body">
              <%!-- The grade is chosen by the shelf cards below, not a dropdown. --%>
              <.input type="hidden" field={@lane_form[:grade]} />

              <section class="vn-drawer__price">
                <p class="vn-drawer__amount">{selling(@selected.rate_micros, @params)}</p>
                <p class="vn-muted">selling price per 1,000 — the number a buyer sees</p>

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
              </section>

              <section class="vn-drawer__section">
                <h3 class="vn-drawer__legend">
                  <span class="vn-drawer__step">1</span> Which shelf?
                </h3>
                <p class="vn-muted">
                  A grade is a shelf a buyer chooses between. This service will stand behind the one you pick.
                </p>
                <div class="vn-drawer__grades" id="grade-pick" role="radiogroup" aria-label="Grade">
                  <button
                    :for={grade <- Grade.all()}
                    type="button"
                    id={"grade-#{grade}"}
                    class={[
                      "vn-grade-card",
                      "vn-drawer__grade-card",
                      grade_on?(@lane_form, grade) && "vn-grade-card--on"
                    ]}
                    phx-click="pick_grade"
                    phx-value-grade={grade}
                    aria-pressed={to_string(grade_on?(@lane_form, grade))}
                  >
                    <span class="vn-drawer__grade">
                      <span class="vn-drawer__radio" aria-hidden="true"></span>
                      <span class="vn-grade">{Grade.label(grade)}</span>
                      <span class="vn-drawer__role">{grade_role(grade)}</span>
                    </span>
                    <span class="vn-drawer__grade-blurb">{grade_blurb(grade)}</span>
                    <span
                      :if={grade in grades_for(@on_shop, @selected.id)}
                      class="vn-badge vn-badge--ok"
                    >
                      on the shop
                    </span>
                  </button>
                </div>
              </section>

              <section class="vn-drawer__section">
                <h3 class="vn-drawer__legend">
                  <span class="vn-drawer__step">2</span> Where does it live?
                </h3>
                <.input
                  field={@lane_form[:offer_id]}
                  type="select"
                  label="Add to an offer already on the shop"
                  options={offer_options(@offers)}
                  prompt="None — start a new one"
                />
                <p class="vn-drawer__or"><span>or start a new offer</span></p>
                <div class="vn-form-grid">
                  <.input field={@lane_form[:platform]} label="Platform" placeholder="instagram" />
                  <.input field={@lane_form[:outcome]} label="Outcome" placeholder="views" />
                </div>
                <.input
                  field={@lane_form[:title]}
                  label="Title a buyer sees"
                  placeholder="Instagram views"
                />
              </section>

              <section class="vn-drawer__section">
                <h3 class="vn-drawer__legend">
                  <span class="vn-drawer__step">3</span> Fine tuning
                </h3>
                <.input
                  field={@lane_form[:manual_kes]}
                  type="number"
                  label="Manual price (KSh per 1,000, optional)"
                />
                <p class="vn-muted">
                  Leave it blank to sell at the price above; a manual price is pinned to the shilling.
                </p>
                <.input
                  field={@lane_form[:published]}
                  type="checkbox"
                  label="Show it on the shop right away"
                />
              </section>

              <section :if={@suggestions != []} class="vn-drawer__section">
                <h3 class="vn-drawer__legend">Cheaper elsewhere</h3>
                <p class="vn-muted">Same job, another panel — tap one to swap it in.</p>
                <ul class="vn-drawer__suggest">
                  <li :for={{reason, service} <- @suggestions}>
                    <button
                      type="button"
                      class="vn-drawer__suggest-item"
                      phx-click="select"
                      phx-value-id={service.id}
                      id={"suggest-#{service.id}"}
                    >
                      <span class="vn-drawer__suggest-price">
                        {selling(service.rate_micros, @params)}
                      </span>
                      <span class="vn-drawer__suggest-body">
                        <span class="vn-drawer__suggest-reason">{Suggestions.label(reason)}</span>
                        <span class="vn-drawer__suggest-src">
                          {service.supplier.slug} · {service.external_id}
                        </span>
                      </span>
                    </button>
                  </li>
                </ul>
              </section>
            </div>

            <footer class="vn-drawer__foot">
              <p class="vn-drawer__footnote">{footnote(@lane_form, @offers)}</p>
              <button type="submit" class="vn-button" id="pin-submit">
                {submit_label(@lane_form)}
              </button>
            </footer>
          </.form>
        </aside>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Drawer">
        export default {
          mounted() {
            this.el.focus({preventScroll: true})
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
                    phx-click="select"
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
     |> assign(:offer_form, to_form(%{}, as: "offer"))
     |> assign(:lane_form, to_form(%{}, as: "lane"))
     |> assign(:selected, nil)
     |> assign(:suggestions, [])
     |> assign(:service_limit, @service_limit)
     |> assign(:panels, Catalog.list_panels())
     |> assign(:categories, Catalog.list_categories())
     |> assign(:params, Pricing.current())
     |> refresh_offers()
     |> apply_filters(@blank_filters)}
  end

  @impl true
  def handle_info({:pricing, :changed}, socket) do
    # A super-admin moved a knob; re-quote the inventory with the new parameters.
    {:noreply, socket |> assign(:params, Pricing.current()) |> refresh_services()}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    {:noreply, apply_filters(socket, Map.merge(@blank_filters, params))}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, apply_filters(socket, @blank_filters)}
  end

  # "select" is the row's Place button and every suggestion: it opens the drawer,
  # it never places on its own. Placing is the drawer's confirm — one action.
  def handle_event("select", %{"id" => id}, socket) do
    case Catalog.get_service_with_supplier(id) do
      nil -> {:noreply, put_flash(socket, :error, "That service is gone.")}
      service -> {:noreply, open_placement(socket, service)}
    end
  end

  def handle_event("close_placement", _params, socket) do
    {:noreply, assign(socket, selected: nil, suggestions: [])}
  end

  # Choosing a shelf only arms the confirm; the footer button does the placing.
  def handle_event("pick_grade", %{"grade" => grade}, socket) do
    {:noreply, assign_form(socket, "grade", grade)}
  end

  # The drawer's preview follows the form: the header title and the foot's
  # "Goes into …" line re-render as the operator changes the offer or the title.
  def handle_event("lane_preview", %{"lane" => params}, socket) do
    {:noreply, assign(socket, :lane_form, to_form(params, as: "lane"))}
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

  defp open_placement(socket, service) do
    draft = offer_draft(service)
    current = socket.assigns.lane_form.params
    same? = not is_nil(socket.assigns.selected) and socket.assigns.selected.id == service.id

    assign(socket,
      selected: service,
      suggestions: Suggestions.for_service(service),
      lane_form: to_form(placement_params(current, draft, same?), as: "lane")
    )
  end

  # Re-selecting the same row keeps whatever the operator had typed; a new row
  # starts from the service's draft (platform, outcome, title) and a free shelf.
  defp placement_params(current, draft, true) do
    %{
      "offer_id" => current["offer_id"] || "",
      "grade" => kept_grade(current, draft),
      "platform" => current["platform"] || draft.platform,
      "outcome" => current["outcome"] || draft.outcome,
      "title" => current["title"] || draft.title,
      "manual_kes" => current["manual_kes"] || "",
      "published" => "true"
    }
  end

  defp placement_params(_current, draft, _same?) do
    %{
      "offer_id" => "",
      "grade" => Atom.to_string(free_grade(draft)),
      "platform" => draft.platform,
      "outcome" => draft.outcome,
      "title" => draft.title,
      "manual_kes" => "",
      "published" => "true"
    }
  end

  defp kept_grade(current, draft) do
    case current["grade"] do
      grade when grade in [nil, ""] -> Atom.to_string(free_grade(draft))
      grade -> grade
    end
  end

  # The shelf a fresh placement lands on: the first free grade of the draft's
  # offer, so Cheap by default and Moderate once Cheap is taken.
  defp free_grade(draft) do
    taken =
      case Catalog.get_offer_by_slot(draft.platform, draft.outcome) do
        nil -> []
        offer -> Catalog.get_offer!(offer.id).lanes |> Enum.map(& &1.grade)
      end

    Enum.find(Grade.all(), &(&1 not in taken)) || :cheap
  end

  defp assign_form(socket, key, value) do
    params = Map.put(socket.assigns.lane_form.params, key, value)
    assign(socket, :lane_form, to_form(params, as: "lane"))
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

  # One place to set the filters: the params, the form, the "how many are on"
  # count the folded summary shows, and the rows themselves.
  defp apply_filters(socket, params) do
    socket
    |> assign(:filter_params, params)
    |> assign(:filter_form, to_form(params, as: "filters"))
    |> assign(:active_filters, active_filter_count(params))
    |> refresh_services()
  end

  defp active_filter_count(params) do
    [
      params["q"] not in [nil, ""],
      params["supplier"] not in [nil, ""],
      params["category"] not in [nil, ""],
      params["max_kes"] not in [nil, ""],
      params["sort"] not in [nil, "", "cost"],
      params["refill"] == "true",
      params["cancel"] == "true",
      params["bounds"] == "true",
      params["shortlisted"] == "true"
    ]
    |> Enum.count(& &1)
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

  defp service_label(%{supplier: %{slug: slug}, external_id: external_id, name: name}) do
    "#{slug} #{external_id} — #{name}"
  end

  defp service_label(_), do: "unknown service"

  defp grades_for(grades, id), do: Map.get(grades, id, [])

  defp place_label(grades, id) do
    case grades_for(grades, id) do
      [] -> "Place"
      _placed -> "Place again"
    end
  end

  # The drawer's header names what a buyer will see, and the foot says plainly
  # where it lands and whether it is live — so the confirm button is never a guess.
  defp drawer_title(form, selected) do
    case trim(form[:title].value) do
      "" -> clip_title(selected.name)
      title -> title
    end
  end

  defp submit_label(form) do
    case Grade.parse(form[:grade].value) do
      {:ok, grade} -> "Put on the shop as #{Grade.label(grade)}"
      :error -> "Put on the shop"
    end
  end

  defp footnote(form, offers) do
    destination =
      case offer_at(form, offers) do
        %{title: title} -> "Goes into #{title}"
        nil -> "Starts a new offer: #{title_value(form)}"
      end

    visibility =
      if to_string(form[:published].value) == "true",
        do: "visible to buyers right away",
        else: "hidden until you publish"

    "#{destination} — #{visibility}."
  end

  defp offer_at(form, offers) do
    case form[:offer_id].value do
      id when id in [nil, ""] -> nil
      id -> Enum.find(offers, &(to_string(&1.id) == to_string(id)))
    end
  end

  defp title_value(form) do
    case trim(form[:title].value) do
      "" -> "untitled"
      title -> title
    end
  end

  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(_value), do: ""

  defp grade_on?(form, grade) do
    value = form[:grade].value
    is_binary(value) and value == Atom.to_string(grade)
  end

  defp grade_role(:cheap), do: "Lowest"
  defp grade_role(:moderate), do: "Middle"
  defp grade_role(:quality), do: "Expensive"

  defp grade_blurb(:cheap), do: "The lowest price on this offer."
  defp grade_blurb(:moderate), do: "The middle price."
  defp grade_blurb(:quality), do: "The expensive one — fastest and dearest."

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
