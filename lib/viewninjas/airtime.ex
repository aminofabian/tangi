defmodule ViewNinjas.Airtime do
  @moduledoc """
  Buying airtime (scope: `docs/instalipa-airtime.md`).

  Airtime is paid **from the wallet**, so its money path is the one the wallet
  already trusts: a debit and the `paid` state in one transaction, and a credit back
  when a send definitively fails. A **bulk buy** is several orders sharing one
  `batch_id`, each its own rail transaction, each refundable on its own.

  The rail's word arrives later — `submitted` is not delivered — so the confirming
  job (not this module) moves an order to `delivered` or `failed`. This module only
  owns the state machine and the ledger.
  """

  import Ecto.Query

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Airtime.{AirtimeEvent, AirtimeOrder, SavedRecipient}
  alias ViewNinjas.Repo
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.SendAirtime

  # Provisional bounds until Instalipa confirms theirs (scope §3.6, §14). Whole
  # shillings per recipient, and a ceiling that keeps one fat finger from being a
  # very expensive one.
  @min_amount_cents 1_000
  @max_amount_cents 100_000
  @max_recipients 20

  @doc "The smallest top-up per recipient, in KES cents."
  @spec min_amount_cents() :: pos_integer()
  def min_amount_cents, do: @min_amount_cents

  @doc "The largest top-up per recipient, in KES cents."
  @spec max_amount_cents() :: pos_integer()
  def max_amount_cents, do: @max_amount_cents

  @doc "The most recipients one bulk buy may carry."
  @spec max_recipients() :: pos_integer()
  def max_recipients, do: @max_recipients

  # -- buying ------------------------------------------------------------

  @doc """
  Buys airtime for one or more numbers, paid from the wallet.

  Every recipient becomes its own order, all sharing one `batch_id`, and the debit
  is a single transaction: either the whole batch is paid and queued, or nothing is.
  """
  @spec buy(User.t(), map()) :: {:ok, [AirtimeOrder.t()]} | {:error, term()}
  def buy(%User{} = user, attrs) do
    with {:ok, amount_cents} <- validate_amount(attrs[:amount_cents]),
         {:ok, phones} <- validate_phones(attrs[:phones]) do
      run(user, phones, amount_cents)
    end
  end

  defp run(user, phones, amount_cents) do
    total = amount_cents * length(phones)

    case Repo.transact(fn -> purchase(user, phones, amount_cents, total) end) do
      {:ok, orders} = ok ->
        # Queued only once the debit has committed, so a job never runs against
        # uncommitted state.
        _ = Enum.each(orders, &SendAirtime.enqueue(&1.id))
        _ = touch_recipients(user, phones)
        ok

      error ->
        error
    end
  end

  defp purchase(user, phones, amount_cents, total) do
    # Serialise one customer's spending so two taps cannot both pass the check.
    _ = Repo.one!(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE")

    if Wallet.balance(user.id) >= total do
      insert_batch(user, phones, amount_cents, token())
    else
      {:error, :insufficient_funds}
    end
  end

  # Every line in one transaction: the whole batch is paid, or none of it is.
  defp insert_batch(user, phones, amount_cents, batch) do
    result =
      Enum.reduce_while(phones, {:ok, []}, fn phone, acc ->
        step(insert_paid(user, phone, amount_cents, batch), acc)
      end)

    case result do
      {:ok, orders} -> {:ok, Enum.reverse(orders)}
      {:error, _reason} = error -> error
    end
  end

  defp step({:ok, order}, {:ok, acc}), do: {:cont, {:ok, [order | acc]}}
  defp step({:error, _reason} = error, _acc), do: {:halt, error}

  defp insert_paid(user, phone, amount_cents, batch) do
    reference = "airtime-" <> token()

    with {:ok, order} <-
           %AirtimeOrder{}
           |> AirtimeOrder.changeset(%{
             user_id: user.id,
             batch_id: batch,
             phone: phone,
             amount_cents: amount_cents,
             state: :paid,
             reference: reference,
             idempotency_key: reference
           })
           |> Repo.insert(),
         {:ok, _entry} <-
           Wallet.record(%{
             user_id: user.id,
             amount_cents: -amount_cents,
             reason: :airtime,
             airtime_order_id: order.id
           }),
         {:ok, _event} <- record_event(order, nil, :paid, "paid from the wallet") do
      {:ok, order}
    end
  end

  # -- reading -----------------------------------------------------------

  def get_order(id), do: Repo.get(AirtimeOrder, id)

  @doc "One airtime order, but only when it belongs to this customer."
  def get_order_for_user(%User{id: user_id}, id) do
    AirtimeOrder
    |> where([o], o.id == ^id and o.user_id == ^user_id)
    |> Repo.one()
  end

  @doc "The customer's airtime orders, newest first."
  def list_for_user(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    AirtimeOrder
    |> where([o], o.user_id == ^user_id)
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "The orders still worth asking the rail about — the sweep's query."
  def list_pollable(opts \\ []) do
    limit = Keyword.get(opts, :limit, 500)

    AirtimeOrder
    |> where([o], o.state in ^AirtimeOrder.pollable_states() and not is_nil(o.instalipa_id))
    |> order_by([o], asc: o.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "The order's timeline, oldest first."
  def timeline(%AirtimeOrder{id: id}) do
    AirtimeEvent
    |> where([e], e.airtime_order_id == ^id)
    |> order_by([e], asc: e.inserted_at, asc: e.id)
    |> preload(:actor)
    |> Repo.all()
  end

  # -- the state machine -------------------------------------------------

  @doc "Marks a paid order as sent, before the rail is called. Never sent twice."
  @spec mark_sending(AirtimeOrder.t()) :: {:ok, AirtimeOrder.t()} | {:error, term()}
  def mark_sending(%AirtimeOrder{state: :paid} = order),
    do: transition(order, :sending, "sent to the rail")

  def mark_sending(%AirtimeOrder{}), do: {:error, :not_sendable}

  @doc "Records the rail's acceptance: the transaction id and what it reported."
  @spec mark_submitted(AirtimeOrder.t(), map()) :: {:ok, AirtimeOrder.t()} | {:error, term()}
  def mark_submitted(%AirtimeOrder{state: :sending} = order, tx),
    do: transition(order, :submitted, "the rail accepted it", rail_attrs(tx))

  @doc "The rail delivered it (a confirming status said Success)."
  @spec mark_delivered(AirtimeOrder.t(), map()) :: {:ok, AirtimeOrder.t()} | {:error, term()}
  def mark_delivered(%AirtimeOrder{state: :submitted} = order, tx),
    do: transition(order, :delivered, "the rail delivered it", rail_attrs(tx))

  @doc "The rail reported a failure. The caller decides whether to refund."
  @spec mark_failed(AirtimeOrder.t(), String.t() | nil, String.t() | nil) ::
          {:ok, AirtimeOrder.t()} | {:error, term()}
  def mark_failed(%AirtimeOrder{state: state} = order, kind, message)
      when state in [:sending, :submitted] do
    transition(order, :failed, message, %{failure_kind: kind, failure_message: message})
  end

  def mark_failed(%AirtimeOrder{} = order, kind, message),
    do: transition(order, :failed, message, %{failure_kind: kind, failure_message: message})

  @doc "Parks an order for a person: an ambiguous send, never a second one."
  @spec mark_needs_review(AirtimeOrder.t(), String.t()) ::
          {:ok, AirtimeOrder.t()} | {:error, term()}
  def mark_needs_review(%AirtimeOrder{state: state} = order, reason)
      when state in [:paid, :sending, :submitted] do
    transition(order, :needs_review, reason)
  end

  @doc "Credits the wallet back and closes the order. Refuses anything not refundable."
  @spec refund(AirtimeOrder.t()) :: {:ok, AirtimeOrder.t()} | {:error, term()}
  def refund(%AirtimeOrder{state: state} = order) when state in [:failed, :needs_review] do
    Repo.transact(fn ->
      with {:ok, refunded} <-
             order |> AirtimeOrder.changeset(%{state: :refunded}) |> Repo.update(),
           {:ok, _entry} <-
             Wallet.record(%{
               user_id: order.user_id,
               amount_cents: order.amount_cents,
               reason: :airtime_refund,
               airtime_order_id: order.id
             }),
           {:ok, _event} <-
             record_event(refunded, state, :refunded, "refunded to the wallet") do
        {:ok, refunded}
      end
    end)
  end

  def refund(%AirtimeOrder{}), do: {:error, :not_refundable}

  defp transition(order, to_state, reason, attrs \\ %{}) do
    Repo.transact(fn ->
      with {:ok, moved} <-
             order
             |> AirtimeOrder.changeset(Map.merge(attrs, %{state: to_state}))
             |> Repo.update(),
           {:ok, _event} <- record_event(moved, order.state, to_state, reason) do
        {:ok, moved}
      end
    end)
  end

  defp record_event(order, from_state, to_state, reason, actor \\ nil) do
    %AirtimeEvent{}
    |> AirtimeEvent.changeset(%{
      airtime_order_id: order.id,
      from_state: state_string(from_state),
      to_state: state_string(to_state),
      reason: reason,
      actor_id: actor && actor.id
    })
    |> Repo.insert()
  end

  defp state_string(nil), do: nil
  defp state_string(state), do: to_string(state)

  # The rail's fields, as data. A nil the rail did not report stays nil — nothing
  # is invented (scope §5).
  defp rail_attrs(tx) do
    %{
      instalipa_status: tx[:status] && to_string(tx[:status]),
      discount_cents: cents(tx[:discount]),
      float_cents: cents(tx[:balance]),
      receipt: tx[:receipt]
    }
    |> maybe_put_instalipa_id(tx[:id])
  end

  defp maybe_put_instalipa_id(attrs, nil), do: attrs
  defp maybe_put_instalipa_id(attrs, id), do: Map.put(attrs, :instalipa_id, id)

  defp cents(nil), do: nil

  defp cents(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, ""} ->
        decimal |> Decimal.mult(100) |> Decimal.round(0, :half_up) |> Decimal.to_integer()

      _ ->
        nil
    end
  end

  defp cents(value) when is_integer(value), do: value

  # -- saved recipients --------------------------------------------------

  @doc "The customer's saved numbers, most recently used first."
  @spec list_recipients(User.t()) :: [SavedRecipient.t()]
  def list_recipients(%User{id: user_id}) do
    SavedRecipient
    |> where([r], r.user_id == ^user_id)
    |> order_by([r], desc_nulls_last: r.last_used_at, desc: r.inserted_at)
    |> Repo.all()
  end

  @doc """
  Saves a number for future buys. Idempotent: saving the same number again only
  updates its label, never duplicates it.
  """
  @spec save_recipient(User.t(), String.t(), String.t() | nil) ::
          {:ok, SavedRecipient.t()} | {:error, term()}
  def save_recipient(%User{} = user, raw_phone, label) do
    case Phone.normalize(raw_phone) do
      {:ok, phone} -> insert_recipient(user, phone, label)
      {:error, :invalid_phone} -> {:error, :invalid_phone}
    end
  end

  defp insert_recipient(user, phone, label) do
    %SavedRecipient{}
    |> SavedRecipient.changeset(%{
      user_id: user.id,
      phone: phone,
      label: label && String.trim(label)
    })
    |> Repo.insert(
      on_conflict: {:replace, [:label, :updated_at]},
      conflict_target: [:user_id, :phone]
    )
  end

  @doc "Removes a saved number, but only one this customer owns."
  @spec delete_recipient(User.t(), integer()) :: :ok
  def delete_recipient(%User{id: user_id}, id) do
    SavedRecipient
    |> where([r], r.id == ^id and r.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  @doc "Stamps the saved numbers in this buy as just used, so the picker floats them."
  @spec touch_recipients(User.t(), [String.t()]) :: :ok
  def touch_recipients(%User{id: user_id}, phones) when is_list(phones) do
    now = DateTime.utc_now(:second)

    SavedRecipient
    |> where([r], r.user_id == ^user_id and r.phone in ^phones)
    |> Repo.update_all(set: [last_used_at: now, updated_at: now])

    :ok
  end

  # -- validation --------------------------------------------------------

  defp validate_amount(cents) when is_integer(cents) do
    cond do
      rem(cents, 100) != 0 -> {:error, :not_whole_shillings}
      cents < @min_amount_cents -> {:error, :amount_too_small}
      cents > @max_amount_cents -> {:error, :amount_too_large}
      true -> {:ok, cents}
    end
  end

  defp validate_amount(_cents), do: {:error, :amount_too_small}

  defp validate_phones(phones) when is_list(phones) do
    phones
    |> Enum.reduce_while({:ok, []}, fn raw, {:ok, acc} ->
      case Phone.normalize(raw) do
        {:ok, phone} -> {:cont, {:ok, [phone | acc]}}
        {:error, :invalid_phone} -> {:halt, {:error, {:invalid_phone, raw}}}
      end
    end)
    |> case do
      {:ok, list} -> check_recipients(Enum.uniq(list))
      error -> error
    end
  end

  defp validate_phones(_phones), do: {:error, :no_recipients}

  defp check_recipients([]), do: {:error, :no_recipients}

  defp check_recipients(list) when length(list) > @max_recipients,
    do: {:error, :too_many_recipients}

  defp check_recipients(list), do: {:ok, list}

  defp token, do: Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
end
