defmodule ViewNinjasWeb.UserLive.Registration do
  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Accounts
  alias ViewNinjas.Accounts.{Phone, User}
  alias ViewNinjas.RateLimit
  alias ViewNinjasWeb.ClientIp

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} title={gettext("Create an account")}>
      <.header>
        Create an account
        <:subtitle>
          Already registered?
          <.link navigate={~p"/users/log-in"} class="text-brand hover:underline">
            Log in
          </.link>
          to your account now.
        </:subtitle>
      </.header>

      <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
        <.input
          field={@form[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:phone]}
          type="tel"
          label="Phone"
          autocomplete="tel"
          placeholder="0712 345 678"
          required
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="new-password"
          spellcheck="false"
          required
        />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label="Confirm password"
          autocomplete="new-password"
          spellcheck="false"
        />

        <.button phx-disable-with="Creating account..." class="vn-button w-full">
          Create an account
        </.button>
      </.form>

      <%!-- Sign-up cannot set a session itself, so a successful registration
            posts the credentials straight to the session controller and logs
            the new customer in without an email round-trip. --%>
      <.form
        :if={@trigger_submit}
        for={@login_form}
        id="registration_login"
        action={~p"/users/log-in"}
        method="post"
        phx-trigger-action={@trigger_submit}
      >
        <input type="hidden" name="user[email]" value={@registered_email} />
        <input type="hidden" name="user[password]" value={@registered_password} />
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: ViewNinjasWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    socket =
      socket
      |> assign(:client_ip, ClientIp.from_socket(socket))
      |> assign_form(changeset)
      |> assign(:trigger_submit, false)
      |> assign(:login_form, to_form(%{}, as: "user"))
      |> assign(:registered_email, nil)
      |> assign(:registered_password, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    if RateLimit.allow_signup?(socket.assigns.client_ip, signup_phone_key(user_params)) do
      register(socket, user_params)
    else
      {:noreply,
       put_flash(socket, :error, "Too many sign-up attempts. Please try again in a little while.")}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  defp register(socket, user_params) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:registered_email, user.email)
         |> assign(:registered_password, user_params["password"])
         |> assign(:trigger_submit, true)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  # Budget the phone in its canonical form so `0712…` and `+254712…` share one
  # bucket rather than buying two.
  defp signup_phone_key(%{"phone" => phone}) when is_binary(phone) do
    Phone.normalize_or_self(phone)
  end

  defp signup_phone_key(_), do: "unknown"

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
