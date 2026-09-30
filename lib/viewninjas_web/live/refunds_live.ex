defmodule ViewNinjasWeb.RefundsLive do
  @moduledoc """
  The promise in plain words (scope.md §13, §17; build-plan.md M12).

  Platform terms forbid buying followers, likes and views, and that is a risk we
  carry in the open rather than bury: drops, bans and advertising limits are real.
  The copy here describes grade, speed and refill, and promises only the thing the
  panels actually honour — undelivered quantity comes back. It makes no claim of a
  network partnership and never says every unit is a person.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjasWeb.{Analytics, SEO}

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Refunds"))
     |> assign(:meta_title, gettext("Refunds and refills for social media orders"))
     |> assign(
       :page_description,
       gettext(
         "How refunds and refills work at ViewNinjas: when an order does not fully arrive, the undelivered quantity comes back to your wallet in shillings, automatically."
       )
     )
     |> assign(:analytics, Analytics.capture(socket, session))}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    Analytics.record_page_view(socket, uri)
    {:noreply, assign(socket, :canonical_url, SEO.canonical_url(uri))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} title={gettext("Refunds")}>
      <section class="vn-card" id="refund-promise">
        <h2>{gettext("What we promise")}</h2>
        <p class="vn-muted">
          {gettext(
            "Each grade tells you how fast it moves and whether it comes with a refill. That is what you are buying — not a count of anything else."
          )}
        </p>
      </section>

      <section class="vn-card" id="refund-undelivered">
        <h2>{gettext("If it does not fully arrive")}</h2>
        <p class="vn-muted">
          {gettext(
            "Undelivered quantity comes back to you. If a supplier finishes only part of an order, the unfinished share is credited to your wallet automatically — you do not have to ask."
          )}
        </p>
        <p class="vn-muted">
          {gettext(
            "If an order fails before it starts, the whole amount is credited back to your wallet."
          )}
        </p>
      </section>

      <section class="vn-card" id="refund-wallet">
        <h2>{gettext("What the credit is")}</h2>
        <p class="vn-muted">
          {gettext(
            "A credit is shillings in your wallet, spendable on any order straight away. We do not reverse a payment back down the M-Pesa line in this version — reversals are slow and easy to get wrong, and a credit reaches you faster."
          )}
        </p>
        <.link navigate={~p"/wallet"} class="vn-button vn-button--muted">{gettext("See my wallet")}</.link>
      </section>

      <section class="vn-card" id="refund-honest">
        <h2>{gettext("The honest part")}</h2>
        <p class="vn-muted">
          {gettext(
            "Instagram, TikTok and YouTube do not permit buying followers, likes or views. That means a drop, a profile restriction, or a limit on advertising is possible, and we cannot promise otherwise."
          )}
        </p>
        <p class="vn-muted">
          {gettext(
            "We are not affiliated with, endorsed by, or partnered with any of these platforms. We buy wholesale capacity from suppliers and resell it in shillings; we do not claim that every unit is an authentic person."
          )}
        </p>
        <p class="vn-muted">
          {gettext(
            "What we do control is the price, the grade, the refill, and the credit when something does not arrive. That is the deal on the tin."
          )}
        </p>
      </section>
    </Layouts.app>
    """
  end
end
