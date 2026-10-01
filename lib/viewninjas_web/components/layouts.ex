defmodule ViewNinjasWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use ViewNinjasWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders the app shell.

  Every LiveView template begins with this component. The shop is a single
  centred column with a fixed bottom tab bar (see scope.md §11, §12), because
  it is used on a phone. The back office sets `admin` and gets a sidebar and a
  workspace instead, because it is used at a desk (see the media query at the
  foot of `app.css`); below that width it falls back to the phone shell.

  The header always carries the brand. On a customer screen it also shows the
  optional page title; in the back office the title is the workspace's own
  heading, so it moves into `<main>`.

  ## Examples

      <Layouts.app flash={@flash} section={:shop} title={gettext("Shop")}>
        <h1>Content</h1>
      </Layouts.app>

      <Layouts.app flash={@flash} title={gettext("Orders")} admin={:orders}>
        <section class="vn-card">…</section>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :section, :atom,
    default: nil,
    doc: "the active bottom-tab section, used to highlight the current tab"

  attr :title, :string, default: nil, doc: "the optional sticky header title"

  attr :admin, :atom,
    default: nil,
    doc:
      "the back office section this screen belongs to; set it to swap the customer tab bar for the section nav, and to pick the workspace shape `vn-app--admin-<section>`"

  slot :inner_block, required: true

  def app(assigns) do
    assigns =
      assigns
      |> assign(:back_office?, not is_nil(assigns.admin))
      |> assign(:role, staff_role(assigns[:current_scope]))

    ~H"""
    <div class={[
      "vn-app",
      @back_office? && "vn-app--admin",
      @back_office? && "vn-app--admin-#{@admin}"
    ]}>
      <div class="vn-topbar">
        <header class="vn-header">
          <.brand />
          <%!-- In the back office the title is the page's own heading, not a nav-bar
                afterthought, so it moves into the workspace. --%>
          <h1 :if={@title && !@back_office?} class="vn-header__title">{@title}</h1>
        </header>

        <.admin_nav :if={@back_office?} section={@admin} role={@role} />
      </div>

      <main class={["vn-main", @back_office? && "vn-main--flush"]}>
        <h1 :if={@title && @back_office?} class="vn-page-title">{@title}</h1>
        <%!-- In the flow and first on the page, never pinned: a pinned version sat
              squarely on top of the log-in button. --%>
        <.pwa_install :if={!@back_office?} />
        {render_slot(@inner_block)}
      </main>
    </div>

    <.tab_bar :if={!@back_office?} section={@section} />
    <.flash_group flash={@flash} />
    """
  end

  defp staff_role(%{user: %{role: role}}), do: role
  defp staff_role(_), do: nil

  @doc """
  Renders the brand lockup as a link home.

  This draws the supplied artwork from `priv/static/images/logo.png`; it is the
  one place the app shows its own logo.
  """
  def brand(assigns) do
    ~H"""
    <.link navigate={~p"/"} class="vn-brand">
      <img
        src={~p"/images/logo.png"}
        class="vn-brand__logo"
        alt="Tangi"
        width="569"
        height="459"
      />
    </.link>
    """
  end

  @doc """
  Renders the fixed bottom tab bar.

  Tabs are always visible and reachable one-handed; the current tab is
  marked with `aria-current` for screen readers.
  """
  attr :section, :atom, default: nil

  def tab_bar(assigns) do
    ~H"""
    <nav class="vn-tabbar" aria-label={gettext("Primary")}>
      <.link
        :for={tab <- tabs()}
        navigate={tab.href}
        class="vn-tabbar__item"
        aria-current={if @section == tab.id, do: "page", else: nil}
      >
        <.icon name={tab.icon} class="vn-tabbar__icon" />
        <span>{tab.label}</span>
      </.link>
    </nav>
    """
  end

  defp tabs do
    [
      %{id: :home, label: gettext("Home"), href: ~p"/", icon: "hero-home"},
      %{id: :shop, label: gettext("Shop"), href: ~p"/shop", icon: "hero-shopping-bag"},
      %{id: :orders, label: gettext("Orders"), href: ~p"/orders", icon: "hero-receipt-percent"},
      %{id: :account, label: gettext("Account"), href: ~p"/account", icon: "hero-user"}
    ]
  end

  @doc """
  Renders the back office's section nav.

  Nine sections will not fit in the four-slot bottom tab bar, and an operator
  should never be looking at two different screens both called "Orders", so the
  back office gets a nav of its own. It lives under the header inside the same
  sticky bar, so it scrolls as one piece.

  The sections are shown in two labelled groups — the day job and the money —
  because a flat list of nine gives no clue which is which. Only the groups the
  current role can reach are listed; the router still gates them, this just
  keeps the nav honest.

  ## Examples

      <.admin_nav section={:orders} role={:admin} />

  """
  attr :section, :atom, required: true, doc: "the section being shown"
  attr :role, :atom, default: nil, doc: "the signed-in staff role"

  def admin_nav(assigns) do
    assigns = assign(assigns, :groups, admin_groups(assigns.role))

    ~H"""
    <nav class="vn-admin-nav" aria-label={gettext("Back office")}>
      <ul class="vn-admin-nav__list">
        <li :for={{label, sections} <- @groups} class="vn-admin-nav__group">
          <p class="vn-admin-nav__label">{label}</p>
          <ul class="vn-admin-nav__items">
            <li :for={section <- sections}>
              <.link
                navigate={section.path}
                class="vn-admin-nav__item"
                id={"admin-nav-#{section.id}"}
                aria-current={if @section == section.id, do: "page", else: nil}
              >
                {section.label}
              </.link>
            </li>
          </ul>
        </li>
      </ul>
    </nav>
    """
  end

  # The groups, in the order they appear. Everything at :staff is the day job;
  # :super is the money and the numbers (scope.md §7).
  defp admin_groups(role) do
    [{:staff, gettext("Operations")}, {:super, gettext("Business")}]
    |> Enum.map(fn {level, label} -> {label, section_at(role, level)} end)
    |> Enum.reject(fn {_label, sections} -> sections == [] end)
  end

  defp section_at(role, level) do
    Enum.filter(admin_sections(), &(&1.level == level and reachable?(role, &1.level)))
  end

  defp reachable?(:super_admin, _level), do: true
  defp reachable?(_role, :staff), do: true
  defp reachable?(_role, _level), do: false

  defp admin_sections do
    [
      %{id: :overview, label: gettext("Overview"), path: ~p"/admin", level: :staff},
      %{id: :orders, label: gettext("Orders"), path: ~p"/admin/orders", level: :staff},
      %{id: :suppliers, label: gettext("Suppliers"), path: ~p"/admin/suppliers", level: :staff},
      %{id: :catalog, label: gettext("Catalog"), path: ~p"/admin/catalog", level: :staff},
      %{id: :pricing, label: gettext("Pricing"), path: ~p"/admin/pricing", level: :super},
      %{id: :costs, label: gettext("Costs"), path: ~p"/admin/costs", level: :super},
      %{
        id: :settlements,
        label: gettext("Settlements"),
        path: ~p"/admin/settlements",
        level: :super
      },
      %{id: :insight, label: gettext("Insight"), path: ~p"/admin/insight", level: :super},
      %{id: :settings, label: gettext("Settings"), path: ~p"/admin/settings", level: :super}
    ]
  end

  @doc """
  The first-run "add to home screen" nudge (scope.md §12).

  It leads the page, in the flow rather than pinned over the foot of it, so it can
  never cover a control underneath it. It stays hidden until the browser says the
  app is installable — Chrome's `beforeinstallprompt` — or until an iOS Safari
  visit, which fires no such event and is shown the manual steps instead. A
  dismissal is remembered, but only for a month: an install is a "later", not a
  "never". The whole subtree is `phx-update="ignore"`: the hook owns its own DOM
  and LiveView must not re-render it back.

  The prompt itself is caught in `assets/js/app.js` before LiveView boots — see
  the note there for why the hook cannot wait for the event on its own.
  """
  def pwa_install(assigns) do
    ~H"""
    <aside
      id="pwa-install"
      class="vn-install"
      phx-hook=".PwaInstall"
      phx-update="ignore"
      hidden
    >
      <img src={~p"/images/logo-mark.png"} alt="" width="56" height="56" class="vn-install__mark" />
      <div class="vn-install__copy">
        <p class="vn-install__title">{gettext("Install Tangi")}</p>
        <p class="vn-install__text">{gettext("Add it to your home screen for one-tap ordering.")}</p>
      </div>
      <div class="vn-install__actions">
        <button type="button" class="vn-button" data-pwa-install>{gettext("Install")}</button>
        <button
          type="button"
          class="vn-button vn-button--muted vn-install__dismiss"
          data-pwa-dismiss
          aria-label={gettext("Not now")}
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </aside>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".PwaInstall">
      const SNOOZED_AT = "tangi:pwa-dismissed-at"
      // A month. Long enough not to nag, short enough that a change of mind is
      // still reachable from the nudge rather than only from the Account tab.
      const SNOOZE_MS = 30 * 24 * 60 * 60 * 1000

      export default {
        mounted() {
          if (!window.vnPwa) return

          const button = this.el.querySelector("[data-pwa-install]")
          const text = this.el.querySelector(".vn-install__text")

          const snoozed = () => {
            const at = Number(localStorage.getItem(SNOOZED_AT))
            return at > 0 && Date.now() - at < SNOOZE_MS
          }

          // The Account tab carries a permanent install card; nudging there too
          // would say the same thing twice, so the card wins.
          const hasCard = () => document.querySelector("[data-pwa-install-card]") !== null

          // The browser may have offered installation long before this hook
          // mounted, so every path re-reads the shared state rather than waiting.
          this.refresh = () => {
            if (window.vnPwa.installed() || snoozed() || hasCard()) {
              this.el.hidden = true
            } else if (window.vnPwa.available()) {
              button.hidden = false
              this.el.hidden = false
            } else if (window.vnPwa.ios()) {
              // iOS never fires beforeinstallprompt; show the manual steps.
              text.textContent = "Tap the Share button, then \u201cAdd to Home Screen\u201d."
              button.hidden = true
              this.el.hidden = false
            } else {
              this.el.hidden = true
            }
          }

          button.addEventListener("click", () => window.vnPwa.install())

          this.el.querySelector("[data-pwa-dismiss]").addEventListener("click", () => {
            localStorage.setItem(SNOOZED_AT, String(Date.now()))
            this.el.hidden = true
          })

          window.addEventListener("phx:pwa-installable", this.refresh)
          window.addEventListener("phx:pwa-installed", () => (this.el.hidden = true))
          // A live navigation can bring the Account card in or out from under us.
          window.addEventListener("phx:page-loading-stop", this.refresh)

          this.refresh()
        },
      }
    </script>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
