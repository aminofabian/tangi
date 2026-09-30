defmodule ViewNinjasWeb.Admin.PricingLive do
  @moduledoc """
  The money knobs (build-plan.md M5, scope.md §7): a super-admin changes the
  margin, the buffer, the FX override and the rounding, and every change is an
  audited, append-only version — never an edit, never a deploy.

  Also the FX rate record: the effective rate, and the series the daily job and
  a manual override leave behind.
  """
  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Pricing
  alias ViewNinjas.Pricing.FxRate

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Pricing")}
      admin={:pricing}
    >
      <section class="vn-card" id="in-force">
        <h2>In force</h2>
        <dl class="vn-detail">
          <dt>Margin</dt>
          <dd>{format_percent(@params.margin_bps)} over landed</dd>
          <dt>Buffer</dt>
          <dd>{format_percent(@params.buffer_bps)}</dd>
          <dt>FX</dt>
          <dd>{format_fx(@params.fx_ppm)} KES/USD ({fx_source(@settings, @fx_rate)})</dd>
          <dt>Rounding</dt>
          <dd>nearest shilling, half up</dd>
        </dl>
        <p class="vn-muted">{version_note(@settings)}</p>
      </section>

      <section class="vn-card">
        <h2>New version</h2>
        <p class="vn-muted">A change appends a version; nothing is edited in place.</p>
        <.form for={@form} id="settings-form" phx-submit="save">
          <div class="grid grid-cols-2 gap-2">
            <.input
              field={@form[:margin_percent]}
              type="number"
              step="0.01"
              label="Margin % over landed"
            />
            <.input field={@form[:buffer_percent]} type="number" step="0.01" label="Buffer %" />
          </div>
          <.input
            field={@form[:fx_override]}
            type="number"
            step="0.0001"
            label="FX override (KES/USD, blank for none)"
          />
          <.input field={@form[:reason]} label="Reason" placeholder="why the change" />
          <button class="vn-button" id="settings-submit">Append version</button>
        </.form>
      </section>

      <section class="vn-card">
        <h2>FX rate</h2>
        <.form for={@fx_form} id="fx-form" phx-submit="record_fx">
          <.input
            field={@fx_form[:rate]}
            type="number"
            step="0.0001"
            label="Record a manual rate (KES/USD)"
          />
          <button class="vn-button" id="fx-submit">Record manual rate</button>
        </.form>

        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>Rate</th>
                <th>Source</th>
                <th>By</th>
                <th>When</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={rate <- @fx_rates} id={"fx-#{rate.id}"}>
                <td>{format_fx(rate.rate_ppm)}</td>
                <td>{FxRate.label(rate.source)}</td>
                <td>{actor(rate.actor)}</td>
                <td>{format_at(rate.fetched_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@fx_rates == []} class="vn-muted">
          No rate recorded yet; the §7 default holds.
        </p>
      </section>

      <section class="vn-card">
        <h2>Versions</h2>
        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>Margin</th>
                <th>Buffer</th>
                <th>FX override</th>
                <th>By</th>
                <th>When</th>
                <th>Reason</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={version <- @settings_history} id={"version-#{version.id}"}>
                <td>{format_percent(version.margin_bps)}</td>
                <td>{format_percent(version.buffer_bps)}</td>
                <td>{override(version.fx_override_ppm)}</td>
                <td>{actor(version.actor)}</td>
                <td>{format_at(version.effective_at)}</td>
                <td>{version.reason}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@settings_history == []} class="vn-muted">
          No version recorded yet; the §7 defaults hold.
        </p>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Pricing"))
     |> assign_forms()
     |> load()}
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    with {:ok, margin} <- required_bps(params["margin_percent"], "the margin"),
         {:ok, buffer} <- required_bps(params["buffer_percent"], "the buffer"),
         {:ok, fx} <- optional_ppm(params["fx_override"]) do
      attrs = %{
        margin_bps: margin,
        buffer_bps: buffer,
        fx_override_ppm: fx,
        reason: present(params["reason"])
      }

      case Pricing.append_settings(attrs, socket.assigns.current_scope.user) do
        {:ok, _version} ->
          {:noreply,
           socket
           |> put_flash(:info, "A new pricing version is in force.")
           |> assign_forms()
           |> load()}

        {:error, changeset} ->
          {:noreply, put_flash(socket, :error, changeset_message(changeset))}
      end
    else
      {:error, message} -> {:noreply, put_flash(socket, :error, message)}
    end
  end

  def handle_event("record_fx", %{"fx" => params}, socket) do
    case required_ppm(params["rate"], "the rate") do
      {:ok, ppm} ->
        case Pricing.record_fx_rate(
               %{rate_ppm: ppm, source: "manual"},
               socket.assigns.current_scope.user
             ) do
          {:ok, _rate} ->
            {:noreply,
             socket
             |> put_flash(:info, "The manual rate is recorded.")
             |> assign_forms()
             |> load()}

          {:error, changeset} ->
            {:noreply, put_flash(socket, :error, changeset_message(changeset))}
        end

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # -- internals ---------------------------------------------------------

  defp load(socket) do
    assign(socket,
      settings: Pricing.current_settings(),
      params: Pricing.current(),
      fx_rate: Pricing.current_fx(),
      settings_history: Pricing.list_settings(),
      fx_rates: Pricing.list_fx_rates()
    )
  end

  defp assign_forms(socket) do
    settings = Pricing.current_settings()

    form =
      to_form(
        %{
          "margin_percent" => percent((settings && settings.margin_bps) || 13_000),
          "buffer_percent" => percent((settings && settings.buffer_bps) || 300)
        },
        as: "settings"
      )

    assign(socket, form: form, fx_form: to_form(%{}, as: "fx"))
  end

  defp required_bps(value, label) do
    case scaled(value, 100) do
      {:ok, nil} -> {:error, "Enter #{label}."}
      other -> other
    end
  end

  defp required_ppm(value, label) do
    case scaled(value, 1_000_000) do
      {:ok, nil} -> {:error, "Enter #{label}."}
      other -> other
    end
  end

  defp optional_ppm(value), do: scaled(value, 1_000_000)

  defp scaled(value, _factor) when value in [nil, ""], do: {:ok, nil}

  defp scaled(value, factor) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} ->
        scaled =
          decimal |> Decimal.mult(factor) |> Decimal.round(0, :half_up) |> Decimal.to_integer()

        if scaled > 0, do: {:ok, scaled}, else: {:error, "Enter a positive number."}

      _ ->
        {:error, "Enter a number."}
    end
  end

  defp scaled(_value, _factor), do: {:error, "Enter a number."}

  defp present(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_value), do: nil

  defp percent(nil), do: nil

  defp percent(bps) do
    bps |> Decimal.new() |> Decimal.div(100) |> Decimal.to_string(:normal)
  end

  defp format_percent(bps) do
    "#{bps |> Decimal.new() |> Decimal.div(100) |> Decimal.round(2) |> Decimal.to_string(:normal)}%"
  end

  defp format_fx(ppm) do
    ppm |> Decimal.new() |> Decimal.div(1_000_000) |> Decimal.to_string(:normal)
  end

  defp override(nil), do: "—"
  defp override(ppm), do: format_fx(ppm)

  defp actor(nil), do: "system"
  defp actor(%{email: email}), do: email
  defp actor(_not_loaded), do: "system"

  defp format_at(nil), do: "never"
  defp format_at(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp fx_source(%{fx_override_ppm: ppm}, _fx) when is_integer(ppm), do: "override"
  defp fx_source(_settings, %{source: source}), do: FxRate.label(source)
  defp fx_source(_settings, _fx), do: "default"

  defp version_note(nil), do: "No version recorded yet; the §7 defaults hold."

  defp version_note(settings) do
    "Last changed by #{actor(settings.actor)} on #{format_at(settings.effective_at)}" <>
      if(settings.reason, do: " — #{settings.reason}", else: ".")
  end

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
