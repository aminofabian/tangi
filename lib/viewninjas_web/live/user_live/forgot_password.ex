defmodule ViewNinjasWeb.UserLive.ForgotPassword do
  @moduledoc """
  The first half of a password reset: "I forgot my password".

  This screen **never says whether an email is on file**. A reset link is sent
  when the address exists and the screen says exactly the same thing when it does
  not, so it cannot be used to find out who has an account here — the same rule
  that keeps the login screen's wording uniform.

  Requests are rate limited per IP, because this endpoint sends email and is
  otherwise an open relay into the Resend account.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Accounts
  alias ViewNinjas.Accounts.User
  alias ViewNinjas.RateLimit
  alias ViewNinjasWeb.ClientIp

  @generic gettext(
             "If your email is in our system, you will receive instructions to reset your password shortly."
           )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} title={gettext("Reset password")}>
      <div class="mx-auto max-w-sm">
        <.header>
          {gettext("Forgot your password?")}
          <:subtitle>{gettext("We'll email you a link to set a new one.")}</:subtitle>
        </.header>

        <.form for={@form} id="reset_password_form" phx-submit="send_email">
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.button phx-disable-with={gettext("Sending...")} class="vn-button w-full">
            {gettext("Send reset instructions")}
          </.button>
        </.form>

        <p class="mt-6 text-center text-sm">
          <.link navigate={~p"/users/log-in"} class="text-brand hover:underline" phx-no-format>
            {gettext("Back to log in")}
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:client_ip, ClientIp.from_socket(socket))
     |> assign_form(Accounts.change_user_registration(%User{}, %{}, validate_unique: false))}
  end

  @impl true
  def handle_event("send_email", %{"user" => %{"email" => email}}, socket) do
    if RateLimit.allow_password_reset?(socket.assigns.client_ip) do
      deliver_reset_instructions(socket, email)
    else
      {:noreply,
       put_flash(socket, :error, gettext("Too many requests. Please try again in a few minutes."))}
    end
  end

  # The outcome is identical whether or not the address exists. That is the point:
  # a different message for a missing account turns this screen into an account
  # directory for anyone who types an address.
  defp deliver_reset_instructions(socket, email) do
    Accounts.deliver_user_reset_password_instructions(
      Accounts.get_user_by_email(email),
      &url(~p"/users/reset-password/#{&1}")
    )

    {:noreply,
     socket
     |> put_flash(:info, @generic)
     |> assign_form(Accounts.change_user_registration(%User{}, %{}, validate_unique: false))}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
