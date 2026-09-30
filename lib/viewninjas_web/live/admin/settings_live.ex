defmodule ViewNinjasWeb.Admin.SettingsLive do
  @moduledoc """
  The super-admin's settings (scope.md §7, §11; build-plan.md M12). Super-admin
  only.

  The rail key, the SMS credentials, the FX source, the mailer From and the rest —
  the values that used to be environment variables only. They are stored encrypted
  and can be set or cleared here. A secret is never shown back: the form says
  whether one is in force, and leaves it alone unless a new value is typed.

  The bootstrap values — `DATABASE_URL`, `SECRET_KEY_BASE`, `CLOAK_KEY`, `PORT`,
  `PHX_HOST` and the Postgres variables — stay in the environment, because they are
  needed before the database is reachable.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, gettext("Settings")) |> load()}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    case Settings.put_many(params, actor(socket)) do
      {:ok, 0} ->
        {:noreply, put_flash(socket, :info, gettext("Nothing to change."))}

      {:ok, count} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Saved %{count} setting(s).", count: count))
         |> load()}

      {:error, :not_an_integer} ->
        {:noreply, put_flash(socket, :error, gettext("The SMS cap must be a whole number."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save those settings."))}
    end
  end

  def handle_event("clear", %{"key" => key}, socket) do
    :ok = Settings.clear(key)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Cleared — the environment or the default applies again."))
     |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Settings")}
      admin={:settings}
    >
      <p class="vn-muted" id="settings-intro">
        {gettext(
          "Stored encrypted. A secret is never shown back; leave a field blank to keep what is there."
        )}
      </p>

      <.form for={@form} id="settings-form" phx-submit="save">
        <section :for={{group, entries} <- @groups} class="vn-card" id={"settings-#{group}"}>
          <h2>{group}</h2>

          <div :for={entry <- entries} class="vn-setting" id={"setting-#{entry.key}"}>
            <.input
              :if={entry.secret}
              type="password"
              field={@form[entry.key]}
              label={entry.label}
              autocomplete="new-password"
              placeholder={secret_placeholder(entry)}
            />
            <.input
              :if={!entry.secret}
              field={@form[entry.key]}
              label={entry.label}
              placeholder={entry[:placeholder]}
            />
            <p :if={entry[:hint]} id={"hint-#{entry.key}"} class="vn-muted">{entry[:hint]}</p>

            <p class="vn-muted">
              {state_label(entry)}
              <button
                :if={entry.stored}
                type="button"
                class="text-brand hover:underline"
                phx-click="clear"
                phx-value-key={entry.key}
                id={"clear-#{entry.key}"}
              >
                {gettext("clear")}
              </button>
            </p>
          </div>
        </section>

        <button class="vn-button" id="settings-submit">{gettext("Save")}</button>
      </.form>

      <section class="vn-card" id="settings-bootstrap">
        <h2>{gettext("Set in the environment")}</h2>
        <p class="vn-muted">
          {gettext(
            "DATABASE_URL and the Postgres variables, SECRET_KEY_BASE, CLOAK_KEY, PORT and PHX_HOST are needed before the database is reachable, so they cannot be set here."
          )}
        </p>
      </section>
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load(socket) do
    entries = Settings.entries()

    assign(socket,
      groups: grouped(entries),
      form: to_form(Map.new(entries, &{&1.key, &1.value || ""}), as: "settings")
    )
  end

  defp grouped(entries) do
    by_group = Enum.group_by(entries, & &1.group)

    Enum.map(Settings.groups(), fn {group, _specs} -> {group, Map.get(by_group, group, [])} end)
  end

  defp secret_placeholder(%{effective: true}), do: gettext("•••• set — leave blank to keep")
  defp secret_placeholder(_entry), do: gettext("not set")

  defp state_label(%{stored: true}), do: gettext("Set here.")
  defp state_label(%{effective: true}), do: gettext("From the environment or the default.")
  defp state_label(_entry), do: gettext("Not set.")

  defp actor(socket), do: socket.assigns.current_scope.user
end
