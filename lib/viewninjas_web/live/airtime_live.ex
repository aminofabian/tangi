defmodule ViewNinjasWeb.AirtimeLive do
  @moduledoc """
  Buying airtime (scope: `docs/instalipa-airtime.md` §8).

  One number or a bulk list, paid from the wallet, with a running total so nothing
  irreversible is a surprise. The numbers you buy for are **remembered as you buy** —
  there is no separate "save" step — and offered back for the next time.

  When the wallet is short the buy does not dead-end: the shortfall is raised with
  M-Pesa, or the customer deposits more and keeps the rest. Either way the airtime
  goes out the moment the wallet can cover it.
  """

  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.PaymentComponents

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Airtime
  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Pricing
  alias ViewNinjas.RateLimit
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.CreatePayment
  alias ViewNinjasWeb.Analytics

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:mode, :idle)
     |> assign(:payment, nil)
     |> assign(:intent, nil)
     |> assign(:form, buy_form("", ""))
     |> assign(:error, nil)
     |> assign(:purchased, [])
     |> assign(:preview, %{})
     |> load_wallet()
     |> load_saved()
     |> load_recent()
     |> refresh_preview()}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    Analytics.record_page_view(socket, uri)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"airtime" => params}, socket) do
    {:noreply, socket |> keep_form(params) |> refresh_preview()}
  end

  def handle_event("pick_amount", %{"amount" => amount}, socket) do
    numbers = socket.assigns.form[:numbers].value
    {:noreply, socket |> assign(:form, buy_form(amount, numbers)) |> refresh_preview()}
  end

  # Tap a remembered number and it drops into the list.
  def handle_event("use_recipient", %{"phone" => phone}, socket) do
    numbers = socket.assigns.form[:numbers].value || ""
    joined = if String.trim(numbers) == "", do: phone, else: numbers <> "\n" <> phone

    {:noreply,
     socket
     |> assign(:form, buy_form(socket.assigns.form[:amount].value, joined))
     |> refresh_preview()}
  end

  def handle_event("delete_recipient", %{"id" => id}, socket) do
    _ = Airtime.delete_recipient(socket.assigns.current_scope.user, String.to_integer(id))
    {:noreply, load_saved(socket)}
  end

  def handle_event("buy", %{"airtime" => params}, socket) do
    user = socket.assigns.current_scope.user
    # Keep what was typed and re-read it, so the short-fall block is current even if
    # the customer submits without a change event firing first.
    socket = socket |> keep_form(params) |> refresh_preview()

    with {:ok, amount_cents} <- parse_amount(params["amount"]),
         {:ok, phones} <- parse_phones(params["numbers"]) do
      case Airtime.buy(user, %{amount_cents: amount_cents, phones: phones}) do
        {:ok, orders} ->
          {:noreply, socket |> assign(:error, nil) |> complete_purchase(orders)}

        {:error, :insufficient_funds} ->
          {:noreply, assign(socket, :error, short_copy(socket.assigns.preview))}

        {:error, reason} ->
          {:noreply, assign(socket, :error, error_copy(reason))}
      end
    else
      {:error, message} -> {:noreply, assign(socket, :error, message)}
    end
  end

  # The shortfall, raised exactly.
  def handle_event("pay_shortfall", _params, socket) do
    case socket.assigns.preview[:short_cents] do
      nil -> {:noreply, socket}
      cents -> start_topup(socket, cents)
    end
  end

  # Or deposit more and keep the rest.
  def handle_event("topup", %{"amount" => value}, socket) do
    case Integer.parse(to_string(value)) do
      {shillings, ""} when shillings > 0 -> start_topup(socket, shillings * 100)
      _ -> {:noreply, assign(socket, :error, gettext("Enter a whole number of shillings."))}
    end
  end

  @impl true
  def handle_info({:payment, %Payment{id: payment_id} = payment}, socket) do
    watched = socket.assigns[:payment]

    if watched && watched.id == payment_id do
      {:noreply, handle_payment(socket, payment)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      section={:shop}
      title={gettext("Airtime")}
    >
      <%= if @mode == :topup do %>
        <.waiting
          amount_cents={@payment.amount_cents}
          phone={Phone.format(Payments.prompted_phone(@payment))}
          prompted={not is_nil(@payment.malipo_payment_id)}
        />
      <% else %>
        <.buy_page
          balance={@balance}
          form={@form}
          preview={@preview}
          saved={@saved}
          error={@error}
          purchased={@purchased}
          recent={@recent}
        />
      <% end %>
    </Layouts.app>
    """
  end

  attr :balance, :integer, required: true
  attr :form, :map, required: true
  attr :preview, :map, required: true
  attr :saved, :list, required: true
  attr :error, :string, default: nil
  attr :purchased, :list, required: true
  attr :recent, :list, required: true

  defp buy_page(assigns) do
    ~H"""
    <section class="vn-card" id="airtime-wallet">
      <p class="vn-muted">{gettext("Wallet")}</p>
      <p class="vn-total__value">{kes(@balance)}</p>
    </section>

    <section class="vn-card" id="buy-airtime">
      <h2>{gettext("Buy airtime")}</h2>
      <p class="vn-muted">
        {gettext("Pick an amount, add one or more numbers, and it goes out at once.")}
      </p>

      <.form for={@form} id="airtime-form" phx-submit="buy" phx-change="validate">
        <div class="vn-amount">
          <span class="vn-amount__prefix" aria-hidden="true">{gettext("KSh")}</span>
          <.input
            field={@form[:amount]}
            type="number"
            inputmode="numeric"
            step="1"
            min="1"
            label={gettext("Amount per number")}
            placeholder={gettext("Any amount")}
            class="w-full input vn-amount-field"
          />
        </div>

        <div class="vn-chips" id="airtime-amounts">
          <button
            :for={amount <- amounts()}
            type="button"
            id={"airtime-amount-#{amount}"}
            class={["vn-chip", picked?(@form, amount) && "vn-chip--on"]}
            phx-click="pick_amount"
            phx-value-amount={amount}
          >
            {kes(amount * 100)}
          </button>
        </div>

        <.input
          field={@form[:numbers]}
          type="textarea"
          rows="3"
          label={gettext("Who's getting it?")}
          placeholder={gettext("0712 345 678\n0722 000 111")}
        />

        <section :if={@saved != []} id="airtime-recents">
          <p class="vn-muted">{gettext("Recent numbers — tap to add")}</p>
          <div class="vn-recents">
            <span :for={recipient <- @saved} class="vn-recent" id={"saved-#{recipient.id}"}>
              <button
                type="button"
                class="vn-recent__add"
                phx-click="use_recipient"
                phx-value-phone={recipient.phone}
              >
                {recipient.label || Phone.format(recipient.phone)}
              </button>
              <button
                type="button"
                class="vn-recent__forget"
                phx-click="delete_recipient"
                phx-value-id={recipient.id}
                aria-label={gettext("Forget this number")}
              >
                <.icon name="hero-x-mark" class="size-3" />
              </button>
            </span>
          </div>
        </section>

        <p :if={@preview[:invalid] not in [nil, []]} class="vn-error" id="airtime-invalid">
          {gettext("Not a Kenyan number: %{list}", list: Enum.join(@preview.invalid, ", "))}
        </p>

        <div
          :if={summary?(@preview)}
          class={["vn-summary", @preview.short && "vn-summary--short"]}
          id="airtime-summary"
        >
          <span>{summary_label(@preview)}</span>
          <span class="vn-summary__total">{kes(@preview.total_cents)}</span>
        </div>

        <p :if={@error} class="vn-error" id="airtime-error">{@error}</p>

        <%= if @preview[:short] do %>
          <div class="vn-topup" id="airtime-short">
            <p class="vn-muted">
              {gettext(
                "Your wallet has %{balance}. Pay the %{short} difference with M-Pesa, or deposit more and keep the rest.",
                balance: kes(@balance),
                short: kes(@preview[:short_cents])
              )}
            </p>

            <button type="button" class="vn-button" phx-click="pay_shortfall" id="pay-shortfall">
              {gettext("Pay %{short} with M-Pesa", short: kes(@preview[:short_cents]))}
            </button>

            <div class="vn-topup__options">
              <button
                :for={option <- topup_options(@preview, @balance)}
                type="button"
                class="vn-button vn-button--muted"
                id={"topup-#{option.shillings}"}
                phx-click="topup"
                phx-value-amount={option.shillings}
              >
                {gettext("Deposit %{amount} — %{left} left in your wallet",
                  amount: kes(option.amount_cents),
                  left: kes(option.left_cents)
                )}
              </button>
            </div>
          </div>
        <% else %>
          <button class="vn-button" id="airtime-submit">{gettext("Buy airtime")}</button>
        <% end %>
      </.form>
    </section>

    <section :if={@purchased != []} class="vn-card" id="airtime-purchased">
      <h2>{gettext("On its way")}</h2>
      <p class="vn-muted">{gettext("Saved to your numbers for next time.")}</p>
      <ul class="vn-detail">
        <li :for={order <- @purchased} id={"purchased-#{order.id}"}>
          <span>{Phone.format(order.phone)}</span>
          <span class="vn-muted">{state_label(order.state)}</span>
          <span class="vn-price">{kes(order.amount_cents)}</span>
        </li>
      </ul>
    </section>

    <section :if={@recent != []} class="vn-card" id="airtime-recent">
      <h2>{gettext("Recent airtime")}</h2>
      <ul class="vn-detail">
        <li :for={order <- @recent} id={"airtime-#{order.id}"}>
          <span>{Phone.format(order.phone)}</span>
          <span class="vn-muted">{state_label(order.state)}</span>
          <span class="vn-price">{kes(order.amount_cents)}</span>
        </li>
      </ul>
    </section>
    """
  end

  # -- the shortfall and its top-up --------------------------------------

  # The exact shortfall is the primary button; these are the "and keep the rest"
  # deposits — round numbers *above* it, so the extra genuinely stays behind and no
  # option is a duplicate of paying the difference exactly.
  defp topup_options(preview, balance) do
    short = preview[:short_cents] || 0

    [next_above(short, 10_000), next_above(short, 50_000)]
    |> Enum.uniq()
    |> Enum.map(fn amount ->
      %{
        shillings: div(amount, 100),
        amount_cents: amount,
        left_cents: balance + amount - preview.total_cents
      }
    end)
  end

  defp next_above(value, step), do: (div(max(value, 0), step) + 1) * step

  # M-Pesa moves whole shillings, so a difference that is not one is paid up to the
  # next shilling; the odd cents stay in the wallet.
  defp ceil_shilling(cents), do: div(cents + 99, 100) * 100

  defp start_topup(socket, amount_cents) do
    with {:ok, intent} <- current_intent(socket),
         :ok <- covers?(socket, intent, amount_cents),
         :ok <- check_limits(socket),
         {:ok, payment} <- start_payment(socket, amount_cents) do
      {:noreply,
       socket
       |> assign(:intent, intent)
       |> assign(:error, nil)
       |> assign(:mode, :topup)
       |> watch(payment)}
    else
      {:error, message} -> {:noreply, assign(socket, :error, message)}
    end
  end

  defp current_intent(socket) do
    with {:ok, amount_cents} <- parse_amount(socket.assigns.form[:amount].value),
         {:ok, phones} <- parse_phones(socket.assigns.form[:numbers].value) do
      {:ok,
       %{amount_cents: amount_cents, phones: phones, total_cents: amount_cents * length(phones)}}
    end
  end

  defp covers?(socket, intent, deposit) do
    if socket.assigns.balance + deposit >= intent.total_cents do
      :ok
    else
      {:error,
       gettext("That is still short — add at least %{min}.",
         min: kes(intent.total_cents - socket.assigns.balance)
       )}
    end
  end

  defp check_limits(socket) do
    user = socket.assigns.current_scope.user

    if RateLimit.allow?("payment:user:#{user.id}", :payment_user) do
      :ok
    else
      {:error, gettext("Too many attempts just now — try again shortly.")}
    end
  end

  defp start_payment(socket, amount_cents) do
    user = socket.assigns.current_scope.user

    if Payments.configured?() do
      case Payments.pending_topup(user) do
        # Never raise two prompts for the same amount.
        %Payment{amount_cents: ^amount_cents} = pending -> {:ok, pending}
        _ -> new_payment(user, amount_cents)
      end
    else
      {:error, gettext("Payments are not set up yet.")}
    end
  end

  defp new_payment(user, amount_cents) do
    with {:ok, payment} <- Payments.start_topup_payment(user, amount_cents),
         {:ok, _job} <- CreatePayment.new(%{payment_id: payment.id}) |> Oban.insert() do
      {:ok, payment}
    else
      {:error, _reason} -> {:error, gettext("Could not start the payment.")}
    end
  end

  defp watch(socket, %Payment{} = payment) do
    if socket.assigns[:watching] != payment.id do
      Payments.subscribe(payment.id)
    end

    assign(socket, payment: payment, watching: payment.id)
  end

  defp handle_payment(socket, %Payment{status: :settled}) do
    complete(socket)
  end

  defp handle_payment(socket, %Payment{status: :failed} = payment) do
    socket
    |> assign(:mode, :idle)
    |> assign(:payment, nil)
    |> assign(:error, Payments.failure_copy(payment.failure_kind, payment.failure_message))
  end

  defp handle_payment(socket, _payment), do: socket

  # The wallet is funded now, so the airtime the customer asked for goes out.
  defp complete(socket) do
    socket =
      socket
      |> assign(:mode, :idle)
      |> assign(:payment, nil)
      |> load_wallet()
      |> load_saved()
      |> load_recent()

    case socket.assigns.intent do
      %{amount_cents: amount_cents, phones: phones} ->
        user = socket.assigns.current_scope.user

        case Airtime.buy(user, %{amount_cents: amount_cents, phones: phones}) do
          {:ok, orders} ->
            socket |> assign(:intent, nil) |> complete_purchase(orders)

          {:error, reason} ->
            socket |> assign(:intent, nil) |> assign(:error, error_copy(reason))
        end

      _none ->
        socket
    end
  end

  defp complete_purchase(socket, orders) do
    socket
    |> assign(:error, nil)
    |> assign(:purchased, orders)
    |> assign(:form, buy_form("", ""))
    |> load_wallet()
    |> load_saved()
    |> load_recent()
    |> refresh_preview()
  end

  # -- rendering helpers -------------------------------------------------

  defp load_wallet(socket),
    do: assign(socket, :balance, Wallet.balance(socket.assigns.current_scope.user))

  defp load_saved(socket) do
    assign(socket, :saved, Airtime.list_recipients(socket.assigns.current_scope.user))
  end

  defp load_recent(socket) do
    assign(socket, :recent, Airtime.list_for_user(socket.assigns.current_scope.user, limit: 10))
  end

  defp buy_form(amount, numbers) do
    to_form(%{"amount" => amount || "", "numbers" => numbers || ""}, as: "airtime")
  end

  # Where the buy is submitted with values the change event never saw, the form must
  # still catch up before the preview is read from it.
  defp keep_form(socket, params), do: assign(socket, :form, to_form(params, as: "airtime"))

  # The running total, so an irreversible buy is never a surprise. Lenient: it reads
  # whatever is typed and says what it makes of it, rather than waiting for submit.
  defp refresh_preview(socket) do
    amount = parse_shillings(socket.assigns.form[:amount].value)
    numbers = split_numbers(socket.assigns.form[:numbers].value)
    {valid, invalid} = Enum.split_with(numbers, &Phone.valid?/1)
    count = valid |> Enum.map(&Phone.normalize_or_self/1) |> Enum.uniq() |> length()
    total = if amount, do: amount * count, else: nil

    assign(socket, :preview, %{
      amount_cents: amount,
      count: count,
      invalid: invalid,
      total_cents: total,
      short: is_integer(total) and total > socket.assigns.balance,
      short_cents: short_cents(total, socket.assigns.balance)
    })
  end

  defp short_cents(total, balance) when is_integer(total) and total > balance,
    do: ceil_shilling(total - balance)

  defp short_cents(_total, _balance), do: nil

  # When the block already says what is short, a banner above it would only repeat
  # it, so the error stays quiet.
  defp short_copy(preview) do
    if preview[:short], do: nil, else: gettext("Your wallet does not cover this.")
  end

  defp summary?(preview), do: preview[:count] > 0 and is_integer(preview[:amount_cents])

  defp summary_label(preview) do
    if preview.short do
      gettext("Your wallet is short")
    else
      gettext("%{each} each to %{count}",
        each: kes(preview.amount_cents),
        count: recipient_count(preview.count)
      )
    end
  end

  defp recipient_count(1), do: gettext("1 number")
  defp recipient_count(count), do: gettext("%{count} numbers", count: count)

  defp amounts, do: [50, 100, 200, 500]

  defp picked?(form, amount), do: to_string(form[:amount].value) == to_string(amount)

  defp parse_shillings(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {shillings, ""} when shillings > 0 -> shillings * 100
      _ -> nil
    end
  end

  defp parse_shillings(_value), do: nil

  defp parse_amount(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {shillings, ""} when shillings > 0 -> {:ok, shillings * 100}
      _ -> {:error, gettext("Enter a whole number of shillings.")}
    end
  end

  defp parse_amount(_value), do: {:error, gettext("Enter an amount.")}

  # Split on lines and separators only — never on spaces, because a Kenyan number is
  # often written "0722 000 111" and splitting on spaces tears it in three.
  defp split_numbers(text) when is_binary(text), do: String.split(text, ~r/[\n,;]+/, trim: true)
  defp split_numbers(_text), do: []

  defp parse_phones(text) when is_binary(text) do
    text
    |> split_numbers()
    |> Enum.reduce_while({:ok, []}, fn number, {:ok, acc} ->
      case Phone.normalize(number) do
        {:ok, phone} -> {:cont, {:ok, [phone | acc]}}
        {:error, :invalid_phone} -> {:halt, {:error, invalid_number_message(number)}}
      end
    end)
    |> case do
      {:ok, []} -> {:error, gettext("Add at least one number.")}
      {:ok, list} -> {:ok, Enum.uniq(list)}
      error -> error
    end
  end

  defp parse_phones(_text), do: {:error, gettext("Add at least one number.")}

  defp invalid_number_message(number) do
    gettext("%{number} is not a Kenyan mobile number.", number: number)
  end

  defp error_copy(:amount_too_small),
    do: gettext("The smallest top-up is %{min}.", min: kes(Airtime.min_amount_cents()))

  defp error_copy(:amount_too_large),
    do: gettext("The largest top-up is %{max}.", max: kes(Airtime.max_amount_cents()))

  defp error_copy(:not_whole_shillings), do: gettext("Use whole shillings.")

  defp error_copy(:too_many_recipients),
    do: gettext("Up to %{max} numbers at a time.", max: Airtime.max_recipients())

  defp error_copy(:no_recipients), do: gettext("Add at least one number.")

  defp error_copy({:invalid_phone, number}), do: invalid_number_message(number)
  defp error_copy(_reason), do: gettext("Could not start that purchase.")

  defp state_label(state) do
    case state do
      :delivered -> gettext("Delivered")
      :refunded -> gettext("Refunded")
      :failed -> gettext("Failed")
      :needs_review -> gettext("Checking")
      _ -> gettext("Sending")
    end
  end

  defp kes(cents), do: Pricing.format_kes_cents(cents)
end
