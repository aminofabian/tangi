defmodule ViewNinjasWeb.AirtimeLive do
  @moduledoc """
  Buying airtime (scope: `docs/instalipa-airtime.md` §8).

  One number or a bulk list, paid from the wallet. Saved numbers are reusable — the
  picker drops one into the list — and this is also where they are kept.
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
     |> assign(:recipient_form, to_form(%{"phone" => "", "label" => ""}, as: "recipient"))
     |> assign(:error, nil)
     |> assign(:purchased, [])
     |> load_wallet()
     |> load_saved()
     |> load_recent()}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    Analytics.record_page_view(socket, uri)
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"airtime" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "airtime"))}
  end

  def handle_event("pick_amount", %{"amount" => amount}, socket) do
    numbers = socket.assigns.form[:numbers].value
    {:noreply, assign(socket, form: buy_form(amount, numbers))}
  end

  def handle_event("use_recipient", %{"phone" => phone}, socket) do
    numbers = socket.assigns.form[:numbers].value || ""
    joined = if String.trim(numbers) == "", do: phone, else: numbers <> "\n" <> phone

    {:noreply, assign(socket, form: buy_form(socket.assigns.form[:amount].value, joined))}
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
           |> load_recent()}

        {:error, :insufficient_funds} ->
          {:noreply,
           assign(
             socket,
             :error,
             gettext("Your wallet does not cover this. Add money, then try again.")
           )}

        {:error, reason} ->
          {:noreply, assign(socket, :error, error_copy(reason))}
      end
    else
      {:error, message} -> {:noreply, assign(socket, :error, message)}
    end
  end

  def handle_event("save_recipient", %{"recipient" => params}, socket) do
    user = socket.assigns.current_scope.user

    case Airtime.save_recipient(user, params["phone"], params["label"]) do
      {:ok, _recipient} ->
        {:noreply,
         socket
         |> assign(:recipient_form, to_form(%{"phone" => "", "label" => ""}, as: "recipient"))
         |> load_saved()}

      {:error, :invalid_phone} ->
        {:noreply, put_flash(socket, :error, gettext("That is not a Kenyan mobile number."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save that number."))}
    end
  end

  def handle_event("delete_recipient", %{"id" => id}, socket) do
    _ = Airtime.delete_recipient(socket.assigns.current_scope.user, String.to_integer(id))
    {:noreply, load_saved(socket)}
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
      <section class="vn-card">
        <p class="vn-muted">{gettext("Wallet")}</p>
        <p class="vn-total__value">{kes(@balance)}</p>
      </section>

      <section class="vn-card" id="buy-airtime">
        <h2>{gettext("Buy airtime")}</h2>
        <p class="vn-muted">
          {gettext("Type a number (or several, one per line) and an amount. Paid from your wallet.")}
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
            label={gettext("Numbers")}
            placeholder={gettext("0712 345 678\n0722 000 111")}
          />

          <div :if={@saved != []} class="vn-chips" id="saved-picker">
            <button
              :for={recipient <- @saved}
              type="button"
              id={"use-#{recipient.id}"}
              class="vn-chip"
              phx-click="use_recipient"
              phx-value-phone={recipient.phone}
            >
              {recipient.label || Phone.format(recipient.phone)}
            </button>
          </div>

          <p :if={@error} class="vn-error" id="airtime-error">{@error}</p>

          <button class="vn-button" id="airtime-submit">{gettext("Buy airtime")}</button>
        </.form>
      </section>

      <section :if={@purchased != []} class="vn-card" id="airtime-purchased">
        <h2>{gettext("On its way")}</h2>
        <ul class="vn-detail">
          <li :for={order <- @purchased} id={"purchased-#{order.id}"}>
            <span>{Phone.format(order.phone)}</span>
            <span class="vn-muted">{state_label(order.state)}</span>
            <span class="vn-price">{kes(order.amount_cents)}</span>
          </li>
        </ul>
      </section>

      <section class="vn-card" id="saved-recipients">
        <h2>{gettext("Saved numbers")}</h2>
        <p class="vn-muted">{gettext("Keep the numbers you top up often.")}</p>

        <.form for={@recipient_form} id="recipient-form" phx-submit="save_recipient">
          <.input
            field={@recipient_form[:phone]}
            type="tel"
            inputmode="tel"
            label={gettext("Number")}
            placeholder={gettext("0712 345 678")}
          />
          <.input
            field={@recipient_form[:label]}
            type="text"
            label={gettext("Name (optional)")}
            placeholder={gettext("Mum")}
          />
          <button class="vn-button vn-button--muted" id="save-recipient">
            {gettext("Save number")}
          </button>
        </.form>

        <ul class="vn-detail" id="saved-list">
          <li :for={recipient <- @saved} id={"saved-#{recipient.id}"}>
            <span>{recipient.label || Phone.format(recipient.phone)}</span>
            <span class="vn-muted">{Phone.format(recipient.phone)}</span>
            <button
              type="button"
              class="vn-button vn-button--muted"
              phx-click="delete_recipient"
              phx-value-id={recipient.id}
              aria-label={gettext("Remove")}
            >
              <.icon name="hero-x-mark" class="size-4" />
            </button>
          </li>
        </ul>
        <p :if={@saved == []} class="vn-muted">{gettext("No saved numbers yet.")}</p>
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

  defp amounts, do: [50, 100, 200, 500]

  defp picked?(form, amount), do: to_string(form[:amount].value) == to_string(amount)

  defp parse_amount(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {shillings, ""} when shillings > 0 -> {:ok, shillings * 100}
      _ -> {:error, gettext("Enter a whole number of shillings.")}
    end
  end

  defp parse_amount(_value), do: {:error, gettext("Enter an amount.")}

  defp parse_phones(text) when is_binary(text) do
    # Split on lines and separators only — never on spaces, because a Kenyan
    # number is often written "0722 000 111" and splitting on spaces tears it in
    # three. `Phone.normalize/1` strips the spaces inside each entry.
    text
    |> String.split(~r/[\n,;]+/, trim: true)
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
