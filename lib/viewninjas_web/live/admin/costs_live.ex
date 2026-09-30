defmodule ViewNinjasWeb.Admin.CostsLive do
  @moduledoc """
  Costs and targets (scope.md §11; build-plan.md M10). Super-admin only: the
  money knobs' neighbours are the shop's own costs and the goals it is judged
  against, and both are the super-admin's to set.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.{Costs, Pricing, Progress}
  alias ViewNinjas.Insight.{Cost, Target}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Costs and targets"))
     |> assign(:cost_form, cost_form())
     |> assign(:target_form, target_form())
     |> load()}
  end

  @impl true
  def handle_event("add_cost", %{"cost" => params}, socket) do
    case Costs.create_cost(cost_attrs(params), actor(socket)) do
      {:ok, _cost} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Cost recorded."))
         |> assign(:cost_form, cost_form())
         |> load()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Check the amount and the date."))}
    end
  end

  def handle_event("add_target", %{"target" => params}, socket) do
    case Progress.create_target(target_attrs(params), actor(socket)) do
      {:ok, _target} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Target set."))
         |> assign(:target_form, target_form())
         |> load()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Check the goal."))}
    end
  end

  def handle_event("delete_cost", %{"id" => id}, socket) do
    case Costs.get_cost(id) do
      nil -> {:noreply, socket}
      cost -> {:noreply, socket |> remove(cost) |> load()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      title={gettext("Costs and targets")}
      admin={:costs}
    >
      <section class="vn-card" id="cost-form-card">
        <h2>{gettext("Record a cost")}</h2>
        <.form for={@cost_form} id="cost-form" phx-submit="add_cost">
          <.input
            field={@cost_form[:kind]}
            type="select"
            label={gettext("Kind")}
            options={Enum.map(Cost.kinds(), &{to_string(&1), &1})}
          />
          <.input
            field={@cost_form[:amount]}
            label={gettext("Amount (shillings)")}
            inputmode="numeric"
          />
          <.input field={@cost_form[:incurred_on]} type="date" label={gettext("Incurred on")} />
          <.input field={@cost_form[:note]} label={gettext("Note")} />
          <button class="vn-button" id="cost-submit">{gettext("Add cost")}</button>
        </.form>
      </section>

      <section class="vn-card">
        <h2>{gettext("Costs")}</h2>
        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>{gettext("Day")}</th>
                <th>{gettext("Kind")}</th>
                <th>{gettext("Amount")}</th>
                <th>{gettext("Note")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={cost <- @costs} id={"cost-#{cost.id}"}>
                <td>{cost.incurred_on}</td>
                <td>{cost.kind}</td>
                <td>{kes(cost.amount_cents)}</td>
                <td>{cost.note}</td>
                <td>
                  <button
                    class="vn-button vn-button--muted"
                    phx-click="delete_cost"
                    phx-value-id={cost.id}
                    id={"delete-cost-#{cost.id}"}
                  >
                    {gettext("Remove")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@costs == []} class="vn-muted">{gettext("No costs yet.")}</p>
      </section>

      <section class="vn-card" id="target-form-card">
        <h2>{gettext("Set a target")}</h2>
        <.form for={@target_form} id="target-form" phx-submit="add_target">
          <.input
            field={@target_form[:metric]}
            type="select"
            label={gettext("Metric")}
            options={Enum.map(Target.metrics(), &{Progress.label(&1), &1})}
          />
          <.input
            field={@target_form[:period]}
            type="select"
            label={gettext("Period")}
            options={Enum.map(Target.periods(), &{to_string(&1), &1})}
          />
          <.input
            field={@target_form[:value]}
            label={gettext("Goal (shillings, a count, or a percent)")}
            inputmode="decimal"
          />
          <button class="vn-button" id="target-submit">{gettext("Set target")}</button>
        </.form>
      </section>

      <section class="vn-card">
        <h2>{gettext("Targets in force")}</h2>
        <div class="vn-scroll">
          <table class="vn-table">
            <thead>
              <tr>
                <th>{gettext("Metric")}</th>
                <th>{gettext("Period")}</th>
                <th>{gettext("Goal")}</th>
                <th>{gettext("Set")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={target <- @targets} id={"target-#{target.id}"}>
                <td>{Progress.label(target.metric)}</td>
                <td>{target.period}</td>
                <td>{Progress.format(target.metric, target.value_cents)}</td>
                <td>{format_at(target.effective_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@targets == []} class="vn-muted">{gettext("No targets yet.")}</p>
      </section>
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load(socket) do
    assign(socket, costs: Costs.list_costs(), targets: Progress.current_targets())
  end

  defp cost_form do
    to_form(
      %{
        "kind" => "hosting",
        "amount" => "",
        "incurred_on" => Date.to_iso8601(Date.utc_today()),
        "note" => ""
      },
      as: "cost"
    )
  end

  defp target_form do
    to_form(%{"metric" => "revenue", "period" => "month", "value" => ""}, as: "target")
  end

  defp cost_attrs(params) do
    %{
      "kind" => params["kind"],
      "amount_cents" => shillings_to_cents(params["amount"]),
      "incurred_on" => params["incurred_on"],
      "note" => blank_to_nil(params["note"])
    }
  end

  defp target_attrs(params) do
    metric = params["metric"]

    %{
      "metric" => metric,
      "period" => params["period"],
      "value_cents" => goal_value(metric, params["value"])
    }
  end

  defp goal_value("revenue", value), do: shillings_to_cents(value)
  defp goal_value("margin", value), do: percent_to_bps(value)
  defp goal_value(_metric, value), do: to_integer(value)

  defp shillings_to_cents(value) do
    case to_integer(value) do
      nil -> nil
      shillings -> shillings * 100
    end
  end

  defp percent_to_bps(value) do
    case to_integer(value) do
      nil -> nil
      percent -> percent * 100
    end
  end

  defp to_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(_value), do: nil

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp remove(socket, %Cost{} = cost) do
    case Costs.delete_cost(cost) do
      {:ok, _} -> put_flash(socket, :info, gettext("Cost removed."))
      {:error, _} -> put_flash(socket, :error, gettext("Could not remove that cost."))
    end
  end

  defp actor(socket), do: socket.assigns.current_scope.user
  defp kes(cents), do: Pricing.format_kes_cents(cents)
  defp format_at(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
end
