defmodule ViewNinjasWeb.CheckoutLive do
  @moduledoc """
  Checkout and the M-Pesa sheet (scope.md §8, §12).

  Two ways to pay, one page. **Pay with M-Pesa** starts an attempt and shows the
  sheet; the money moves only when a confirming `GET` says `settled`, which flips
  the sheet over PubSub. **Pay from the wallet** debits the ledger and marks the
  order paid in one transaction, with no prompt at all.

  The account's phone must be verified first, because that is where the prompt
  goes. A failure leaves the order exactly where it was — `awaiting_payment` —
  and a retry is a new attempt with a new idempotency key, never a second prompt
  on the same one.
  """
  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.PaymentComponents

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Orders
  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.RateLimit
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.CreatePayment
  alias ViewNinjasWeb.Analytics

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:order, nil)
     |> assign(:payment, nil)
     |> assign(:mode, :review)
     |> assign(:failure, nil)
     |> assign(:receipt, nil)
     |> assign(:wallet_balance, 0)
     |> assign(:payments_configured, Payments.configured?())}
  end

  @impl true
  def handle_params(%{"order_id" => order_id}, uri, socket) do
    Analytics.record_page_view(socket, uri)
    user = socket.assigns.current_scope.user

    case Orders.get_order_for_user(user, parse_id(order_id)) do
      nil -> {:noreply, push_navigate(socket, to: ~p"/orders")}
      order -> {:noreply, load(socket, order)}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, push_navigate(socket, to: ~p"/orders")}

  @impl true
  def handle_event("pay_mpesa", _params, socket) do
    with :ok <- check_limits(socket),
         {:ok, payment} <- start_attempt(socket) do
      {:noreply, watch(socket, payment)}
    else
      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many attempts just now — try again shortly."))}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not start the payment."))}
    end
  end

  @impl true
  def handle_event("retry", params, socket), do: handle_event("pay_mpesa", params, socket)

  def handle_event("pay_wallet", _params, socket) do
    case Orders.pay_from_wallet(socket.assigns.order) do
      {:ok, order} ->
        {:noreply, socket |> assign(:order, order) |> assign(:mode, :succeeded)}

      {:error, :insufficient_funds} ->
        {:noreply, put_flash(socket, :error, gettext("Your wallet does not cover this order."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not pay from the wallet just now."))}
    end
  end

  @impl true
  def handle_info({:payment, %Payment{id: payment_id} = payment}, socket) do
    watched = socket.assigns.payment

    if watched && watched.id == payment_id do
      {:noreply, watch(socket, payment)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} section={:shop} title={@page_title}>
      <%= cond do %>
        <% @mode == :waiting -> %>
          <.waiting amount_cents={@payment.amount_cents} phone={phone(@current_scope.user)} />
        <% @mode == :succeeded -> %>
          <.succeeded
            title={gettext("Paid")}
            amount_cents={@order.retail_cents}
            receipt={@receipt}
          />
        <% @mode == :failed -> %>
          <.failed amount_cents={@payment.amount_cents} failure={@failure} />
        <% true -> %>
          <.review
            order={@order}
            user={@current_scope.user}
            wallet_balance={@wallet_balance}
            payments_configured={@payments_configured}
          />
      <% end %>
    </Layouts.app>
    """
  end

  # -- the review step ---------------------------------------------------

  attr :order, :map, required: true
  attr :user, :map, required: true
  attr :wallet_balance, :integer, required: true
  attr :payments_configured, :boolean, required: true

  defp review(assigns) do
    ~H"""
    <section class="vn-card" id="order-summary">
      <h2>{order_title(@order)}</h2>
      <dl class="vn-detail">
        <dt>{gettext("Grade")}</dt>
        <dd>{@order.lane.grade}</dd>
        <dt>{gettext("How many")}</dt>
        <dd>{@order.quantity}</dd>
        <dt>{gettext("Link")}</dt>
        <dd class="vn-breakall">{@order.link}</dd>
        <dt>{gettext("Total")}</dt>
        <dd>
          <span class="vn-total__value">{kes(@order.retail_cents)}</span>
        </dd>
      </dl>
    </section>

    <section :if={is_nil(@user.phone_verified_at)} class="vn-card" id="verify-first">
      <h2>{gettext("Verify your phone to pay")}</h2>
      <p class="vn-muted">
        {gettext("The M-Pesa prompt goes to your phone, so we have to prove it is yours first.")}
      </p>
      <.link navigate={~p"/users/verify-phone"} class="vn-button">{gettext("Verify now")}</.link>
    </section>

    <section :if={@user.phone_verified_at} class="vn-card">
      <h2>{gettext("Pay")}</h2>
      <p :if={not @payments_configured} class="vn-error" id="payments-unconfigured">
        {gettext("Payments are not configured yet, so this order cannot be paid for.")}
      </p>
      <p :if={@payments_configured} class="vn-muted">
        {gettext("The prompt goes to %{phone}.", phone: phone(@user))}
      </p>
      <div :if={@payments_configured} class="flex flex-col gap-2">
        <button class="vn-button" phx-click="pay_mpesa" id="pay-mpesa">
          {gettext("Pay %{amount} with M-Pesa", amount: kes(@order.retail_cents))}
        </button>
        <button
          :if={@wallet_balance >= @order.retail_cents}
          class="vn-button vn-button--muted"
          phx-click="pay_wallet"
          id="pay-wallet"
        >
          {gettext("Pay from wallet (%{balance})", balance: kes(@wallet_balance))}
        </button>
      </div>
      <p :if={@payments_configured} class="vn-muted mt-3">
        {gettext("Nothing is sent to the supplier until the payment settles.")}
      </p>
    </section>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load(socket, order) do
    user = socket.assigns.current_scope.user

    socket
    |> assign(:page_title, gettext("Checkout"))
    |> assign(:order, order)
    |> assign(:wallet_balance, Wallet.balance(user))
    |> resume_or_review(order)
  end

  defp resume_or_review(socket, %{state: :paid} = order) do
    assign(socket, mode: :succeeded, order: order, payment: nil)
  end

  defp resume_or_review(socket, order) do
    case Payments.pending_for_order(order) do
      nil -> assign(socket, mode: :review, payment: nil)
      payment -> watch(socket, payment)
    end
  end

  defp watch(socket, nil), do: assign(socket, mode: :review, payment: nil)

  defp watch(socket, %Payment{status: :settled} = payment) do
    # The success screen needs the amount (already on the order we loaded) and the
    # receipt — no extra read, so a PubSub flip costs nothing.
    socket
    |> assign(:order, socket.assigns.order)
    |> assign(:payment, payment)
    |> assign(:receipt, payment.receipt)
    |> assign(:mode, :succeeded)
  end

  defp watch(socket, %Payment{status: :failed} = payment) do
    socket
    |> assign(:payment, payment)
    |> assign(:failure, Payments.failure_copy(payment.failure_kind, payment.failure_message))
    |> assign(:mode, :failed)
  end

  defp watch(socket, %Payment{} = payment) do
    if socket.assigns[:watching] != payment.id do
      Payments.subscribe(payment.id)
    end

    socket
    |> assign(:payment, payment)
    |> assign(:watching, payment.id)
    |> assign(:mode, :waiting)
  end

  defp start_attempt(socket) do
    with {:ok, payment} <- Payments.start_order_payment(socket.assigns.order),
         {:ok, _job} <- CreatePayment.new(%{payment_id: payment.id}) |> Oban.insert() do
      {:ok, payment}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset_message(changeset)}
      {:error, _reason} -> {:error, :enqueue_failed}
    end
  end

  defp check_limits(socket) do
    user = socket.assigns.current_scope.user

    if RateLimit.allow?("payment:user:#{user.id}", :payment_user) and
         RateLimit.allow?("payment:phone:#{user.phone}", :payment_phone) do
      :ok
    else
      {:error, :rate_limited}
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp phone(user), do: Phone.format(user.phone)

  defp order_title(%{lane: %{offer: %{title: title}}}), do: title
  defp order_title(_order), do: gettext("Your order")

  defp kes(cents), do: ViewNinjas.Pricing.format_kes_cents(cents)

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
