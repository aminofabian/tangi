defmodule ViewNinjasWeb.CheckoutLive do
  @moduledoc """
  Checkout and the M-Pesa sheet (scope.md §8, §12).

  Two ways to pay, and either one of them. **Pay with M-Pesa** starts an attempt and
  shows the sheet; the money moves only when a confirming `GET` says `settled`,
  which flips the sheet over PubSub. **Pay from the wallet** debits the ledger and
  marks the order paid in one transaction, with no prompt at all. When the wallet
  is short, a third button tops it up by the shortfall (the same prompt) and hands
  the buyer the wallet button back.

  Phone verification is not required to buy. The prompt starts on the account's
  number, and the buyer can change it — pay, or top the wallet up, from another
  phone. The wallet is offered whenever its balance covers the order. A failure
  leaves the order exactly where it was — `awaiting_payment` — and a retry is a
  new attempt with a new idempotency key, never a second prompt on the same one.
  """
  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.JourneyComponents
  import ViewNinjasWeb.PaymentComponents

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Catalog.Grade
  alias ViewNinjas.Orders
  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.RateLimit
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.CreatePayment
  alias ViewNinjasWeb.Analytics

  # The wallet will not take a smaller top-up than this (matches the wallet screen).
  @min_topup_cents 1_000

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
     |> assign(:phone_form, phone_form(""))
     |> assign(:phone_error, nil)
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
  def handle_event("set_phone", %{"prompt" => %{"phone" => phone}}, socket) do
    {:noreply, socket |> assign(:phone_form, phone_form(phone)) |> assign(:phone_error, nil)}
  end

  def handle_event("pay_mpesa", _params, socket) do
    with {:ok, phone} <- prompt_phone(socket),
         :ok <- check_limits(socket, phone),
         {:ok, payment} <- start_attempt(socket, phone) do
      {:noreply, assign(socket, :phone_error, nil) |> watch(payment)}
    else
      {:error, :invalid_phone} ->
        {:noreply, assign(socket, :phone_error, invalid_phone())}

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

  @impl true
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

  # The other way to buy: top the wallet up by the shortfall (same M-Pesa prompt), and
  # the order is then paid from the wallet — one purchase, either route.
  def handle_event("topup", _params, socket) do
    amount = topup_amount(socket)

    with {:ok, phone} <- prompt_phone(socket),
         :ok <- check_limits(socket, phone),
         {:ok, payment} <- start_topup(socket, amount, phone) do
      {:noreply, assign(socket, :phone_error, nil) |> watch(payment)}
    else
      {:error, :invalid_phone} ->
        {:noreply, assign(socket, :phone_error, invalid_phone())}

      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many attempts just now — try again shortly."))}

      {:error, message} when is_binary(message) ->
        {:noreply, put_flash(socket, :error, message)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not start the top-up just now."))}
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
          <.waiting
            amount_cents={@payment.amount_cents}
            phone={Phone.format(Payments.prompted_phone(@payment))}
            prompted={not is_nil(@payment.malipo_payment_id)}
          />
        <% @mode == :succeeded -> %>
          <.succeeded
            title={gettext("Paid")}
            amount_cents={@order.retail_cents}
            receipt={@receipt}
            celebrate={true}
            next={~p"/orders/#{@order.id}"}
            next_label={gettext("Watch it arrive")}
          />
        <% @mode == :failed -> %>
          <.failed amount_cents={@payment.amount_cents} failure={@failure} />
        <% true -> %>
          <.review
            order={@order}
            phone_form={@phone_form}
            phone_error={@phone_error}
            wallet_balance={@wallet_balance}
            payments_configured={@payments_configured}
          />
      <% end %>
    </Layouts.app>
    """
  end

  # -- the review step ---------------------------------------------------

  attr :order, :map, required: true
  attr :phone_form, :map, required: true
  attr :phone_error, :string, default: nil
  attr :wallet_balance, :integer, required: true
  attr :payments_configured, :boolean, required: true

  defp review(assigns) do
    ~H"""
    <div class="vn-checkout" id="checkout">
      <.journey step={:pay} />

      <section class="vn-card vn-ticket vn-arrive" id="order-summary">
        <h2>{order_title(@order)}</h2>
        <dl class="vn-detail">
          <dt>{gettext("Grade")}</dt>
          <dd>{Grade.label(@order.lane.grade)}</dd>
          <dt>{gettext("How many")}</dt>
          <dd>{@order.quantity}</dd>
          <dt>{gettext("Link")}</dt>
          <dd class="vn-breakall">{@order.link}</dd>
        </dl>
        <p class="vn-ticket__total">
          <span class="vn-muted">{gettext("Total")}</span>
          <span class="vn-total__value">{kes(@order.retail_cents)}</span>
        </p>
      </section>

      <section class="vn-card vn-arrive vn-arrive--late" id="pay">
        <header class="vn-checkout__head">
          <h2>{gettext("Pay")}</h2>
          <p class="vn-muted">{pay_lead(@order, @wallet_balance)}</p>
        </header>

        <div class="vn-checkout__wallet">
          <p class="vn-meter__label">
            <span>{gettext("Wallet")}</span>
            <span>
              {kes(@wallet_balance)}
              <span class="vn-muted">/ {kes(@order.retail_cents)}</span>
            </span>
          </p>
          <div
            class={["vn-meter", wallet_covers?(@order, @wallet_balance) && "vn-meter--full"]}
            id="wallet-meter"
            aria-hidden="true"
          >
            <span style={"--fill: #{coverage_pct(@order, @wallet_balance)}%"}></span>
          </div>
        </div>

        <p :if={not @payments_configured} class="vn-error" id="payments-unconfigured">
          {gettext(
            "Payments need the secret key that starts with sk_live_. The client id cannot take a payment."
          )}
        </p>

        <div :if={@payments_configured} class="vn-checkout__prompt">
          <hr class="vn-checkout__rule" />
          <.form for={@phone_form} id="prompt-form" phx-change="set_phone">
            <.input
              field={@phone_form[:phone]}
              type="tel"
              inputmode="tel"
              autocomplete="tel"
              label={gettext("M-Pesa number")}
              id="prompt-phone"
            />
            <div class="vn-checkout__phone-meta">
              <p class="vn-checkout__hint" id="prompt-hint">
                {gettext(
                  "The prompt goes to this number. Change it to pay or top up from another phone."
                )}
              </p>
              <span :if={network_label(@phone_form)} class="vn-badge vn-badge--ok" id="prompt-network">
                {network_label(@phone_form)}
              </span>
            </div>
            <p :if={@phone_error} class="vn-error" id="prompt-error">{@phone_error}</p>
          </.form>
        </div>

        <div :if={@payments_configured} class="vn-checkout__actions">
          <button
            :if={wallet_covers?(@order, @wallet_balance)}
            class="vn-button"
            phx-click="pay_wallet"
            id="pay-wallet"
          >
            {gettext("Pay %{amount} from wallet", amount: kes(@order.retail_cents))}
          </button>

          <button
            class={["vn-button", wallet_covers?(@order, @wallet_balance) && "vn-button--muted"]}
            phx-click="pay_mpesa"
            id="pay-mpesa"
          >
            {gettext("Pay %{amount} with M-Pesa", amount: kes(@order.retail_cents))}
          </button>

          <button
            :if={not wallet_covers?(@order, @wallet_balance)}
            class="vn-button vn-button--muted"
            phx-click="topup"
            id="topup-wallet"
          >
            {gettext("Top up %{amount} and pay from wallet",
              amount: kes(shortfall(@order, @wallet_balance))
            )}
          </button>
        </div>

        <p :if={@payments_configured} class="vn-checkout__close vn-muted">
          {gettext("Your order starts the moment the payment settles.")}
        </p>
      </section>
    </div>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load(socket, order) do
    user = socket.assigns.current_scope.user

    socket
    |> assign(:page_title, gettext("Checkout"))
    |> assign(:order, order)
    |> assign(:wallet_balance, Wallet.balance(user))
    |> assign(:phone_form, phone_form(user))
    |> assign(:phone_error, nil)
    |> resume_or_review(order)
  end

  defp resume_or_review(socket, %{state: :paid} = order) do
    assign(socket, mode: :succeeded, order: order, payment: nil)
  end

  defp resume_or_review(socket, order) do
    case Payments.pending_for_order(order) do
      nil -> resume_topup_or_review(socket)
      payment -> watch(socket, payment)
    end
  end

  # A top-up started from checkout (or the wallet) still shows its sheet on return.
  defp resume_topup_or_review(socket) do
    case Payments.pending_topup(socket.assigns.current_scope.user) do
      nil -> assign(socket, mode: :review, payment: nil)
      payment -> watch(socket, payment)
    end
  end

  defp watch(socket, nil), do: assign(socket, mode: :review, payment: nil)

  # A top-up inside checkout is a means, not the end: credit the wallet, then hand
  # the buyer the "pay from wallet" button instead of a success screen.
  defp watch(socket, %Payment{purpose: :topup, status: :settled}) do
    socket
    |> assign(:payment, nil)
    |> assign(:wallet_balance, Wallet.balance(socket.assigns.current_scope.user))
    |> assign(:mode, :review)
    |> put_flash(:info, gettext("Top-up received — pay from your wallet below."))
  end

  defp watch(socket, %Payment{purpose: :topup, status: :failed} = payment) do
    socket
    |> assign(:payment, nil)
    |> assign(:mode, :review)
    |> put_flash(:error, Payments.failure_copy(payment.failure_kind, payment.failure_message))
  end

  defp watch(socket, %Payment{purpose: :topup} = payment), do: waiting(socket, payment)

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

  defp watch(socket, %Payment{} = payment), do: waiting(socket, payment)

  defp waiting(socket, %Payment{} = payment) do
    if socket.assigns[:watching] != payment.id do
      Payments.subscribe(payment.id)
    end

    socket
    |> assign(:payment, payment)
    |> assign(:watching, payment.id)
    |> assign(:mode, :waiting)
  end

  defp start_attempt(socket, phone) do
    with {:ok, payment} <- Payments.start_order_payment(socket.assigns.order, phone),
         {:ok, _job} <- CreatePayment.new(%{payment_id: payment.id}) |> Oban.insert() do
      {:ok, payment}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset_message(changeset)}
      {:error, _reason} -> {:error, :enqueue_failed}
    end
  end

  # One top-up at a time: a pending one is reused rather than prompting twice.
  defp start_topup(socket, amount, phone) do
    user = socket.assigns.current_scope.user

    case Payments.pending_topup(user) do
      %Payment{} = pending ->
        {:ok, pending}

      nil ->
        with {:ok, payment} <- Payments.start_topup_payment(user, amount, phone),
             {:ok, _job} <- CreatePayment.new(%{payment_id: payment.id}) |> Oban.insert() do
          {:ok, payment}
        else
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset_message(changeset)}
          {:error, _reason} -> {:error, :enqueue_failed}
        end
    end
  end

  defp topup_amount(socket) do
    shortfall(socket.assigns.order, socket.assigns.wallet_balance)
  end

  defp wallet_covers?(order, balance), do: balance >= order.retail_cents

  defp coverage_pct(%{retail_cents: cents}, _balance) when cents <= 0, do: 0

  defp coverage_pct(%{retail_cents: cents}, balance) do
    div(min(balance, cents) * 100, cents)
  end

  defp shortfall(order, balance), do: max(order.retail_cents - balance, @min_topup_cents)

  # Budgeted per customer and per prompted number. A changed phone must not
  # become a way to spam one line.
  defp check_limits(socket, phone) do
    user = socket.assigns.current_scope.user

    if RateLimit.allow?("payment:user:#{user.id}", :payment_user) and
         RateLimit.allow?("payment:phone:#{phone}", :payment_phone) do
      :ok
    else
      {:error, :rate_limited}
    end
  end

  defp phone_form(%{phone: phone}), do: phone_form(Phone.format(phone) || "")
  defp phone_form(phone) when is_binary(phone), do: to_form(%{"phone" => phone}, as: :prompt)

  defp prompt_phone(socket) do
    case Phone.normalize(socket.assigns.phone_form[:phone].value) do
      {:ok, phone} -> {:ok, phone}
      {:error, :invalid_phone} -> {:error, :invalid_phone}
    end
  end

  defp invalid_phone do
    gettext("Enter a valid M-Pesa number, e.g. 0712 345 678.")
  end

  defp network_label(form) do
    form[:phone].value |> Phone.network() |> Phone.network_name()
  end

  defp pay_lead(order, balance) do
    if wallet_covers?(order, balance) do
      gettext(
        "Your wallet covers this. Pay from it with no prompt, or send M-Pesa to the number below."
      )
    else
      gettext("Send the prompt to the number below — yours, or another phone.")
    end
  end

  defp parse_id(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp order_title(%{lane: %{offer: %{title: title}}}), do: title
  defp order_title(_order), do: gettext("Your order")

  defp kes(cents), do: ViewNinjas.Pricing.format_kes_cents(cents)

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
