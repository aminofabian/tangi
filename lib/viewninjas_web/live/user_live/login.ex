defmodule ViewNinjasWeb.UserLive.Login do
  @moduledoc """
  Logging in (scope.md §6).

  There are two ways in — a password, or a link by email — but they are **one
  decision, not two forms**. The screen used to ask for the email twice, once
  above a "Log in with email" button and once above the password fields, which
  read as two unrelated boxes and made it unclear which one to fill in. Now the
  email is typed once and the method is a switch beneath it, so the page states
  one identity and then asks how to prove it.

  The password branch needs a real POST, because logging in has to issue a session
  cookie; the link branch is handled here and never leaves the LiveView.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Accounts
  alias ViewNinjas.Settings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <div class="text-center">
          <.header>
            <p>Log in</p>
            <:subtitle>
              <%= if @current_scope do %>
                You need to reauthenticate to perform sensitive actions on your account.
              <% else %>
                Don't have an account? <.link
                  navigate={~p"/users/register"}
                  class="font-semibold text-brand hover:underline"
                  phx-no-format
                >Sign up</.link> for an account now.
              <% end %>
            </:subtitle>
          </.header>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <.form
          for={@form}
          id="login_form"
          action={~p"/users/log-in"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <.input
            readonly={!!@current_scope}
            field={@form[:email]}
            type="email"
            label="Email"
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />

          <div class="vn-segmented" role="group" aria-label="How would you like to log in?">
            <button
              :for={{method, label} <- method_choices()}
              type="button"
              class={[
                "vn-segmented__option",
                @method == method && "vn-segmented__option--on"
              ]}
              id={"login-method-#{method}"}
              aria-pressed={to_string(@method == method)}
              phx-click="pick_method"
              phx-value-method={method}
            >
              {label}
            </button>
          </div>

          <div :if={@method == :password} id="login-password-fields" class="space-y-1">
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="current-password"
              spellcheck="false"
            />
            <.input
              field={@form[:remember_me]}
              type="checkbox"
              label="Keep me logged in on this device"
            />
          </div>

          <p :if={@method == :link} class="vn-muted" id="login-link-hint">
            {gettext("We'll email you a link that signs you straight in — no password needed.")}
          </p>

          <.button class="vn-button w-full" id="login-submit">
            {submit_label(@method)} <span aria-hidden="true">→</span>
          </.button>
        </.form>

        <p class="text-sm text-base-content/70 text-center">
          <.link navigate={~p"/users/reset-password"} class="text-brand hover:underline" phx-no-format>
            Forgot your password?
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     socket
     |> assign(:form, form)
     # Password is the default: most people who reach this screen have one.
     |> assign(:method, :password)
     |> assign(:trigger_submit, false)}
  end

  @impl true
  def handle_event("pick_method", %{"method" => method}, socket) do
    case parse_method(method) do
      nil -> {:noreply, socket}
      method -> {:noreply, assign(socket, :method, method)}
    end
  end

  def handle_event("submit", %{"user" => %{"email" => email}}, socket) do
    if socket.assigns.method == :link do
      {:noreply, deliver_login_link(socket, email)}
    else
      # Hand off to the controller: a session cookie cannot be set from here.
      {:noreply, assign(socket, :trigger_submit, true)}
    end
  end

  # The reply is the same whether or not the address exists, so this screen cannot
  # be used to discover who has an account.
  defp deliver_login_link(socket, email) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(user, &url(~p"/users/log-in/#{&1}"))
    end

    socket
    |> put_flash(
      :info,
      gettext(
        "If your email is in our system, you will receive instructions for logging in shortly."
      )
    )
    |> push_navigate(to: ~p"/users/log-in")
  end

  # Matched against the known methods rather than converted with `String.to_atom/1`:
  # the value arrives from the browser, and an unbounded atom table is a leak.
  defp parse_method("password"), do: :password
  defp parse_method("link"), do: :link
  defp parse_method(_method), do: nil

  defp method_choices, do: [{:password, gettext("Password")}, {:link, gettext("Email link")}]

  defp submit_label(:link), do: gettext("Send me a login link")
  defp submit_label(_password), do: gettext("Log in")

  # The banner offers the local mailbox, which is only true when email is
  # actually landing there. With a Resend key set, mail really is sent.
  defp local_mail_adapter? do
    not Settings.email_configured?() and
      Application.get_env(:viewninjas, ViewNinjas.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
