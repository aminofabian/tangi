defmodule ViewNinjasWeb.UserLive.VerifyPhone do
  @moduledoc """
  The phone verification screen (build-plan.md M2).

  Texts a 6-digit code to the number on the account, takes it back with
  `autocomplete="one-time-code"`, shows a visible resend countdown, and says
  plainly when a number is locked out.
  """
  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Accounts
  alias ViewNinjas.Accounts.{Phone, PhoneVerification}
  alias ViewNinjasWeb.ClientIp

  @resend_seconds 60

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Verify your phone")}
    >
      <%= if @user.phone_verified_at do %>
        <section class="vn-card">
          <p>Your phone <strong>{Phone.format(@user.phone)}</strong> is verified.</p>
          <.link navigate={~p"/account"} class="vn-button">Back to account</.link>
        </section>
      <% else %>
        <section class="vn-card">
          <p>
            We will text a 6-digit code to <strong>{Phone.format(@user.phone)}</strong>.
          </p>
          <p class="vn-muted">It expires in 5 minutes.</p>

          <.form for={@form} id="otp_form" phx-submit="verify" phx-change="validate">
            <.input
              field={@form[:code]}
              type="text"
              label={gettext("Code")}
              autocomplete="one-time-code"
              inputmode="numeric"
              pattern="[0-9]{6}"
              maxlength="6"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="vn-button w-full" phx-disable-with={gettext("Checking...")}>
              {gettext("Verify")}
            </.button>
          </.form>

          <div class="mt-4">
            <button
              :if={@resend_in > 0}
              type="button"
              id="resend-button"
              class="vn-button vn-button--muted w-full"
              disabled
            >
              {gettext("Resend in")} {@resend_in}s
            </button>
            <button
              :if={@resend_in == 0}
              type="button"
              id="resend-button"
              class="vn-button vn-button--muted w-full"
              phx-click="send_code"
            >
              {@resend_label}
            </button>
          </div>
        </section>
      <% end %>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: gettext("Verify your phone"),
       user: socket.assigns.current_scope.user,
       form: to_form(%{"code" => ""}, as: "user"),
       client_ip: ClientIp.from_socket(socket),
       resend_in: 0,
       resend_label: gettext("Send code")
     )}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("send_code", _params, socket) do
    case PhoneVerification.request(socket.assigns.user, ip: socket.assigns.client_ip) do
      {:ok, :queued} ->
        {:noreply,
         socket
         |> assign(:resend_label, gettext("Resend code"))
         |> start_countdown()
         |> put_flash(:info, "We sent a code to #{Phone.format(socket.assigns.user.phone)}.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, error_message(reason))}
    end
  end

  def handle_event("verify", %{"user" => %{"code" => code}}, socket) do
    case PhoneVerification.verify(socket.assigns.user, String.trim(code)) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:current_scope, Accounts.Scope.for_user(user))
         |> put_flash(:info, gettext("Phone verified."))
         |> push_navigate(to: ~p"/account")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:form, to_form(%{"code" => ""}, as: "user"))
         |> put_flash(:error, error_message(reason))}
    end
  end

  @impl true
  def handle_info(:resend_tick, socket) do
    case socket.assigns.resend_in do
      seconds when seconds > 1 ->
        Process.send_after(self(), :resend_tick, 1_000)
        {:noreply, assign(socket, :resend_in, seconds - 1)}

      _ ->
        {:noreply, assign(socket, :resend_in, 0)}
    end
  end

  defp start_countdown(socket) do
    if socket.assigns.resend_in == 0 do
      Process.send_after(self(), :resend_tick, 1_000)
    end

    assign(socket, :resend_in, @resend_seconds)
  end

  defp error_message(:rate_limited), do: "Too many codes requested. Please try again later."
  defp error_message(:too_soon), do: "Please wait a moment before requesting another code."

  defp error_message(:invalid_phone),
    do: "That phone number cannot receive texts. Update it in settings."

  defp error_message(:invalid_code),
    do: "That code is not right. Check the message and try again."

  defp error_message(:too_many_attempts), do: "Too many attempts. Request a new code."
  defp error_message(:expired), do: "That code has expired. Request a new one."
  defp error_message(:already_used), do: "That code has already been used. Request a new one."
  defp error_message(:no_challenge), do: "Request a code first."
  defp error_message(:no_code), do: "Request a new code."
  defp error_message(:enqueue_failed), do: "We could not send a code just now. Try again."
  defp error_message(_), do: "Something went wrong. Try again."
end
