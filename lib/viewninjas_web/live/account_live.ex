defmodule ViewNinjasWeb.AccountLive do
  @moduledoc """
  The Account tab (scope.md §11).

  Shows who is signed in and the phone on the account, and is the way in to
  settings and out of the session. The wallet ledger, saved links and
  notification preferences land here in later milestones.
  """
  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.{Notifications, Pricing, Wallet}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: gettext("Account"))
     |> assign(notifications_form: notifications_form(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("save_notifications", %{"notifications" => params}, socket) do
    case Notifications.save_preferences(socket.assigns.current_scope.user, params) do
      {:ok, :saved} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Notification choices saved."))
         |> assign(notifications_form: notifications_form(socket.assigns.current_scope))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save those choices."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      section={:account}
      title={gettext("Account")}
    >
      <%= if @current_scope && @current_scope.user do %>
        <.identity user={@current_scope.user} />
        <section class="vn-card" id="account-wallet">
          <h2>{gettext("Wallet")}</h2>
          <p class="vn-total__value">
            {Pricing.format_kes_cents(Wallet.balance(@current_scope.user))}
          </p>
          <.link navigate={~p"/wallet"} class="vn-button vn-button--muted">
            {gettext("Ledger and top-up")}
          </.link>
        </section>
        <section class="vn-card" id="account-notifications">
          <h2>{gettext("Notifications")}</h2>
          <.form for={@notifications_form} id="notifications-form" phx-submit="save_notifications">
            <.input
              field={@notifications_form[:sms_opted_in]}
              type="checkbox"
              label={gettext("Text me about my orders")}
            />
            <.input
              field={@notifications_form[:sms_quiet_hours]}
              label={gettext("Quiet hours (blank for any time)")}
              placeholder="21:00-07:00"
            />
            <.input
              field={@notifications_form[:email_opted_in]}
              type="checkbox"
              label={gettext("Email me a receipt")}
            />
            <.input type="hidden" field={@notifications_form[:email_quiet_hours]} />
            <button class="vn-button" id="save-notifications">{gettext("Save")}</button>
          </.form>
        </section>
        <div class="flex flex-col gap-2">
          <.link navigate={~p"/refunds"} class="vn-button vn-button--muted" id="account-refunds">
            {gettext("Refunds and what we promise")}
          </.link>
          <.link navigate={~p"/users/settings"} class="vn-button">
            Settings
          </.link>
          <.link href={~p"/users/log-out"} method="delete" class="vn-button vn-button--muted">
            Log out
          </.link>
        </div>
      <% else %>
        <section class="vn-card">
          <h2>Sign in to buy</h2>
          <p class="vn-muted">
            Create an account with your email and phone to place an order.
          </p>
          <div class="mt-4 flex flex-col gap-2">
            <.link navigate={~p"/users/register"} class="vn-button">
              Create an account
            </.link>
            <.link navigate={~p"/users/log-in"} class="vn-button vn-button--muted">
              Log in
            </.link>
          </div>
        </section>
      <% end %>
    </Layouts.app>
    """
  end

  attr :user, :map, required: true

  defp identity(assigns) do
    ~H"""
    <section class="vn-card">
      <dl class="vn-detail">
        <dt>Email</dt>
        <dd>{@user.email}</dd>
        <dt>Phone</dt>
        <dd>
          {Phone.format(@user.phone)}
          <%= if @user.phone_verified_at do %>
            <span class="vn-badge vn-badge--ok">Verified</span>
          <% else %>
            <.link navigate={~p"/users/verify-phone"} class="text-brand hover:underline">
              Verify now
            </.link>
          <% end %>
        </dd>
        <dt>Role</dt>
        <dd>{@user.role}</dd>
      </dl>
      <p :if={is_nil(@user.phone_verified_at)} class="mt-3 vn-muted">
        We text a short code to prove the number before you can pay with it.
      </p>
    </section>
    """
  end

  defp notifications_form(%{user: %{} = user}) do
    preferences = Notifications.preferences(user)

    to_form(
      %{
        "sms_opted_in" => preferences.sms.opted_in,
        "sms_quiet_hours" => preferences.sms.quiet_hours || "",
        "email_opted_in" => preferences.email.opted_in,
        "email_quiet_hours" => ""
      },
      as: "notifications"
    )
  end

  defp notifications_form(_scope) do
    to_form(
      %{
        "sms_opted_in" => true,
        "sms_quiet_hours" => "",
        "email_opted_in" => true,
        "email_quiet_hours" => ""
      },
      as: "notifications"
    )
  end
end
