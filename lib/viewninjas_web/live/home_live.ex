defmodule ViewNinjasWeb.HomeLive do
  @moduledoc """
  The home surface (scope.md §11, §12).

  Two routes share it. `/` is the **market** to anyone signed out and the
  **buyer dashboard** once signed in; `/shop` is the market to everyone, signed
  in or not. The market is public and real: it shows published offers with a
  from-price pulled from a published lane, and an offer with no published lane
  is not shown at all.

  The dashboard's wallet card, stats strip and orders list are stubbed; they fill
  in as M7 (wallet), M8 (orders) and M9 (refunds, refills) land.
  """
  use ViewNinjasWeb, :live_view

  alias ViewNinjas.{Catalog, Orders, Pricing, Wallet}
  alias ViewNinjas.Catalog.Grade
  alias ViewNinjasWeb.{Analytics, SEO}

  @impl true
  def mount(_params, session, socket) do
    market? = socket.assigns.live_action == :shop or not signed_in?(socket)

    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:params, Pricing.current())
     |> assign(:section, section(socket))
     |> assign(:page_title, page_title(socket))
     |> assign(:market?, market?)
     |> assign(:meta_title, market_meta_title(market?))
     |> assign(:page_description, market_description(market?))
     |> assign(:page_robots, if(market?, do: "index, follow", else: "noindex, nofollow"))
     |> assign(:stats, [])
     |> assign(:platform, nil)
     |> assign(:offers, [])
     |> assign(:platforms, [])
     |> maybe_load_market()}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    Analytics.record_page_view(socket, uri)

    # The dashboard is the same route (`/`) as the public market, but signed in
    # it is nobody's landing page, so it carries no canonical URL.
    canonical = if socket.assigns.market?, do: SEO.canonical_url(uri), else: nil

    {:noreply, assign(socket, :canonical_url, canonical)}
  end

  @impl true
  def handle_event("filter", %{"platform" => platform}, socket) do
    platform = if platform in [nil, "", "all"], do: nil, else: platform

    {:noreply,
     socket
     |> assign(:platform, platform)
     |> assign(:offers, Catalog.list_market_offers(platform: platform))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      section={@section}
      title={@page_title}
    >
      <%= if @market? do %>
        <.market
          offers={@offers}
          platforms={@platforms}
          platform={@platform}
          params={@params}
          signed_in?={signed_in?(@current_scope)}
        />
      <% else %>
        <.dashboard stats={stats(@current_scope.user)} />
      <% end %>
    </Layouts.app>
    """
  end

  defp maybe_load_market(socket) do
    if socket.assigns.market? do
      assign(socket,
        offers: Catalog.list_market_offers(),
        platforms: Catalog.list_market_platforms()
      )
    else
      socket
    end
  end

  defp section(socket), do: if(socket.assigns.live_action == :shop, do: :shop, else: :home)

  defp page_title(socket) do
    case {socket.assigns.live_action, signed_in?(socket)} do
      {:shop, _} -> gettext("Shop")
      {:index, true} -> gettext("Home")
      _ -> gettext("Shop")
    end
  end

  # The market's visible heading stays short ("Shop"); the document title and
  # description carry the search terms instead.
  defp market_meta_title(true), do: SEO.default_title()
  defp market_meta_title(false), do: gettext("Home")

  defp market_description(true), do: SEO.default_description()

  defp market_description(false) do
    gettext("Your ViewNinjas dashboard: wallet balance, orders in progress and the shop.")
  end

  defp signed_in?(%{assigns: assigns}), do: signed_in?(assigns[:current_scope])
  defp signed_in?(%{user: %{}}), do: true
  defp signed_in?(_), do: false

  # -- the market --------------------------------------------------------

  attr :offers, :list, required: true
  attr :platforms, :list, required: true
  attr :platform, :string, default: nil
  attr :params, :map, required: true
  attr :signed_in?, :boolean, required: true

  defp market(assigns) do
    ~H"""
    <section class="vn-hero">
      <img
        src={~p"/images/logo.png"}
        class="vn-hero__logo"
        alt="Tangi"
        width="569"
        height="459"
      />
      <h2 class="vn-hero__title">{gettext("Social media growth in Kenya")}</h2>
      <p class="vn-hero__tagline">
        {gettext(
          "Buy Instagram followers, TikTok likes and YouTube views — priced in shillings, sold from your phone."
        )}
      </p>
    </section>

    <section class="vn-card">
      <h2>{gettext("Three grades, one margin")}</h2>
      <ul class="vn-grades">
        <li :for={grade <- Grade.all()} id={"legend-#{grade}"}>
          <span class="vn-grade">{Grade.label(grade)}</span>
          <span class="vn-muted">{grade_blurb(grade)}</span>
        </li>
      </ul>
    </section>

    <section class="vn-card">
      <h2>{gettext("Pick a platform")}</h2>
      <div class="vn-chips">
        <button
          type="button"
          class={["vn-chip", is_nil(@platform) && "vn-chip--on"]}
          phx-click="filter"
          phx-value-platform="all"
          id="chip-all"
        >
          {gettext("All")}
        </button>
        <button
          :for={platform <- @platforms}
          type="button"
          class={["vn-chip", @platform == platform && "vn-chip--on"]}
          phx-click="filter"
          phx-value-platform={platform}
          id={"chip-#{platform}"}
        >
          {platform}
        </button>
      </div>
    </section>

    <section class="vn-card">
      <h2>{gettext("Offers")}</h2>
      <ul class="vn-offers">
        <li :for={offer <- @offers} id={"offer-#{offer.id}"}>
          <.link navigate={~p"/offers/#{offer.id}"} class="vn-offer-link">
            <span class="vn-offer-link__title">{offer.title}</span>
            <span class="vn-offer-link__from">{from_label(offer, @params)}</span>
          </.link>
        </li>
      </ul>
      <p :if={@offers == []} class="vn-muted">
        {gettext("Nothing is on sale right now — check back soon.")}
      </p>
    </section>

    <section class="vn-card" id="market-copy">
      <h2>{gettext("Buy followers, likes and views in Kenya")}</h2>
      <p class="vn-muted">
        {gettext(
          "Every offer is a platform and an outcome, in three grades: cheap, moderate and quality. The grade decides how fast it moves and whether it comes with a refill — the markup over cost is the same on all three."
        )}
      </p>
      <p class="vn-muted">
        {gettext(
          "Pay in shillings by M-Pesa and watch the order from your phone. If a supplier finishes only part of an order, the unfinished share is credited back to your wallet automatically."
        )}
      </p>
    </section>

    <section :if={not @signed_in?} class="vn-card">
      <h2>{gettext("Ready to buy?")}</h2>
      <p class="vn-muted">{gettext("Browsing is free; ordering needs an account.")}</p>
      <div class="flex flex-col gap-2">
        <.link navigate={~p"/users/register"} class="vn-button">
          {gettext("Create an account")}
        </.link>
        <.link navigate={~p"/users/log-in"} class="vn-button vn-button--muted">
          {gettext("Log in")}
        </.link>
      </div>
    </section>
    """
  end

  # -- the buyer dashboard (stubbed) -------------------------------------

  attr :stats, :list, required: true

  defp dashboard(assigns) do
    ~H"""
    <section class="vn-card" id="wallet-card">
      <h2>{gettext("Wallet")}</h2>
      <p class="vn-total__value">{wallet_balance(@stats)}</p>
      <.link navigate={~p"/wallet"} class="vn-button vn-button--muted">
        {gettext("Top up or see the ledger")}
      </.link>
    </section>

    <section class="vn-stats" aria-label={gettext("Your numbers")}>
      <div :for={stat <- @stats} class="vn-card vn-stat" id={"stat-#{stat.id}"}>
        <span class="vn-stat__label">{stat.label}</span>
        <span :if={stat.value} class="vn-stat__value">{stat.value}</span>
        <span :if={is_nil(stat.value)} class="vn-skeleton vn-stat__value" aria-hidden="true"></span>
      </div>
    </section>

    <section class="vn-card" id="orders-card">
      <h2>{gettext("Your orders")}</h2>
      <p class="vn-muted">
        {orders_note(@stats)}
      </p>
      <div class="flex flex-col gap-2">
        <.link navigate={~p"/orders"} class="vn-button vn-button--muted">
          {gettext("See your orders")}
        </.link>
        <.link navigate={~p"/shop"} class="vn-button">{gettext("Browse the shop")}</.link>
      </div>
    </section>
    """
  end

  # -- helpers -----------------------------------------------------------

  defp grade_blurb(:cheap), do: gettext("The lowest price that still works. Slower, no frills.")
  defp grade_blurb(:moderate), do: gettext("The balanced one — a fair speed for the price.")

  defp grade_blurb(:quality),
    do: gettext("The fastest and steadiest. Priced like the service under it.")

  defp grade_blurb(_), do: ""

  defp from_label(offer, params) do
    case Catalog.from_kes_cents(offer, params) do
      nil -> gettext("price on request")
      cents -> gettext("from %{price}", price: Pricing.format_kes_cents(cents))
    end
  end

  # -- the stats strip (scope.md §11) ------------------------------------

  # Real numbers from real rows where M7 can supply them; the rest stay a
  # skeleton rather than a row of fake zeroes. `nil` renders as a skeleton.
  defp stats(user) do
    [
      %{
        id: "wallet",
        label: gettext("Wallet balance"),
        value: Pricing.format_kes_cents(Wallet.balance(user))
      },
      %{
        id: "in-progress",
        label: gettext("In progress"),
        value: Integer.to_string(Orders.count_open(user))
      },
      %{id: "delivered", label: gettext("Delivered this month"), value: nil},
      %{id: "refills", label: gettext("Refills available"), value: nil},
      %{id: "credit", label: gettext("Credit from partials"), value: nil},
      %{id: "spent", label: gettext("Total spent"), value: nil}
    ]
  end

  defp wallet_balance(stats) do
    case Enum.find(stats, &(&1.id == "wallet")) do
      %{value: value} when is_binary(value) -> value
      _ -> "—"
    end
  end

  defp orders_note(stats) do
    case Enum.find(stats, &(&1.id == "in-progress")) do
      %{value: "0"} -> gettext("No orders yet.")
      %{value: count} when is_binary(count) -> gettext("%{count} in progress.", count: count)
      _ -> gettext("Your orders appear here.")
    end
  end
end
