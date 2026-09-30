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

  @doc "The waiting state: a prompt is on the phone."
  attr :amount_cents, :integer, required: true
  attr :phone, :string, required: true

  def waiting(assigns) do
    ~H"""
    <section class="vn-sheet" id="payment-sheet">
      <p class="vn-muted">{gettext("A prompt is on your phone")}</p>
      <p class="vn-sheet__amount">{format_kes_cents(@amount_cents)}</p>
      <p class="vn-sheet__note">
        {gettext("Enter your M-Pesa PIN on %{phone} to confirm.", phone: @phone)}
      </p>
      <p class="vn-sheet__waiting">
        <span class="vn-pulse" aria-hidden="true"></span>
        <span class="vn-muted">{gettext("Waiting for M-Pesa…")}</span>
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

  def failed(assigns) do
    ~H"""
    <section class="vn-sheet" id="payment-failed">
      <p class="vn-sheet__amount">{format_kes_cents(@amount_cents)}</p>
      <p class="vn-error">
        {@failure || gettext("The payment did not go through.")}
      </p>
      <p class="vn-muted">{gettext("Nothing was charged. You can try again.")}</p>
      <button class="vn-button" phx-click="retry" id="payment-retry">
        {gettext("Try again")}
      </button>
      <.link navigate={~p"/orders"} class="vn-button vn-button--muted">
        {gettext("Back to orders")}
      </.link>
    </section>
    """
  end

  @doc "The success state: paid, with the receipt."
  attr :title, :string, required: true
  attr :amount_cents, :integer, default: nil
  attr :receipt, :string, default: nil

  def succeeded(assigns) do
    ~H"""
    <section class="vn-sheet" id="payment-succeeded">
      <p class="vn-muted">{@title}</p>
      <p :if={@amount_cents} class="vn-sheet__amount">{format_kes_cents(@amount_cents)}</p>
      <dl :if={@receipt} class="vn-detail">
        <dt>{gettext("M-Pesa receipt")}</dt>
        <dd>{@receipt}</dd>
      </dl>
      <p class="vn-muted">
        {gettext("We're starting your order now. You'll see it move on the Orders tab.")}
      </p>
      <.link navigate={~p"/orders"} class="vn-button">{gettext("See your orders")}</.link>
    </section>
    """
  end
end
