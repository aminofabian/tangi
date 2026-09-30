defmodule ViewNinjasWeb.WalletLive do
  @moduledoc """
  The wallet (scope.md §8, §11): the balance, the ledger, and a top-up.

  The balance is the **sum** of the ledger, never a column. A top-up starts a
  payment and shows the same M-Pesa sheet as checkout; the ledger is credited only
  when a confirming GET says the payment settled.
  """
  use ViewNinjasWeb, :live_view

  import ViewNinjasWeb.PaymentComponents

  alias ViewNinjas.Payments
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Pricing
  alias ViewNinjas.RateLimit
  alias ViewNinjas.Wallet
  alias ViewNinjas.Wallet.LedgerEntry
  alias ViewNinjas.Workers.CreatePayment
  alias ViewNinjasWeb.Analytics

  # One shilling is the smallest prompt M-Pesa will raise. The ceiling is a
  # guard against a stray zero, not a menu of allowed amounts.
  @min_topup_cents 100
  @max_topup_cents 100_000_000

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:analytics, Analytics.capture(socket, session))
     |> assign(:mode, :idle)
     |> assign(:payment, nil)
     |> assign(:failure, nil)
     |> assign(:receipt, nil)
     |> assign(:receipt_amount, nil)
     |> assign(:form, to_form(%{"amount" => ""}, as: "topup"))
     |> load_wallet()}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    Analytics.record_page_view(socket, uri)
    {:noreply, resume_or_idle(socket)}
  end

  @impl true
  def handle_event("topup", %{"topup" => params}, socket) do
    if RateLimit.allow?("payment:user:#{socket.assigns.current_scope.user.id}", :payment_user) do
      start_topup(socket, params["amount"])
    else
      {:noreply,
       put_flash(socket, :error, gettext("Too many attempts just now — try again shortly."))}
    end
  end

  def handle_event("retry", _params, socket) do
    start_topup(socket, to_string(div(socket.assigns.payment.amount_cents, 100)))
  end

  def handle_event("pick_amount", %{"amount" => amount}, socket) do
    {:noreply, assign(socket, form: to_form(%{"amount" => amount}, as: "topup"))}
  end

  def handle_event("close_topup", _params, socket) do
    {:noreply,
     socket
     |> assign(:mode, :idle)
     |> assign(:payment, nil)
     |> assign(:failure, nil)
     |> assign(:form, to_form(%{"amount" => ""}, as: "topup"))
     |> load_wallet()}
  end

  defp start_topup(socket, raw_amount) do
    if Payments.configured?() do
      with {:ok, amount_cents} <- validate_amount(raw_amount),
           {:ok, payment} <- start_attempt(socket, amount_cents) do
        {:noreply, watch(socket, payment)}
      else
        {:error, message} when is_binary(message) ->
          {:noreply, put_flash(socket, :error, message)}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, gettext("Could not start the top-up."))}
      end
    else
      {:noreply,
       put_flash(
         socket,
         :error,
         gettext(
           "Payments need the secret key that starts with sk_live_. The client id cannot take a payment."
         )
       )}
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
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      section={:account}
      title={gettext("Wallet")}
    >
      <%= cond do %>
        <% @mode == :waiting -> %>
          <.waiting
            amount_cents={@payment.amount_cents}
            phone={ViewNinjas.Accounts.Phone.format(@current_scope.user.phone)}
            prompted={not is_nil(@payment.malipo_payment_id)}
          />
        <% @mode == :succeeded -> %>
          <.succeeded
            title={gettext("It's in")}
            amount_cents={@receipt_amount}
            receipt={@receipt}
            celebrate
            balance={kes(@balance)}
            closer="close_topup"
          />
        <% @mode == :failed -> %>
          <.failed
            amount_cents={@payment.amount_cents}
            failure={@failure}
            closer="close_topup"
          />
        <% true -> %>
          <.wallet_body balance={@balance} entries={@entries} form={@form} />
      <% end %>
    </Layouts.app>
    """
  end

  attr :balance, :integer, required: true
  attr :entries, :list, required: true
  attr :form, :map, required: true

  defp wallet_body(assigns) do
    ~H"""
    <section class="vn-purse" id="wallet-balance">
      <span class="vn-purse__coin vn-purse__coin--a" aria-hidden="true"></span>
      <span class="vn-purse__coin vn-purse__coin--b" aria-hidden="true"></span>
      <span class="vn-purse__coin vn-purse__coin--c" aria-hidden="true"></span>
      <p class="vn-purse__label">{gettext("Balance")}</p>
      <p class="vn-purse__amount">{kes(@balance)}</p>
      <p class="vn-purse__note">{gettext("Spendable now — the sum of your ledger.")}</p>
    </section>

    <section class="vn-card" id="topup">
      <h2>{gettext("Add money")}</h2>
      <p class="vn-muted">{gettext("Type any amount in shillings, or start from one of these.")}</p>
      <.form for={@form} id="topup-form" phx-submit="topup">
        <.input
          field={@form[:amount]}
          type="number"
          inputmode="numeric"
          step="1"
          min="1"
          label={gettext("Amount in shillings")}
          placeholder={gettext("Any amount")}
        />
        <div class="vn-chips" id="topup-amounts">
          <button
            :for={amount <- topup_amounts()}
            type="button"
            id={"topup-amount-#{amount}"}
            class={["vn-chip", picked?(@form, amount) && "vn-chip--on"]}
            phx-click="pick_amount"
            phx-value-amount={amount}
          >
            {kes(amount * 100)}
          </button>
        </div>
        <button class="vn-button" id="topup-submit">{gettext("Top up with M-Pesa")}</button>
      </.form>
    </section>

    <section class="vn-card">
      <h2>{gettext("Ledger")}</h2>
      <ul class="vn-ledger">
        <li :for={entry <- @entries} id={"entry-#{entry.id}"} class="vn-ledger__row">
          <span>{LedgerEntry.label(entry.reason)}</span>
          <span class="vn-muted">{format_at(entry.inserted_at)}</span>
          <span class={[
            "vn-ledger__amount",
            entry.amount_cents < 0 && "vn-ledger__amount--out"
          ]}>
            {signed(entry.amount_cents)}
          </span>
        </li>
      </ul>
      <p :if={@entries == []} class="vn-muted">{gettext("No movements yet.")}</p>
    </section>
    """
  end

  # -- internals ---------------------------------------------------------

  defp load_wallet(socket) do
    user = socket.assigns.current_scope.user

    assign(socket,
      balance: Wallet.balance(user),
      entries: Wallet.list_entries(user, 30)
    )
  end

  defp resume_or_idle(socket) do
    case Payments.pending_topup(socket.assigns.current_scope.user) do
      nil -> assign(socket, mode: :idle, payment: nil)
      payment -> watch(socket, payment)
    end
  end

  defp watch(socket, nil), do: assign(socket, mode: :idle)

  defp watch(socket, %Payment{status: :settled} = payment) do
    socket
    |> assign(:payment, payment)
    |> assign(:receipt, payment.receipt)
    |> assign(:receipt_amount, payment.amount_cents)
    |> assign(:mode, :succeeded)
    |> load_wallet()
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

  defp start_attempt(socket, amount_cents) do
    with {:ok, payment} <-
           Payments.start_topup_payment(socket.assigns.current_scope.user, amount_cents),
         {:ok, _job} <- CreatePayment.new(%{payment_id: payment.id}) |> Oban.insert() do
      {:ok, payment}
    else
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset_message(changeset)}
      {:error, _reason} -> {:error, :enqueue_failed}
    end
  end

  defp validate_amount(value) when is_binary(value) do
    case Integer.parse(value) do
      {shillings, ""} when shillings > 0 -> check_bounds(shillings * 100)
      _ -> {:error, gettext("Enter a whole number of shillings.")}
    end
  end

  defp validate_amount(_value), do: {:error, gettext("Enter an amount.")}

  defp check_bounds(cents) when cents < @min_topup_cents,
    do: {:error, gettext("The smallest top-up is %{min}.", min: kes(@min_topup_cents))}

  defp check_bounds(cents) when cents > @max_topup_cents,
    do: {:error, gettext("That is more than we can top up at once.")}

  defp check_bounds(cents), do: {:ok, cents}

  defp kes(cents), do: Pricing.format_kes_cents(cents)

  defp topup_amounts, do: [50, 100, 200, 500, 1_000]

  defp picked?(form, amount), do: to_string(form[:amount].value) == to_string(amount)

  defp signed(cents) when cents < 0, do: "−" <> Pricing.format_kes_cents(-cents)
  defp signed(cents), do: "+" <> Pricing.format_kes_cents(cents)

  defp format_at(nil), do: ""
  defp format_at(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
