defmodule ViewNinjasWeb.Admin.SettlementsLive do
  @moduledoc """
  Settlement reconciliation (scope.md §10, §11; `docs/malipo-connect.md` §10;
  build-plan.md M10). Super-admin only.

  Paste a Malipo statement, and read the four buckets and the payout delta. A
  matched line has its reconciled fee written onto the payment; every other
  bucket is a flag for a person, never an automatic ledger write.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.{Pricing, Settlement}

  @bucket_labels [
    {:matched, "Matched"},
    {:amount_mismatch, "Amount mismatch"},
    {:provider_only, "Provider only"},
    {:local_only, "Local only"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Settlements"))
     |> assign(:bucket_labels, @bucket_labels)
     |> assign(:form, form())}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:selected, params["statement"])
     |> assign(:received, shillings_to_cents(params["received"]))
     |> load()}
  end

  @impl true
  def handle_event("import", %{"settlement" => params}, socket) do
    with {:ok, lines} <- Settlement.parse_csv(params["text"]),
         {:ok, _buckets} <- Settlement.import(params["statement_id"], lines) do
      {:noreply,
       socket
       |> put_flash(:info, gettext("Imported %{count} line(s).", count: length(lines)))
       |> assign(:form, form())
       |> push_patch(
         to:
           ~p"/admin/settlements?statement=#{params["statement_id"]}&received=#{params["received"]}"
       )}
    else
      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not import that statement."))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Settlements")}
      admin={:settlements}
    >
      <section class="vn-card" id="import-card">
        <h2>{gettext("Import a statement")}</h2>
        <p class="vn-muted">
          {gettext(
            "CSV with a header row: malipo_id (or provider_ref), receipt, gross, fee, net, settled_on."
          )}
        </p>
        <.form for={@form} id="settlement-form" phx-submit="import">
          <.input field={@form[:statement_id]} label={gettext("Statement id")} />
          <.input
            field={@form[:received]}
            label={gettext("Received (shillings)")}
            inputmode="numeric"
          />
          <.input field={@form[:text]} type="textarea" rows="8" label={gettext("Statement")} />
          <button class="vn-button" id="settlement-import">{gettext("Import")}</button>
        </.form>
      </section>

      <section :if={@statements != []} class="vn-card">
        <h2>{gettext("Statements")}</h2>
        <div class="vn-chips">
          <.link
            :for={statement <- @statements}
            patch={~p"/admin/settlements?statement=#{statement}"}
            class={["vn-chip", @selected == statement && "vn-chip--on"]}
            id={"statement-#{statement}"}
          >
            {statement}
          </.link>
        </div>
      </section>

      <section :if={@buckets} class="vn-card" id="buckets">
        <h2>{gettext("Buckets")}</h2>
        <ul class="vn-stats">
          <li :for={{kind, label} <- @bucket_labels} id={"bucket-#{kind}"}>
            <span class="vn-muted">{label}</span>
            <span class="vn-stat__value">{Map.get(@buckets.counts, kind, 0)}</span>
          </li>
        </ul>

        <dl class="vn-detail">
          <dt>{gettext("Gross")}</dt>
          <dd>{kes(@buckets.gross_cents)}</dd>
          <dt>{gettext("Fees")}</dt>
          <dd>{kes(@buckets.fee_cents)}</dd>
          <dt>{gettext("Net expected")}</dt>
          <dd id="net-expected">{kes(@buckets.net_cents)}</dd>
          <dt :if={@received}>{gettext("Payout delta")}</dt>
          <dd :if={@received} id="payout-delta">{kes(@delta)}</dd>
        </dl>

        <div :for={{kind, label} <- @bucket_labels} :if={bucket = @buckets.by_kind[kind]}>
          <h3>{label}</h3>
          <div class="vn-scroll">
            <table class="vn-table">
              <thead>
                <tr>
                  <th>{gettext("Reference")}</th>
                  <th>{gettext("Receipt")}</th>
                  <th>{gettext("Gross")}</th>
                  <th>{gettext("Fee")}</th>
                  <th>{gettext("Settled on")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={line <- bucket} id={"line-#{line.id}"}>
                  <td>{line.provider_ref}</td>
                  <td>{line.receipt}</td>
                  <td>{kes(line.gross_cents)}</td>
                  <td>{kes(line.fee_cents)}</td>
                  <td>{line.settled_on}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load(socket) do
    statements = Settlement.statements()
    selected = socket.assigns[:selected] || List.first(statements)
    buckets = if selected, do: Settlement.buckets(selected), else: nil

    delta =
      if selected && socket.assigns[:received],
        do: Settlement.payout_delta(selected, socket.assigns.received),
        else: nil

    assign(socket,
      statements: statements,
      selected: selected,
      buckets: buckets,
      delta: delta
    )
  end

  defp form do
    to_form(%{"statement_id" => "", "received" => "", "text" => ""}, as: "settlement")
  end

  defp shillings_to_cents(value) when is_binary(value) do
    case Decimal.parse(String.trim(value)) do
      {decimal, ""} ->
        decimal |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_integer()

      _ ->
        nil
    end
  end

  defp shillings_to_cents(_value), do: nil

  defp kes(nil), do: "—"
  defp kes(cents), do: Pricing.format_kes_cents(cents)
end
