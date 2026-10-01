defmodule ViewNinjasWeb.UserLive.ResetPassword do
  @moduledoc """
  The second half of a password reset: setting the new password from the emailed
  link.

  The token carries the account, so this screen needs no session — which is the
  point of emailing a link rather than resetting by phone. Submitting the form
  cannot use a plain LiveView event, because a successful reset must **rotate the
  session**: the tokens are deleted inside the same transaction that changes the
  password, so the response has to be a real form post for the new cookie to be
  issued. That is why the form carries an `action` and `phx-trigger-action`
  rather than `phx-submit` handling a `Repo` write.

  An invalid or expired link never renders the form; it goes back to log in with
  an explanation, rather than showing a form that cannot succeed.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} title={gettext("Set a new password")}>
      <div class="mx-auto max-w-sm">
        <.header>{gettext("Set a new password")}</.header>

        <.form
          for={@form}
          id="reset_password_form"
          action={~p"/users/log-in?_action=password_reset"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name="user[token]" value={@token} />
          <.input
            field={@form[:password]}
            type="password"
            label={gettext("New password")}
            autocomplete="new-password"
            spellcheck="false"
            required
            phx-mounted={JS.focus()}
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label={gettext("Confirm new password")}
            autocomplete="new-password"
            spellcheck="false"
            required
          />
          <.button phx-disable-with={gettext("Setting...")} class="vn-button w-full">
            {gettext("Set new password")}
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
  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    case socket.assigns do
      %{user: user} when not is_nil(user) ->
        {:ok,
         socket
         |> assign(:user, user)
         |> assign(:token, params["token"])
         |> assign_form()
         |> assign(:trigger_submit, false)}

      %{} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Reset password link is invalid or it has expired."))
         |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  # Submitting only arms the real post: the password is written by the controller,
  # which can then issue the session that the token deletion invalidates. The token
  # travels as form data, so the post is self-contained and the submitted token is
  # always the one this screen was rendered for.
  @impl true
  def handle_event("submit", %{"user" => user_params}, socket) do
    {:noreply,
     socket
     |> assign_form(user_params)
     |> assign(:trigger_submit, true)}
  end

  # Only the token's own account is shown, so a valid link can never be pointed at
  # somebody else's email address.
  defp assign_user_and_token(socket, %{"token" => token}) do
    assign(socket, user: Accounts.get_user_by_reset_password_token(token), token: token)
  end

  defp assign_user_and_token(socket, _params), do: assign(socket, user: nil, token: nil)

  # The form is driven by a plain params map rather than a changeset: the password
  # is not written here, so there are no field errors to show until the controller
  # has refused it and sent the user back. The token is rendered as its own hidden
  # input, and the post carries this link's token — the account comes from the
  # token alone, never from the form.
  defp assign_form(socket, params \\ %{}) do
    assign(socket, form: to_form(params, as: "user"))
  end
end
