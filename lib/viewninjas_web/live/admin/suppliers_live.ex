defmodule ViewNinjasWeb.Admin.SuppliersLive do
  @moduledoc """
  The supplier boundary in the back office (build-plan.md M3): each panel's key,
  float and sync state, the raw ingested catalog, and the manual triggers that
  prove all three keys work.

  The page is a browser, not a wall of forms: the panels are listed down the left,
  and the one you are looking at shows its detail beside the list with the things
  you can do to it on the right. Three columns, one row.

  A panel's configuration — base URL, key, `active` and capabilities — is edited
  here rather than only by `mix viewninjas.suppliers.setup` (scope.md §14: a
  fourth panel is a row plus a key). The key is never shown back, so a blank box
  means "leave it as it is".

  Curated offers are M4 — this is the raw feed, unwatched and unfiltered.
  """
  use ViewNinjasWeb, :live_view

  require Logger

  alias ViewNinjas.Suppliers
  alias ViewNinjas.Workers.{CheckSupplierBalance, SyncSupplierServices}

  @raw_limit 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Suppliers")}
      admin={:suppliers}
    >
      <%!-- What you can do to every panel at once. --%>
      <section class="vn-card vn-wide">
        <div class="flex gap-2">
          <button class="vn-button vn-button--muted" phx-click="check_all" id="check-all">
            Check all balances
          </button>
          <button class="vn-button vn-button--muted" phx-click="sync_all" id="sync-all">
            Sync all catalogs
          </button>
        </div>
      </section>

      <%!-- Column one: the panels. --%>
      <section class={["vn-card", @suppliers == [] && "vn-wide"]} id="supplier-list">
        <p class="vn-eyebrow">
          {gettext("Panels")} <span class="vn-muted">{length(@suppliers)}</span>
        </p>

        <ul :if={@suppliers != []} class="vn-rail">
          <li :for={row <- @suppliers}>
            <button
              type="button"
              class="vn-rail__item"
              phx-click="select"
              phx-value-slug={row.supplier.slug}
              id={"supplier-#{row.supplier.slug}"}
              aria-current={if @selected_slug == row.supplier.slug, do: "true", else: nil}
            >
              <span class="vn-rail__name">{row.supplier.slug}</span>
              <span class="vn-rail__count">{row.active_services}/{row.total_services}</span>
              <span class="vn-rail__meta">
                {state_label(row.supplier)} · {balance_short(row.supplier)}
              </span>
            </button>
          </li>
        </ul>

        <p :if={@suppliers == []} class="vn-muted">
          {gettext("No panels yet. Add the keys below and sync.")}
        </p>
      </section>

      <%!-- Columns two and three: what the chosen panel is, and what it takes. --%>
      <%= if @selected do %>
        <section class="vn-card" id="supplier-detail">
          <h2>{@selected.supplier.slug}</h2>
          <p class="vn-muted">{state_label(@selected.supplier)}</p>

          <dl class="vn-detail">
            <dt>Base URL</dt>
            <dd>{@selected.supplier.base_url}</dd>
            <dt>Balance</dt>
            <dd>{balance(@selected.supplier)}</dd>
            <dt>Services</dt>
            <dd>{@selected.active_services} active / {@selected.total_services} ingested</dd>
            <dt>Last sync</dt>
            <dd>{format_at(@selected.last_seen_at)}</dd>
          </dl>
        </section>

        <section class="vn-card" id="supplier-config">
          <p class="vn-eyebrow">{gettext("Configuration")}</p>

          <.form
            for={@selected.form}
            id={"supplier-form-#{@selected.supplier.slug}"}
            phx-submit="save_supplier"
          >
            <.input type="hidden" field={@selected.form["slug"]} />
            <.input field={@selected.form["base_url"]} label={gettext("Base URL")} />
            <.input
              type="password"
              field={@selected.form["api_key"]}
              label={gettext("API key")}
              autocomplete="new-password"
              placeholder={key_placeholder(@selected.supplier)}
            />
            <.input type="checkbox" field={@selected.form["active"]} label={gettext("Active")} />
            <.capability_fields form={@selected.form} flags={@capability_flags} />

            <p :if={message = @errors[@selected.supplier.slug]} class="vn-error">{message}</p>

            <div class="vn-actions">
              <button class="vn-button" type="submit" id={"save-#{@selected.supplier.slug}"}>
                {gettext("Save")}
              </button>
              <button
                class="vn-button vn-button--muted"
                type="button"
                phx-click="check_balance"
                phx-value-slug={@selected.supplier.slug}
                id={"check-#{@selected.supplier.slug}"}
              >
                {gettext("Check balance")}
              </button>
              <button
                class="vn-button vn-button--muted"
                type="button"
                phx-click="sync"
                phx-value-slug={@selected.supplier.slug}
                id={"sync-#{@selected.supplier.slug}"}
              >
                {gettext("Sync services")}
              </button>
            </div>
          </.form>
        </section>
      <% end %>

      <section class="vn-card vn-wide" id="new-supplier">
        <h2>{gettext("Add a panel")}</h2>
        <p class="vn-muted">
          {gettext("A fourth panel is a row plus a key, not a new integration.")}
        </p>

        <.form for={@new_form} id="new-supplier-form" phx-submit="create_supplier">
          <.input field={@new_form["slug"]} label={gettext("Slug")} />
          <.input field={@new_form["base_url"]} label={gettext("Base URL")} />
          <.input
            type="password"
            field={@new_form["api_key"]}
            label={gettext("API key")}
            autocomplete="new-password"
          />
          <.input type="checkbox" field={@new_form["active"]} label={gettext("Active")} />
          <.capability_fields form={@new_form} flags={@capability_flags} />
          <button class="vn-button" type="submit" id="create-supplier">
            {gettext("Create panel")}
          </button>
        </.form>
      </section>

      <section class="vn-card vn-wide">
        <h2>Raw catalog</h2>
        <p class="vn-muted">
          The newest {length(@services)} ingested rows from every panel. Curation — shortlist,
          pin, publish — arrives in M4.
        </p>

        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>Panel</th>
                <th>ID</th>
                <th>Name</th>
                <th>Type</th>
                <th>USD/1k</th>
                <th>Min</th>
                <th>Max</th>
                <th>Refill</th>
                <th>Active</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={service <- @services} id={"service-#{service.id}"}>
                <td>{service.supplier.slug}</td>
                <td>{service.external_id}</td>
                <td>{service.name}</td>
                <td>{service.type}</td>
                <td>{Suppliers.format_usd_micros(service.rate_micros)}</td>
                <td>{service.min}</td>
                <td>{service.max}</td>
                <td>{service.refill}</td>
                <td>{service.active}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p :if={@services == []} class="vn-muted">
          Nothing ingested yet. Add the keys and press “Sync services”.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Suppliers.subscribe()

    {:ok,
     socket
     |> assign(:page_title, gettext("Suppliers"))
     |> assign(:errors, %{})
     |> assign(:selected_slug, nil)
     |> assign(:capability_flags, Suppliers.capability_flags())
     |> assign(:new_form, new_form())
     |> load()}
  end

  @impl true
  def handle_event("select", %{"slug" => slug}, socket) do
    {:noreply, select_panel(socket, slug)}
  end

  def handle_event("check_balance", %{"slug" => slug}, socket) do
    enqueue(slug, &CheckSupplierBalance.new/1, "Checking #{slug}…", socket)
  end

  def handle_event("check_all", _params, socket) do
    for supplier <- Suppliers.list_suppliers() do
      Oban.insert(CheckSupplierBalance.new(%{"supplier_id" => supplier.id}))
    end

    {:noreply, put_flash(socket, :info, "Checking every panel's balance…")}
  end

  def handle_event("sync", %{"slug" => slug}, socket) do
    enqueue(slug, &SyncSupplierServices.new/1, "Syncing #{slug}'s catalog…", socket)
  end

  def handle_event("sync_all", _params, socket) do
    for supplier <- Suppliers.list_suppliers() do
      Oban.insert(SyncSupplierServices.new(%{"supplier_id" => supplier.id}))
    end

    {:noreply, put_flash(socket, :info, "Syncing every panel's catalog…")}
  end

  def handle_event("save_supplier", %{"supplier" => params}, socket) do
    case Suppliers.get_supplier_by_slug(params["slug"]) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("That panel no longer exists."))}

      supplier ->
        save(supplier, params, socket)
    end
  end

  def handle_event("create_supplier", %{"supplier" => params}, socket) do
    case Suppliers.create_supplier_config(params) do
      {:ok, supplier} ->
        {:noreply,
         socket
         |> assign(:selected_slug, supplier.slug)
         |> put_flash(:info, gettext("Panel %{slug} created.", slug: supplier.slug))
         |> load()}

      {:error, :invalid_limit} ->
        {:noreply, put_flash(socket, :error, limit_message())}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, changeset_message(changeset))}
    end
  end

  @impl true
  def handle_info({:suppliers, {:balance, slug, micros}}, socket) do
    {:noreply,
     socket
     |> clear_error(slug)
     |> put_flash(:info, "#{slug}: balance #{Suppliers.format_usd_micros(micros)} USD")
     |> load()}
  end

  def handle_info({:suppliers, {:balance_failed, slug, reason}}, socket) do
    {:noreply, fail(socket, slug, reason)}
  end

  def handle_info({:suppliers, {:synced, slug, stats}}, socket) do
    {:noreply,
     socket
     |> clear_error(slug)
     |> put_flash(
       :info,
       "#{slug}: #{stats.received} services (#{stats.deactivated} withdrawn)"
     )
     |> load()}
  end

  def handle_info({:suppliers, {:sync_failed, slug, reason}}, socket) do
    {:noreply, fail(socket, slug, reason)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # The capability checkboxes and the multi-status limit, shared by every panel
  # form and the "add a panel" form.
  attr :form, :any, required: true
  attr :flags, :list, required: true

  defp capability_fields(assigns) do
    ~H"""
    <fieldset class="mt-3">
      <legend class="vn-muted">{gettext("Capabilities")}</legend>
      <.input
        :for={flag <- @flags}
        type="checkbox"
        field={@form["cap_" <> flag]}
        label={flag}
      />
      <.input
        field={@form["multi_status_limit"]}
        type="number"
        min="1"
        label={gettext("Multi-status limit")}
      />
    </fieldset>
    """
  end

  defp save(supplier, params, socket) do
    case Suppliers.update_supplier_config(supplier, params) do
      {:ok, saved} ->
        {:noreply,
         socket
         |> clear_error(saved.slug)
         |> put_flash(:info, gettext("%{slug} saved.", slug: saved.slug))
         |> load()}

      {:error, :invalid_limit} ->
        {:noreply, put_error(socket, supplier.slug, limit_message())}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_error(socket, supplier.slug, changeset_message(changeset))}
    end
  end

  defp enqueue(slug, build, info, socket) do
    case Suppliers.get_supplier_by_slug(slug) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown panel #{slug}.")}

      supplier ->
        case Oban.insert(build.(%{"supplier_id" => supplier.id})) do
          {:ok, _job} ->
            {:noreply, put_flash(socket, :info, info)}

          {:error, reason} ->
            Logger.error("could not enqueue supplier job: #{inspect(reason)}")
            {:noreply, put_flash(socket, :error, "Could not start that check just now.")}
        end
    end
  end

  # A rejected key becomes one sentence in the panel's card, not a stack trace.
  defp fail(socket, slug, reason) do
    socket
    |> put_error(slug, Suppliers.error_message(reason))
    |> put_flash(:error, "#{slug}: #{Suppliers.error_message(reason)}")
  end

  defp load(socket) do
    suppliers =
      for supplier <- Suppliers.list_suppliers() do
        %{
          supplier: supplier,
          form: panel_form(supplier),
          active_services: Suppliers.count_active_services(supplier),
          total_services: Suppliers.count_services(supplier),
          last_seen_at: Suppliers.last_seen_at(supplier)
        }
      end

    selected = pick_selected(suppliers, socket.assigns[:selected_slug])

    assign(socket,
      suppliers: suppliers,
      selected: selected,
      selected_slug: selected && selected.supplier.slug,
      services: Suppliers.list_recent_services(limit: @raw_limit)
    )
  end

  # The panel on show: whatever was picked, or the first one. A pick that no
  # longer exists falls back too, so the detail panes are never blank while there
  # is a panel to show.
  defp pick_selected([], _slug), do: nil

  defp pick_selected(suppliers, slug) do
    Enum.find(suppliers, &(&1.supplier.slug == slug)) || hd(suppliers)
  end

  # `selected` and `selected_slug` are read by different parts of the template,
  # so they are always moved together.
  defp select_panel(socket, slug) do
    case pick_selected(socket.assigns.suppliers, slug) do
      nil -> socket
      row -> assign(socket, selected: row, selected_slug: row.supplier.slug)
    end
  end

  # -- form data ---------------------------------------------------------

  defp panel_form(supplier) do
    capabilities = supplier.capabilities || %{}

    %{
      "slug" => supplier.slug,
      "base_url" => supplier.base_url,
      "api_key" => "",
      "active" => supplier.active,
      "multi_status_limit" => Map.get(capabilities, "multi_status_limit", 100)
    }
    |> Map.merge(capability_values(capabilities))
    |> to_form(as: "supplier", id: "supplier-form-#{supplier.slug}")
  end

  defp new_form do
    defaults = Suppliers.default_capabilities()

    %{
      "slug" => "",
      "base_url" => "https://",
      "api_key" => "",
      "active" => true,
      "multi_status_limit" => Map.get(defaults, "multi_status_limit", 100)
    }
    |> Map.merge(capability_values(defaults))
    |> to_form(as: "supplier", id: "new-supplier-form")
  end

  defp capability_values(source) do
    Map.new(Suppliers.capability_flags(), &{"cap_#{&1}", Map.get(source, &1, false)})
  end

  defp key_placeholder(%{api_key: nil}), do: gettext("not set")
  defp key_placeholder(_supplier), do: gettext("•••• set — leave blank to keep")

  defp limit_message do
    gettext("The multi-status limit must be a whole number above zero.")
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, [message | _rest]} -> "#{field} #{message}" end)
  end

  # -- helpers -----------------------------------------------------------

  defp put_error(socket, slug, message),
    do: assign(socket, :errors, Map.put(socket.assigns.errors, slug, message))

  defp clear_error(socket, slug),
    do: assign(socket, :errors, Map.delete(socket.assigns.errors, slug))

  defp balance(%{last_balance_micros: nil}), do: "not checked"

  defp balance(%{last_balance_micros: micros, last_balance_at: at}) do
    "#{Suppliers.format_usd_micros(micros)} USD · #{format_at(at)}"
  end

  # The rail gets one short line for the money; the detail pane spells it out.
  defp balance_short(%{last_balance_micros: nil}), do: "—"

  defp balance_short(%{last_balance_micros: micros}),
    do: "#{Suppliers.format_usd_micros(micros)} USD"

  defp state_label(%{active: active, paused_at: paused_at}) do
    state = if active, do: "active", else: "inactive"
    if is_nil(paused_at), do: state, else: state <> " · paused"
  end

  defp format_at(nil), do: "never"
  defp format_at(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
end
