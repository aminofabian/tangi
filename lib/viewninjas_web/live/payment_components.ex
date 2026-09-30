defmodule ViewNinjasWeb.PaymentComponents do
  @moduledoc """
  The full-screen M-Pesa payment sheet (scope.md §12): one calm instruction, the
  amount, and a waiting state fed by PubSub — never a spinner, and a retry that
  starts a **new** attempt rather than sending a second prompt.

  Shared by the order checkout and the wallet top-up, because the customer should
  not be able to tell which one they are in.
  """
  use ViewNinjasWeb, :html

  import ViewNinjas.Pricing, only: [format_kes_cents: 1]

  @doc "The waiting state. The prompt copy appears only after the rail has accepted the payment."
  attr :amount_cents, :integer, required: true
  attr :phone, :string, required: true
  attr :prompted, :boolean, default: false

  def waiting(assigns) do
    ~H"""
    <section class="vn-sheet" id="payment-sheet">
      <div class={["vn-handset", @prompted && "vn-handset--live"]} aria-hidden="true">
        <span class="vn-handset__ring"></span>
        <span class="vn-handset__ring vn-handset__ring--late"></span>
        <span class="vn-handset__notch"></span>
        <div class="vn-handset__screen">
          <span class="vn-handset__card">
            <span class="vn-handset__mark"></span>
            {gettext("M-Pesa")}
          </span>
        </div>
      </div>
      <p class="vn-muted">
        <%= if @prompted do %>
          {gettext("A prompt is on your phone")}
        <% else %>
          {gettext("Sending the prompt…")}
        <% end %>
      </p>
      <p class="vn-sheet__amount">{format_kes_cents(@amount_cents)}</p>
      <p :if={@prompted} class="vn-sheet__note">
        {gettext("Enter your M-Pesa PIN on %{phone} to confirm.", phone: @phone)}
      </p>
      <p class="vn-sheet__waiting">
        <span class="vn-pulse" aria-hidden="true"></span>
        <span class="vn-muted">
          <%= if @prompted do %>
            {gettext("Waiting for M-Pesa…")}
          <% else %>
            {gettext("Contacting the payment rail…")}
          <% end %>
        </span>
      </p>
      <p class="vn-muted">
        {gettext("Leave this screen open. It updates the moment the money lands.")}
      </p>
    </section>
    """
  end

  @doc "The failure state: nothing was charged, and a retry is a new attempt."
  attr :amount_cents, :integer, required: true
  attr :failure, :string, default: nil
  attr :closer, :string, default: nil

  def failed(assigns) do
    ~H"""
    <section class="vn-sheet vn-sheet--miss" id="payment-failed">
      <p class="vn-sheet__amount">{format_kes_cents(@amount_cents)}</p>
      <p class="vn-error">
        {@failure || gettext("The payment did not go through.")}
      </p>
      <p class="vn-muted">{gettext("Nothing was charged. You can try again.")}</p>
      <button class="vn-button" phx-click="retry" id="payment-retry">
        {gettext("Try again")}
      </button>
      <button :if={@closer} class="vn-button vn-button--muted" phx-click={@closer} id="payment-close">
        {gettext("Back to wallet")}
      </button>
      <.link :if={!@closer} navigate={~p"/orders"} class="vn-button vn-button--muted">
        {gettext("Back to orders")}
      </.link>
    </section>
    """
  end

  @doc "The success state: paid, with the receipt. `celebrate` is the wallet burst."
  attr :title, :string, required: true
  attr :amount_cents, :integer, default: nil
  attr :receipt, :string, default: nil
  attr :celebrate, :boolean, default: false
  attr :balance, :string, default: nil
  attr :closer, :string, default: nil

  def succeeded(assigns) do
    ~H"""
    <section class={["vn-sheet", @celebrate && "vn-sheet--landed"]} id="payment-succeeded">
      <div :if={@celebrate} class="vn-fireworks" aria-hidden="true">
        <span
          :for={spark <- sparks()}
          style={"--x: #{spark.x}; --y: #{spark.y}; --c: #{spark.c}; --d: #{spark.d}"}
        ></span>
      </div>
      <p :if={@celebrate} class="vn-sheet__coin" aria-hidden="true"></p>
      <p class="vn-muted">{@title}</p>
      <p :if={@amount_cents} class="vn-sheet__amount">{format_kes_cents(@amount_cents)}</p>
      <dl :if={@receipt} class="vn-detail">
        <dt>{gettext("M-Pesa receipt")}</dt>
        <dd>{@receipt}</dd>
      </dl>
      <p :if={@celebrate && @balance} class="vn-muted">
        {gettext("Your wallet now holds %{balance}.", balance: @balance)}
      </p>
      <p :if={!@celebrate} class="vn-muted">
        {gettext("We're starting your order now. You'll see it move on the Orders tab.")}
      </p>
      <button :if={@closer} class="vn-button" phx-click={@closer} id="topup-done">
        {gettext("Back to wallet")}
      </button>
      <.link :if={!@closer} navigate={~p"/orders"} class="vn-button">{gettext("See your orders")}</.link>
    </section>
    """
  end

  # Two waves of brand-coloured sparks. Positions are offsets from the coin.
  defp sparks do
    [
      %{x: "-6.2rem", y: "-7.4rem", c: "var(--tangi-pink)", d: "0s"},
      %{x: "5.8rem", y: "-7.8rem", c: "var(--tangi-yellow)", d: "0.04s"},
      %{x: "-2rem", y: "-9rem", c: "var(--tangi-cyan)", d: "0.08s"},
      %{x: "2.4rem", y: "-8.6rem", c: "var(--tangi-purple)", d: "0.02s"},
      %{x: "-7.4rem", y: "-2.2rem", c: "var(--tangi-blue)", d: "0.1s"},
      %{x: "7.2rem", y: "-2.6rem", c: "var(--tangi-pink)", d: "0.06s"},
      %{x: "-4.6rem", y: "-4.8rem", c: "var(--tangi-yellow)", d: "0.12s"},
      %{x: "4.8rem", y: "-4.2rem", c: "var(--tangi-cyan)", d: "0.14s"},
      %{x: "0rem", y: "-9.4rem", c: "var(--tangi-blue)", d: "0.7s"},
      %{x: "-5.4rem", y: "-6.2rem", c: "var(--tangi-purple)", d: "0.74s"},
      %{x: "5.6rem", y: "-6rem", c: "var(--tangi-pink)", d: "0.78s"},
      %{x: "-8rem", y: "-4rem", c: "var(--tangi-yellow)", d: "0.72s"},
      %{x: "7.8rem", y: "-4.4rem", c: "var(--tangi-cyan)", d: "0.8s"},
      %{x: "-3rem", y: "-7.6rem", c: "var(--tangi-blue)", d: "0.76s"},
      %{x: "3.2rem", y: "-8rem", c: "var(--tangi-purple)", d: "0.82s"},
      %{x: "0.6rem", y: "-5.2rem", c: "var(--tangi-yellow)", d: "0.68s"}
    ]
  end
end
