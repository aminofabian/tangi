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

  ## The money-out, money-back promise

  A customer is **never** left holding a loss, and the two halves of that promise are
  enforced in different places:

    * a **definite** failure (`fail_and_refund/4`) fails and credits in **one**
      transaction, so a crash between the two can never strand a debit;
    * an **ambiguous** send (`needs_review`) keeps the money and raises an alert,
      because we genuinely do not know whether the airtime went out — the back office
      reconciles it, and `list_needs_review/1` is that queue.

  Float is read from the rail's own `balance` on the newest row (`float/0`), never
  invented, and a floor below it flips selling off (`sellable?/0`) so we stop taking
  money for airtime the rail cannot deliver.
  """

  import Ecto.Query

  alias ViewNinjas.Accounts.Phone
  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Airtime.{AirtimeEvent, AirtimeOrder, SavedRecipient}
  alias ViewNinjas.Alerts
  alias ViewNinjas.Repo
  alias ViewNinjas.Settings
  alias ViewNinjas.Wallet
  alias ViewNinjas.Wallet.LedgerEntry
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

  A paused rail — or a float that has fallen under the floor — refuses **before** any
  money moves, so a customer is never charged for airtime we already know we cannot
  deliver (scope §10). The failure that still gets through, a rail rejection after
  the fact, is made whole by `fail_and_refund/4`.
  """
  @spec buy(User.t(), map()) :: {:ok, [AirtimeOrder.t()]} | {:error, term()}
  def buy(%User{} = user, attrs) do
    case pause_reason() do
      nil -> validated_buy(user, attrs)
      reason -> {:error, reason}
    end
  end

  defp validated_buy(user, attrs) do
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
        _ = remember_recipients(user, phones)
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

  # -- the back office ----------------------------------------------------

  @doc """
  The float we are acting on, in cents, or nil when we have none at all.

  A **manual** figure the super-admin typed from the Instalipa portal wins outright.
  The rail reports a balance only as a side effect of a send, so while selling is
  stopped there are no sends and no newer reading can arrive — which means a rail
  reading can never be the fresher of the two whenever it matters. Preferring it would
  trap the line on a figure the admin has already contradicted (scope §10).

  The admin clears the figure once the rail is talking again (`forget_float/0`), so
  this never silently outlives the reason it was entered.
  """
  @spec float() ::
          %{
            cents: integer(),
            at: DateTime.t(),
            order_id: integer() | nil,
            source: :manual | :rail,
            stale?: boolean()
          }
          | nil
  def float do
    case {Settings.airtime_float_manual_cents(), rail_float()} do
      {nil, nil} -> nil
      {manual, nil} -> manual_float(manual)
      {nil, rail} -> rail
      {manual, _rail} -> manual_float(manual)
    end
  end

  @doc """
  The newest balance the rail itself reported, and how old it is.

  Only a side effect of a send, so `stale?` is the important part: a reading we
  cannot refresh is not evidence about now.
  """
  @spec rail_float() ::
          %{
            cents: integer(),
            at: DateTime.t(),
            order_id: integer(),
            source: :rail,
            stale?: boolean()
          }
          | nil
  def rail_float do
    AirtimeOrder
    |> where([o], not is_nil(o.float_cents))
    |> order_by([o], desc: o.id)
    |> limit(1)
    |> select([o], %{cents: o.float_cents, at: o.inserted_at, order_id: o.id})
    |> Repo.one()
    |> case do
      nil ->
        nil

      reading ->
        Map.merge(reading, %{source: :rail, stale?: stale?(reading.at)})
    end
  end

  defp manual_float(cents),
    do: %{
      cents: cents,
      at: DateTime.utc_now(:second),
      order_id: nil,
      source: :manual,
      stale?: false
    }

  defp stale?(at),
    do: DateTime.diff(DateTime.utc_now(:second), at, :second) >= max_age_seconds()

  @doc "How long a rail float reading keeps holding selling off, in seconds."
  @spec max_age_seconds() :: pos_integer()
  def max_age_seconds, do: Settings.airtime_float_max_age_minutes() * 60

  @doc """
  Whether the rail is taking new airtime.

  Selling stops for two reasons and both are checked before a customer is charged:
  a **pause** the super-admin set by hand, and a **floor** the newest float reading
  has fallen under (scope §10). Stopping here is what keeps a float outage from
  becoming a queue of refunds — the customer is never charged for airtime the rail
  cannot deliver.
  """
  @spec sellable?() :: boolean()
  def sellable?, do: not paused?() and not below_float_floor?()

  @doc "Whether the super-admin has paused selling airtime by hand."
  @spec paused?() :: boolean()
  def paused?, do: Settings.instalipa_paused?()

  @doc """
  Whether the float we hold is under the configured floor.

  **A stale reading never counts against you.** We cannot refresh the float while
  selling is stopped — that is the whole reason it stopped — so a reading from
  yesterday is not evidence about today, and treating it as such would lock the line
  off permanently the moment a float dipped. A *fresh* low reading does stop selling:
  that one we trust, and it is the case worth protecting the customer from.
  """
  @spec below_float_floor?() :: boolean()
  def below_float_floor? do
    case float() do
      nil -> false
      %{cents: cents, stale?: stale?} -> not stale? and cents < float_floor_cents()
    end
  end

  @doc "The float floor in cents — selling stops below it."
  @spec float_floor_cents() :: integer()
  def float_floor_cents, do: Settings.airtime_float_floor_cents()

  @doc """
  Records the float the super-admin read off the Instalipa portal.

  The only way to tell the system about a top-up it cannot see (§10). Replaces the
  stale reading until a send reports a newer one.
  """
  @spec record_float(integer(), User.t() | nil) :: :ok | {:error, term()}
  def record_float(cents, actor) when is_integer(cents) and cents >= 0 do
    case Settings.put("airtime_float_manual_cents", Integer.to_string(cents), actor) do
      {:ok, _setting} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Forgets the hand-entered float, so the rail reading stands again."
  @spec forget_float() :: :ok
  def forget_float, do: Settings.clear("airtime_float_manual_cents")

  @doc "Why airtime cannot be sold right now, or nil when it can."
  @spec pause_reason() :: :paused | :float_low | nil
  def pause_reason do
    cond do
      paused?() -> :paused
      below_float_floor?() -> :float_low
      true -> nil
    end
  end

  @doc """
  Orders the rail rejected whose wallet credit never landed — money we still owe.

  A `failed` order with **no** `airtime_refund` entry. The refund and the state
  change are one transaction, so this should always be empty; it exists because
  "should always" is not a guarantee, and a silent loss is the one failure mode a
  payments system may not have. The sweep drains it every minute.
  """
  @spec list_stranded_refunds() :: [AirtimeOrder.t()]
  def list_stranded_refunds do
    refunded_ids =
      from e in LedgerEntry,
        where: e.reason == :airtime_refund and not is_nil(e.airtime_order_id),
        select: e.airtime_order_id

    AirtimeOrder
    |> where([o], o.state == :failed)
    |> where([o], o.id not in subquery(refunded_ids))
    |> order_by([o], asc: o.id)
    |> Repo.all()
  end

  @doc """
  The airtime orders a person has to reconcile, newest first.

  `needs_review` first whatever the filter, because that is the queue with money in
  it waiting on a decision (scope §9).
  """
  @spec list_for_review(list()) :: [AirtimeOrder.t()]
  def list_for_review(states) do
    AirtimeOrder
    |> where([o], o.state in ^states)
    # `desc`, because Postgres orders false before true: the rows waiting on a person
    # are the ones carrying a customer's money, so they lead the queue.
    |> order_by([o], desc: o.state == :needs_review, desc: o.inserted_at, desc: o.id)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "The states the back office can filter by, as `{label, states}`."
  @spec review_filters() :: [{String.t(), [atom()]}]
  def review_filters do
    [
      {"needs_review", [:needs_review]},
      {"failed", [:failed]},
      {"open", [:paid, :sending, :submitted]},
      {"recent", [:delivered, :refunded, :abandoned]},
      {"all", AirtimeOrder.states()}
    ]
  end

  @doc "How many orders sit in each state, for the back office counters."
  @spec counts_by_state() :: %{atom() => non_neg_integer()}
  def counts_by_state do
    AirtimeOrder
    |> group_by([o], o.state)
    |> select([o], {o.state, count(o.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The total cents a customer is currently owed back — money taken but not returned.

  This is the number that must reach zero on its own. Anything left here is a promise
  the system has not kept yet, whether the row is `needs_review` waiting on a person
  or `failed` whose refund never landed.
  """
  @spec outstanding_refund_cents() :: integer()
  def outstanding_refund_cents do
    AirtimeOrder
    |> where([o], o.state in [:failed, :needs_review])
    |> select([o], coalesce(sum(o.amount_cents), 0))
    |> Repo.one()
  end

  @doc "The customer's airtime history, newest first, with their totals."
  @spec history_for_user(User.t(), keyword()) :: %{orders: [AirtimeOrder.t()], stats: map()}
  def history_for_user(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    orders =
      AirtimeOrder
      |> where([o], o.user_id == ^user_id)
      |> order_by([o], desc: o.inserted_at, desc: o.id)
      |> limit(^limit)
      |> Repo.all()

    %{orders: orders, stats: stats_for_user(user_id)}
  end

  @doc "What a customer has spent, got back and is still waiting on, in cents."
  @spec stats_for_user(integer()) :: map()
  def stats_for_user(user_id) do
    row =
      Repo.one(
        from o in AirtimeOrder,
          where: o.user_id == ^user_id,
          select: %{
            spent:
              filter(
                sum(o.amount_cents),
                o.state in [:delivered, :submitted, :sending, :paid, :needs_review]
              ),
            refunded: filter(sum(o.amount_cents), o.state == :refunded),
            delivered: filter(count(o.id), o.state == :delivered),
            failed: filter(count(o.id), o.state in [:failed, :needs_review])
          }
      ) || %{spent: 0, refunded: 0, delivered: 0, failed: 0}

    Map.update!(row, :spent, fn cents ->
      if is_integer(cents), do: cents, else: 0
    end)
    |> Map.update!(:refunded, fn cents -> if is_integer(cents), do: cents, else: 0 end)
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

  @doc """
  A person resolves an ambiguous send against the Instalipa portal (scope §9, §12).

  Two honest answers, and nothing else: the rail **did** deliver it — pasting the
  `transaction_id` from the portal is what makes that claim checkable later — or it
  **never sent**, which is `refund/2`. There is deliberately no "assume delivered"
  button; an unknown send that nobody checks is a customer quietly out of pocket.
  """
  @spec reconcile_delivered(AirtimeOrder.t(), String.t(), User.t() | nil) ::
          {:ok, AirtimeOrder.t()} | {:error, term()}
  def reconcile_delivered(%AirtimeOrder{state: :needs_review} = order, transaction_id, actor) do
    case String.trim(transaction_id) do
      "" ->
        {:error, :missing_transaction_id}

      id ->
        Repo.transact(fn ->
          with {:ok, delivered} <-
                 order
                 |> AirtimeOrder.changeset(%{
                   state: :delivered,
                   instalipa_id: id,
                   instalipa_status: "Success"
                 })
                 |> Repo.update(),
               {:ok, _event} <-
                 record_event(
                   delivered,
                   :needs_review,
                   :delivered,
                   "reconciled as delivered against the rail",
                   actor
                 ) do
            {:ok, delivered}
          end
        end)
    end
  end

  def reconcile_delivered(%AirtimeOrder{}, _transaction_id, _actor),
    do: {:error, :not_reconcilable}

  @doc "The rail reported a failure. The caller decides whether to refund."
  @spec mark_failed(AirtimeOrder.t(), String.t() | nil, String.t() | nil) ::
          {:ok, AirtimeOrder.t()} | {:error, term()}
  def mark_failed(%AirtimeOrder{state: state} = order, kind, message)
      when state in [:sending, :submitted] do
    transition(order, :failed, message, %{failure_kind: kind, failure_message: message})
  end

  def mark_failed(%AirtimeOrder{} = order, kind, message),
    do: transition(order, :failed, message, %{failure_kind: kind, failure_message: message})

  @doc """
  A definite rejection: the order fails **and** the wallet is credited back, in one
  transaction (docs/instalipa-airtime.md §12).

  Both halves or neither. This is the whole point — splitting them into two writes
  leaves a window where a crash strands the customer: the order reads `failed`, the
  money never comes back, and `max_attempts: 1` means nothing retries it. One
  transaction closes that window, and the partial unique index on
  `(airtime_order_id, reason)` still refuses a second credit.
  """
  @spec fail_and_refund(AirtimeOrder.t(), String.t() | nil, String.t() | nil, keyword()) ::
          {:ok, AirtimeOrder.t()} | {:error, term()}
  def fail_and_refund(order, kind, message, opts \\ [])

  def fail_and_refund(%AirtimeOrder{state: state} = order, kind, message, opts)
      when state in [:sending, :submitted] do
    result =
      Repo.transact(fn ->
        with {:ok, failed} <-
               move(order, :failed, message, %{
                 failure_kind: kind,
                 failure_message: message
               }),
             {:ok, refunded} <-
               move(failed, :refunded, "refunded to your wallet", %{}),
             {:ok, _entry} <- credit_wallet(refunded, opts[:actor]) do
          {:ok, refunded}
        end
      end)

    announce(result)
  end

  def fail_and_refund(%AirtimeOrder{}, _kind, _message, _opts), do: {:error, :not_failable}

  # The wallet credit for a refund. Inside the caller's transaction, so it is the same
  # atomic unit as the state change — never call this on its own.
  @spec credit_wallet(AirtimeOrder.t(), User.t() | nil) ::
          {:ok, LedgerEntry.t()} | {:error, term()}
  defp credit_wallet(%AirtimeOrder{} = order, actor) do
    Wallet.record(%{
      user_id: order.user_id,
      amount_cents: order.amount_cents,
      reason: :airtime_refund,
      airtime_order_id: order.id,
      actor_id: actor && actor.id
    })
  end

  # A refund is the moment a person hears about it, so it is announced and alerted
  # whether it committed or not — a failed refund is money we still owe.
  defp announce({:ok, %AirtimeOrder{} = order}) do
    :ok =
      Alerts.publish(
        :airtime_refunded,
        "airtime #{order.id} refunded: #{order.phone}",
        %{airtime_order_id: order.id, amount_cents: order.amount_cents}
      )

    {:ok, order}
  end

  defp announce({:error, reason} = error) do
    _ =
      Alerts.publish(
        :airtime_refund_failed,
        "an airtime refund did not commit: #{inspect(reason)}"
      )

    error
  end

  @doc """
  Parks an order for a person: an ambiguous send, never a second one.

  The money stays where it is — we do not know whether the airtime went out — but an
  alert goes out, so "a customer is waiting on a decision" is never a thing that only
  the database knows.
  """
  @spec mark_needs_review(AirtimeOrder.t(), String.t()) ::
          {:ok, AirtimeOrder.t()} | {:error, term()}
  def mark_needs_review(%AirtimeOrder{state: state} = order, reason)
      when state in [:paid, :sending, :submitted] do
    transition(order, :needs_review, reason)
    |> tap_needs_review_alert(order, reason)
  end

  defp tap_needs_review_alert({:ok, %AirtimeOrder{} = moved}, original, reason) do
    :ok =
      Alerts.publish(
        :airtime_needs_review,
        "airtime #{original.id} needs a person: #{reason}",
        %{airtime_order_id: original.id, phone: original.phone}
      )

    {:ok, moved}
  end

  defp tap_needs_review_alert(other, _original, _reason), do: other

  @doc "Credits the wallet back and closes the order. Refuses anything not refundable."
  @spec refund(AirtimeOrder.t(), keyword()) :: {:ok, AirtimeOrder.t()} | {:error, term()}
  def refund(order, opts \\ [])

  def refund(%AirtimeOrder{state: state} = order, opts)
      when state in [:failed, :needs_review] do
    result =
      Repo.transact(fn ->
        with {:ok, refunded} <- move(order, :refunded, "refunded to your wallet", %{}),
             {:ok, _entry} <- credit_wallet(refunded, opts[:actor]) do
          {:ok, refunded}
        end
      end)

    announce(result)
  end

  def refund(%AirtimeOrder{}, _opts), do: {:error, :not_refundable}

  defp transition(order, to_state, reason, attrs \\ %{}) do
    Repo.transact(fn -> move(order, to_state, reason, attrs) end)
  end

  # The state change and its timeline line, without opening a transaction — for
  # callers that are already inside one, so a move and a refund are one unit.
  defp move(order, to_state, reason, attrs) do
    with {:ok, moved} <-
           order
           |> AirtimeOrder.changeset(Map.merge(attrs, %{state: to_state}))
           |> Repo.update(),
         {:ok, _event} <- record_event(moved, order.state, to_state, reason) do
      {:ok, moved}
    end
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

  @doc "The customer's remembered numbers, most recently bought first."
  @spec list_recipients(User.t()) :: [SavedRecipient.t()]
  def list_recipients(%User{id: user_id}) do
    SavedRecipient
    |> where([r], r.user_id == ^user_id)
    # `id` breaks a same-second tie, so the order is stable.
    |> order_by([r], desc_nulls_last: r.last_used_at, desc: r.id)
    |> Repo.all()
  end

  @doc """
  Files each recipient away for reuse, so **saving happens by buying** — there is no
  separate "save this number" step. Idempotent and label-preserving: a number already
  on the list only has its `last_used_at` bumped, so the picker floats it and a name it
  may carry later is never wiped.
  """
  @spec remember_recipients(User.t(), [String.t()]) :: :ok
  def remember_recipients(%User{id: user_id}, phones) when is_list(phones) do
    now = DateTime.utc_now(:second)

    Enum.each(phones, fn phone ->
      %SavedRecipient{}
      |> SavedRecipient.changeset(%{user_id: user_id, phone: phone, last_used_at: now})
      |> Repo.insert(
        on_conflict: {:replace, [:last_used_at, :updated_at]},
        conflict_target: [:user_id, :phone]
      )
    end)

    :ok
  end

  @doc "Removes a saved number, but only one this customer owns."
  @spec delete_recipient(User.t(), integer()) :: :ok
  def delete_recipient(%User{id: user_id}, id) do
    SavedRecipient
    |> where([r], r.id == ^id and r.user_id == ^user_id)
    |> Repo.delete_all()

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
