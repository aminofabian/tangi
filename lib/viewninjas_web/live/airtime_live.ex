defmodule ViewNinjasWeb.AirtimeLive do
  @moduledoc """
  Buying airtime (scope: `docs/instalipa-airtime.md` §8).

  One number or a bulk list, paid from the wallet, with a running total so nothing
  irreversible is a surprise. The numbers you buy for are **remembered as you buy** —
  there is no separate "save" step — and offered back for the next time.
  """

  use ViewNinjasWeb, :live_view

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Airtime
  alias ViewNinjas.Pricing
  alias ViewNinjas.Wallet
  alias ViewNinjasWeb.Analytics

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
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
    {:noreply, socket |> assign(:form, to_form(params, as: "airtime")) |> refresh_preview()}
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

    with {:ok, amount_cents} <- parse_amount(params["amount"]),
         {:ok, phones} <- parse_phones(params["numbers"]) do
      case Airtime.buy(user, %{amount_cents: amount_cents, phones: phones}) do
        {:ok, orders} ->
          {:noreply,
           socket
           |> assign(:error, nil)
           |> assign(:purchased, orders)
           |> assign(:form, buy_form("", ""))
           |> load_wallet()
           |> load_saved()
           |> load_recent()
           |> refresh_preview()}

        {:error, :insufficient_funds} ->
          {:noreply,
           assign(socket, :error, gettext("Your wallet does not cover this. Add money first."))}

        {:error, reason} ->
          {:noreply, assign(socket, :error, error_copy(reason))}
      end
    else
      {:error, message} -> {:noreply, assign(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      section={:shop}
      title={gettext("Airtime")}
    >
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

          <p :if={@preview[:short]} class="vn-muted">
            {gettext("Add %{short} to your wallet to cover it.",
              short: kes(@preview.total_cents - @balance)
            )}
          </p>

          <p :if={@error} class="vn-error" id="airtime-error">{@error}</p>

          <button class="vn-button" id="airtime-submit">{gettext("Buy airtime")}</button>
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
    </Layouts.app>
    """
  end

  # -- internals ---------------------------------------------------------

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
      short: is_integer(total) and total > socket.assigns.balance
    })
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
