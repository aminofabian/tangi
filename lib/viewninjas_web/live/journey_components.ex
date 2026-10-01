defmodule ViewNinjasWeb.JourneyComponents do
  @moduledoc """
  The buyer's path: Choose, then Pay, then Watch.

  The same rail sits on the offer, the checkout and the order, so the three
  screens read as one journey. A second rail — Paid, Sent, Arriving, Here —
  draws the delivery once the money has landed.
  """
  use ViewNinjasWeb, :html

  attr :step, :atom, required: true, values: [:choose, :pay, :watch]
  attr :signed_in?, :boolean, default: true

  def journey(assigns) do
    ~H"""
    <.path
      id="journey"
      label={gettext("Your order")}
      current={step_index(@step)}
      steps={buy_steps()}
      caption={caption(@step, @signed_in?)}
    />
    """
  end

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :steps, :list, required: true
  attr :current, :integer, required: true
  attr :caption, :string, default: nil

  def path(assigns) do
    ~H"""
    <div class="vn-path-wrap" id={@id}>
      <ol class="vn-path" style={"--steps: #{length(@steps)}"} aria-label={@label}>
        <li
          :for={{step, index} <- Enum.with_index(@steps)}
          class={stop_class(index, @current)}
          style={"--i: #{index}"}
          aria-current={if(index == @current, do: "step")}
        >
          <span class="vn-path__dot" aria-hidden="true"></span>
          <span class="vn-path__label">{step.label}</span>
        </li>
      </ol>
      <p :if={@caption} class="vn-path__now" id={"#{@id}-now"}>{@caption}</p>
    </div>
    """
  end

  defp buy_steps do
    [
      %{label: gettext("Choose")},
      %{label: gettext("Pay")},
      %{label: gettext("Watch")}
    ]
  end

  defp step_index(:choose), do: 0
  defp step_index(:pay), do: 1
  defp step_index(:watch), do: 2

  defp caption(:choose, true) do
    gettext("Pick a grade, paste the link, and watch the price.")
  end

  defp caption(:choose, false) do
    gettext("Pick a grade and a link. You'll make an account, then pay.")
  end

  defp caption(:pay, _signed_in?) do
    gettext("One tap from here. Your wallet goes first when it covers the order.")
  end

  defp caption(:watch, _signed_in?) do
    gettext("Paid. Stay here and watch it move.")
  end

  defp stop_class(index, current) do
    [
      "vn-path__stop",
      index < current && "vn-path__stop--done",
      index == current && "vn-path__stop--now"
    ]
  end
end
