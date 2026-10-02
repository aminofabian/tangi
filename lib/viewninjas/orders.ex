defmodule ViewNinjas.Orders do
  @moduledoc """
  Orders and their state machine (scope.md §6, §7, §8).

  An order is created `awaiting_payment` and priced from its lane at that moment:
  retail cents, USD cost, margin, buffer and the FX rate row are all copied in, so
  nothing later moves what the customer agreed to pay.

  Money reaches an order in exactly two ways, and both end in `paid`:
  `mark_paid/1` after a confirming GET says a M-Pesa payment settled, and
  `pay_from_wallet/1` as a single debit-and-mark-paid transaction. Filtering is by
  `user_id`; the web layer passes `current_scope.user`.

  ## One order per service at a time

  A customer may hold **one** order per lane at a time. `create_order/1` refuses with
  `{:error, :service_in_progress}` while one is still owed, so the rule holds no matter
  which door they came through — the offer page, "order again", or a repeat.

  The states that block are the ones where money has been taken and work is still owed
  (`Order.blocking_states/0`). An unpaid `awaiting_payment` order deliberately does
  **not** block: it costs the customer nothing, and nothing ever expires it, so blocking
  on it would strand them on a lane they can no longer buy after one abandoned checkout.
  """

  import Ecto.Query

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Catalog.Lane
  alias ViewNinjas.Notifications
  alias ViewNinjas.Orders.{Order, OrderEvent, Refill, SupplierStatus}
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Pricing
  alias ViewNinjas.Repo
  alias ViewNinjas.Wallet
  alias ViewNinjas.Workers.{PlaceOrder, RefillOrder}

  @pubsub ViewNinjas.PubSub

  # -- creating ----------------------------------------------------------

  @doc """
  Creates an order from a lane and freezes the price it was quoted at.

  The lane must be preloaded with its `supplier_service` (and its supplier, so a
  paused panel can be refused before any money moves — scope.md §10).

  Refused with `{:error, :service_in_progress}` when this customer already has an order
  on this lane that is still owed — one purchase of a service at a time, whichever door
  the customer came through.
  """
  @spec create_order(map()) ::
          {:ok, Order.t()} | {:error, Ecto.Changeset.t() | :lane_paused | :service_in_progress}
  def create_order(%{user: %User{} = user, lane: %Lane{} = lane, link: link, quantity: quantity}) do
    cond do
      Lane.paused?(lane) ->
        # The supplier is out of float: the grade shows as paused before payment.
        {:error, :lane_paused}

      in_progress?(user.id, lane.id) ->
        {:error, :service_in_progress}

      true ->
        insert_order(user, lane, link, quantity)
    end
  end

  @doc """
  Whether this customer already has an order on this lane that is still owed.

  Serialised on the user, so two taps that arrive together cannot both pass the check
  and leave the customer with two live orders for one service.
  """
  @spec in_progress?(integer(), integer() | nil) :: boolean()
  def in_progress?(_user_id, nil), do: false

  def in_progress?(user_id, lane_id) do
    _lock = lock_user(user_id)

    Repo.exists?(
      from o in Order,
        where:
          o.user_id == ^user_id and o.lane_id == ^lane_id and o.state in ^Order.blocking_states()
    )
  end

  # One customer's orders are serialised the same way airtime's are, so two taps on
  # "buy" cannot both pass the in-progress check.
  defp lock_user(user_id) do
    Repo.one!(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE")
  end

  @doc """
  The customer's still-owed order for a lane, for the message that explains the block.
  """
  @spec in_progress_order(User.t(), integer() | nil) :: Order.t() | nil
  def in_progress_order(_user, nil), do: nil

  def in_progress_order(%User{id: user_id}, lane_id) do
    Order
    |> where([o], o.user_id == ^user_id and o.lane_id == ^lane_id)
    |> where([o], o.state in ^Order.blocking_states())
    |> order_by([o], desc: o.id)
    |> limit(1)
    |> Repo.one()
  end

  defp insert_order(%User{} = user, %Lane{} = lane, link, quantity) do
    params = Pricing.current()
    rate = lane.supplier_service && lane.supplier_service.rate_micros

    Repo.transact(fn ->
      with {:ok, order} <-
             %Order{}
             |> Order.changeset(%{
               user_id: user.id,
               lane_id: lane.id,
               link: link,
               quantity: quantity,
               retail_cents: Lane.retail_kes_cents(lane, params, quantity),
               cost_usd_micros: rate && Pricing.cost_usd_ppm(rate, quantity),
               margin_bps: params.margin_bps,
               buffer_bps: params.buffer_bps,
               fx_rate_id: current_fx_rate_id(),
               state: :awaiting_payment
             })
             |> Repo.insert(),
           {:ok, _event} <- record_event(order, nil, :awaiting_payment, "created") do
        {:ok, order}
      end
    end)
  end

  @doc """
  A fresh order with the same link, grade and quantity, priced as of now.

  An order still `awaiting_payment` is not copied — that one is finished by paying it,
  not by starting another. An order still being delivered is not copied either, because
  `create_order/1` holds one-per-lane: buying the same service again while one is owed
  would stack two live orders on one service. A lane that has come off sale returns
  `{:error, :unavailable}`.
  """
  @spec repeat_order(User.t(), Order.t()) ::
          {:ok, Order.t()}
          | {:error, :still_open | :unavailable | :not_found | :service_in_progress | term()}
  def repeat_order(%User{id: user_id} = user, %Order{user_id: user_id} = order) do
    lane = lane_for_repeat(order.lane_id)

    cond do
      order.state == :awaiting_payment ->
        {:error, :still_open}

      is_nil(lane) or not Lane.on_sale?(lane) ->
        {:error, :unavailable}

      true ->
        create_order(%{
          user: user,
          lane: lane,
          link: order.link,
          quantity: order.quantity
        })
    end
  end

  def repeat_order(%User{}, %Order{}), do: {:error, :not_found}

  defp lane_for_repeat(lane_id) do
    case Repo.get(Lane, lane_id) do
      nil -> nil
      lane -> Repo.preload(lane, supplier_service: :supplier)
    end
  end

  defp current_fx_rate_id do
    case Pricing.current_fx() do
      nil -> nil
      fx -> fx.id
    end
  end

  # -- reading -----------------------------------------------------------

  def get_order(id), do: Repo.get(Order, id)
  def get_order!(id), do: Repo.get!(Order, id)

  @doc "An order with its lane, offer and pinned service + supplier loaded."
  def get_order_with_lane(id) do
    Order
    |> preload(lane: [:offer, supplier_service: :supplier])
    |> Repo.get(id)
  end

  @doc "The orders the status batch should ask a panel about (scope.md §10)."
  def list_for_status_sync(opts \\ []) do
    limit = Keyword.get(opts, :limit, 2_000)

    Order
    |> where([o], o.state in ^Order.pollable_states() and not is_nil(o.supplier_order_id))
    |> order_by([o], asc: o.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc "An order by the panel's id, within one supplier."
  def get_by_supplier_order(supplier_id, supplier_order_id) do
    Repo.get_by(Order, supplier_id: supplier_id, supplier_order_id: to_string(supplier_order_id))
  end

  @doc "One order, but only when it belongs to this customer."
  def get_order_for_user(%User{id: user_id}, id) do
    Order
    |> where([o], o.id == ^id and o.user_id == ^user_id)
    |> preload(lane: [:offer, :supplier_service])
    |> Repo.one()
  end

  @doc "The customer's orders, newest first."
  def list_orders(%User{id: user_id}, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Order
    |> where([o], o.user_id == ^user_id)
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(^limit)
    |> preload(lane: [:offer])
    |> Repo.all()
  end

  @doc "Orders the customer is still owed — the dashboard's \"in progress\"."
  def count_open(%User{id: user_id}) do
    Order
    |> where([o], o.user_id == ^user_id and o.state in ^Order.open_states())
    |> Repo.aggregate(:count)
  end

  @doc "The order's timeline, oldest first."
  def timeline(%Order{id: order_id}) do
    OrderEvent
    |> where([e], e.order_id == ^order_id)
    |> order_by([e], asc: e.inserted_at, asc: e.id)
    |> preload(:actor)
    |> Repo.all()
  end

  # -- money reaching an order -------------------------------------------

  @doc """
  Marks the order behind a settled payment as paid. Idempotent.

  Called inside the settlement transaction, so it opens none of its own.
  """
  @spec mark_paid(Payment.t()) :: {:ok, Order.t()} | {:error, term()}
  def mark_paid(%Payment{order_id: order_id} = payment) when is_integer(order_id) do
    case Repo.get(Order, order_id) do
      nil -> {:error, :no_order}
      order -> mark_paid(order, payment.receipt)
    end
  end

  def mark_paid(%Payment{}), do: {:error, :no_order}

  def mark_paid(%Order{state: :awaiting_payment} = order, receipt) do
    with {:ok, paid} <- order |> Order.state_changeset(:paid) |> Repo.update(),
         {:ok, _event} <- record_event(paid, :awaiting_payment, :paid, paid_reason(receipt)) do
      _ = Notifications.enqueue(paid, :paid)
      {:ok, paid}
    end
  end

  # Already paid or further along: nothing to do, and nothing to undo.
  def mark_paid(%Order{} = order, _receipt), do: {:ok, order}

  @doc """
  Pays an order from the wallet: the debit and the `paid` state in one
  transaction (scope.md §8). Refuses when the balance will not cover it, and
  takes a row lock so two taps cannot both pass the check.
  """
  @spec pay_from_wallet(Order.t()) :: {:ok, Order.t()} | {:error, term()}
  def pay_from_wallet(%Order{state: :awaiting_payment} = order) do
    case Repo.transact(fn -> wallet_transaction(order) end) do
      {:ok, paid} = ok ->
        # Queued only once the debit has committed, so the job can never run
        # against uncommitted state.
        _ = enqueue_placement(paid)
        ok

      error ->
        error
    end
  end

  def pay_from_wallet(%Order{}), do: {:error, :not_payable}

  defp wallet_transaction(order) do
    # Serialise one customer's wallet checkouts so two taps cannot both pass.
    Repo.one!(from u in User, where: u.id == ^order.user_id, lock: "FOR UPDATE")

    if Wallet.balance(order.user_id) >= order.retail_cents do
      capture_and_pay(order)
    else
      {:error, :insufficient_funds}
    end
  end

  defp capture_and_pay(order) do
    with {:ok, _entry} <- Wallet.capture_order(order),
         {:ok, paid} <- transition_in_transaction(order, :paid, "wallet") do
      {:ok, paid}
    else
      {:error, :already_recorded} -> {:error, :already_captured}
      other -> other
    end
  end

  # -- the state machine -------------------------------------------------

  @doc "Moves an order to a new state and logs it. Refuses to move a finished one."
  @spec transition(Order.t(), atom(), keyword()) :: {:ok, Order.t()} | {:error, term()}
  def transition(%Order{} = order, to_state, opts \\ []) do
    Repo.transact(fn ->
      transition_in_transaction(
        order,
        to_state,
        Keyword.get(opts, :reason),
        Keyword.get(opts, :actor),
        opts
      )
    end)
  end

  defp transition_in_transaction(order, to_state, reason, actor \\ nil, opts \\ []) do
    with {:ok, updated} <- order |> Order.state_changeset(to_state, opts) |> Repo.update(),
         {:ok, _event} <- record_event(updated, order.state, to_state, reason, actor) do
      {:ok, updated}
    end
  end

  @doc "Appends one line to an order's story (scope.md §6)."
  @spec record_event(Order.t(), atom() | nil, atom(), String.t() | nil, User.t() | nil) ::
          {:ok, OrderEvent.t()} | {:error, Ecto.Changeset.t()}
  def record_event(%Order{} = order, from_state, to_state, reason \\ nil, actor \\ nil) do
    %OrderEvent{}
    |> OrderEvent.changeset(%{
      order_id: order.id,
      from_state: state_string(from_state),
      to_state: state_string(to_state),
      reason: reason,
      actor_id: actor && actor.id
    })
    |> Repo.insert()
  end

  defp state_string(nil), do: nil
  defp state_string(state), do: to_string(state)

  defp paid_reason(nil), do: "M-Pesa payment settled"
  defp paid_reason(receipt), do: "M-Pesa receipt #{receipt}"

  # -- fulfilment (M8) ---------------------------------------------------

  @doc """
  Queues placement for a paid order (scope.md §10).

  Call **after** the paying transaction has committed. Only a `paid` order is
  queued, so calling it twice is harmless — and the placement job itself never
  calls `add` twice.
  """
  @spec enqueue_placement(Order.t()) :: {:ok, Oban.Job.t() | :nothing_to_place} | {:error, term()}
  def enqueue_placement(%Order{state: :paid, id: id}), do: PlaceOrder.enqueue(id)
  def enqueue_placement(%Order{}), do: {:ok, :nothing_to_place}

  @doc """
  Persists the placement intent — the supplier, the service, and `placing` —
  *before* `add` is ever sent (scope.md §5, step 1).
  """
  @spec mark_placing(Order.t(), integer(), integer()) :: {:ok, Order.t()} | {:error, term()}
  def mark_placing(%Order{state: :paid} = order, supplier_id, supplier_service_id) do
    attrs = %{supplier_id: supplier_id, supplier_service_id: supplier_service_id, state: :placing}

    Repo.transact(fn ->
      with {:ok, placing} <- order |> Order.changeset(attrs) |> Repo.update(),
           {:ok, _event} <- record_event(placing, :paid, :placing, "placement started") do
        {:ok, placing}
      end
    end)
    |> announce()
  end

  @doc "The panel accepted the order; its id is stored and the order is `placed`."
  @spec mark_placed(Order.t(), String.t()) :: {:ok, Order.t()} | {:error, term()}
  def mark_placed(%Order{state: :placing} = order, supplier_order_id) do
    id = to_string(supplier_order_id)

    Repo.transact(fn ->
      with {:ok, placed} <-
             order |> Order.changeset(%{supplier_order_id: id, state: :placed}) |> Repo.update(),
           {:ok, _event} <- record_event(placed, :placing, :placed, "the order was placed") do
        {:ok, placed}
      end
    end)
    |> announce()
  end

  @doc """
  A definite rejection: the order fails and the wallet is credited back, in one
  transaction (scope.md §5, §10).

  Only a `placing` order reaches this, so the refund can never double-credit.
  """
  @spec mark_failed_and_refund(Order.t(), String.t()) :: {:ok, Order.t()} | {:error, term()}
  def mark_failed_and_refund(%Order{state: :placing} = order, reason) do
    Repo.transact(fn ->
      with {:ok, failed} <- transition_in_transaction(order, :failed, reason),
           {:ok, refunded} <-
             transition_in_transaction(failed, :refunded, "refunded to your wallet"),
           {:ok, _entry} <- refund_wallet(refunded) do
        {:ok, refunded}
      end
    end)
    |> announce()
    |> notify(:refunded)
  end

  @doc """
  The `add` never resolved, or never started. The order stays visible for a person
  to reconcile, and `add` is never called again (scope.md §5, step 5).
  """
  @spec mark_needs_review(Order.t(), String.t()) :: {:ok, Order.t()} | {:error, term()}
  def mark_needs_review(%Order{state: state} = order, reason) when state in [:paid, :placing] do
    transition(order, :needs_review, reason: reason)
  end

  @doc "Writes what the panel reported back onto the order (scope.md §10)."
  @spec apply_supplier_status(Order.t(), map()) :: {:ok, Order.t()} | {:error, term()}
  def apply_supplier_status(%Order{state: previous} = order, report) do
    Repo.transact(fn ->
      # Serialise reports for one order, so a repeated partial cannot race itself
      # into a second credit.
      _lock = lock_order(order.id)

      with {:ok, updated} <- order |> Order.changeset(status_attrs(report)) |> Repo.update(),
           {:ok, moved} <- transition_from_report(updated, report) do
        # A partial is a normal outcome: the undelivered share goes back to the
        # wallet at the KES-per-unit the order captured (scope.md §6, §10).
        credit_partial(moved)
      end
    end)
    |> announce()
    |> notify_transition(previous)
  end

  defp lock_order(id), do: Repo.one!(from o in Order, where: o.id == ^id, lock: "FOR UPDATE")

  defp status_attrs(report) do
    # Only the fields the panel actually reported are written, so a report that
    # omits one does not blank out a number we already hold.
    attrs =
      %{
        supplier_status: :status,
        start_count: :start_count,
        remains: :remains,
        charge_usd_micros: :charge_usd_micros,
        currency: :currency
      }
      |> Enum.flat_map(fn {column, key} ->
        case Map.fetch(report, key) do
          {:ok, value} -> [{column, value}]
          :error -> []
        end
      end)
      |> Map.new()

    # A charge in another currency is not converted on a guess (§10).
    if usd?(Map.get(report, :currency)) do
      attrs
    else
      Map.delete(attrs, :charge_usd_micros)
    end
  end

  defp usd?(nil), do: true
  defp usd?(currency), do: String.upcase(currency) == "USD"

  # An unknown word keeps the state we already had; an unchanged one records no
  # event, so a minute-by-minute poll does not spam the timeline. The reason is
  # left off: the supplier's word and id belong on the order row for staff, never
  # on the customer's timeline (scope.md §13).
  defp transition_from_report(order, %{status: raw}) do
    case SupplierStatus.map(raw) do
      nil -> {:ok, order}
      state when state == order.state -> {:ok, order}
      state -> transition_in_transaction(order, state, nil)
    end
  end

  defp refund_wallet(order, actor \\ nil) do
    attrs = %{
      user_id: order.user_id,
      amount_cents: order.retail_cents,
      reason: :refund,
      order_id: order.id,
      actor_id: actor && actor.id
    }

    case Wallet.record(attrs) do
      {:ok, entry} -> {:ok, entry}
      {:error, :already_recorded} -> {:ok, :already_refunded}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # -- partials (M9) -----------------------------------------------------

  @doc """
  The KES cents owed back for a partial's undelivered share, or nil when the
  order does not carry the numbers to work it out.

  The per-unit price is the one captured on the order — `retail_cents` over
  `quantity` — so a later change to the knobs cannot move the refund (§6).
  """
  @spec partial_cents(Order.t()) :: non_neg_integer() | nil
  def partial_cents(%Order{retail_cents: retail, quantity: quantity, remains: remains})
      when is_integer(retail) and is_integer(quantity) and quantity > 0 and
             is_integer(remains) and remains > 0 do
    div(retail * min(remains, quantity), quantity)
  end

  def partial_cents(%Order{}), do: nil

  defp credit_partial(%Order{state: :partial} = order), do: refund_share(order)
  defp credit_partial(%Order{} = order), do: {:ok, order}

  defp refund_share(order) do
    case partial_cents(order) do
      0 -> {:ok, order}
      nil -> {:ok, order}
      cents -> refund_partial(order, cents)
    end
  end

  defp refund_partial(order, cents) do
    # The unique index on (order_id, reason) is the database's invariant, but a
    # violation would abort the transaction, so the check is done first.
    if Wallet.refunded?(order) do
      {:ok, order}
    else
      insert_partial_refund(order, cents)
    end
  end

  defp insert_partial_refund(order, cents) do
    attrs = %{user_id: order.user_id, amount_cents: cents, reason: :refund, order_id: order.id}

    case Wallet.record(attrs) do
      {:ok, _entry} -> {:ok, order}
      {:error, :already_recorded} -> {:ok, order}
      {:error, changeset} -> {:error, changeset}
    end
  end

  # -- refills (M9) ------------------------------------------------------

  @doc "Whether this order can be refilled right now (scope.md §10)."
  @spec refillable?(Order.t()) :: boolean()
  def refillable?(%Order{} = order) do
    order.state == :completed and refill_offered?(order) and is_nil(get_refill(order))
  end

  defp refill_offered?(%Order{lane: %{supplier_service: %{refill: true}}}), do: true
  defp refill_offered?(%Order{}), do: false

  def get_refill(id) when is_integer(id), do: Repo.get(Refill, id)

  @doc "The order's single refill row, if any."
  @spec get_refill(Order.t()) :: Refill.t() | nil
  def get_refill(%Order{id: order_id}), do: Repo.get_by(Refill, order_id: order_id)

  @doc "The refills still waiting on the panel, with their order and supplier."
  @spec list_refills_for_status_sync(keyword()) :: [Refill.t()]
  def list_refills_for_status_sync(opts \\ []) do
    limit = Keyword.get(opts, :limit, 2_000)

    Refill
    |> where([r], r.state == :requested and not is_nil(r.supplier_refill_id))
    |> order_by([r], asc: r.id)
    |> limit(^limit)
    |> preload(order: :supplier)
    |> Repo.all()
  end

  @doc """
  Opens the one refill for a completed order and queues the single supplier call
  (scope.md §10). A second call is refused: a rejected refill stays rejected.
  """
  @spec request_refill(Order.t()) :: {:ok, Refill.t()} | {:error, term()}
  def request_refill(%Order{} = order) do
    if refillable?(order), do: open_refill(order), else: {:error, :not_refillable}
  end

  defp open_refill(order) do
    with {:ok, refill} <-
           %Refill{}
           |> Refill.changeset(%{order_id: order.id, state: :requested})
           |> Repo.insert(),
         {:ok, _job} <- RefillOrder.enqueue(refill.id) do
      {:ok, refill}
    end
  end

  @doc "Stores the panel's refill id once the single call has answered."
  @spec mark_refill_requested(Refill.t(), String.t()) ::
          {:ok, Refill.t()} | {:error, term()}
  def mark_refill_requested(%Refill{state: :requested} = refill, supplier_refill_id) do
    refill
    |> Refill.changeset(%{supplier_refill_id: to_string(supplier_refill_id)})
    |> Repo.update()
  end

  @doc "Records a definite rejection; the refill stays rejected (scope.md §10)."
  @spec mark_refill_rejected(Refill.t(), String.t()) :: {:ok, Refill.t()} | {:error, term()}
  def mark_refill_rejected(%Refill{} = refill, reason) do
    refill
    |> Refill.changeset(%{state: :rejected, reason: reason})
    |> Repo.update()
  end

  @doc "Writes what the panel said about a refill, keeping the state when unknown."
  @spec apply_refill_status(Refill.t(), String.t() | nil) :: {:ok, Refill.t()} | {:error, term()}
  def apply_refill_status(%Refill{} = refill, raw) do
    case Refill.status_from(raw) do
      nil ->
        {:ok, refill}

      state when state == refill.state ->
        {:ok, refill}

      state ->
        refill
        |> Refill.changeset(%{state: state, reason: "supplier said #{raw}"})
        |> Repo.update()
    end
  end

  # -- the admin review queue (M9) ---------------------------------------

  @doc "Orders in any of the given states, newest first — the review queue."
  @spec list_by_states([atom()], keyword()) :: [Order.t()]
  def list_by_states(states, opts \\ []) when is_list(states) do
    limit = Keyword.get(opts, :limit, 100)

    Order
    |> where([o], o.state in ^states)
    |> order_by([o], desc: o.inserted_at, desc: o.id)
    |> limit(^limit)
    |> preload(lane: [:offer])
    |> Repo.all()
  end

  @doc "A person attaches the supplier's order id to a `needs_review` order."
  @spec admin_attach(Order.t(), String.t(), User.t() | nil) :: {:ok, Order.t()} | {:error, term()}
  def admin_attach(%Order{state: :needs_review} = order, supplier_order_id, actor) do
    id = to_string(supplier_order_id)

    Repo.transact(fn ->
      with {:ok, placed} <-
             order |> Order.changeset(%{supplier_order_id: id, state: :placed}) |> Repo.update(),
           {:ok, _event} <-
             record_event(
               placed,
               :needs_review,
               :placed,
               "the order was placed",
               actor
             ) do
        {:ok, placed}
      end
    end)
    |> announce()
  end

  @doc "A person refunds a `needs_review` order that was never placed."
  @spec admin_refund(Order.t(), User.t() | nil) :: {:ok, Order.t()} | {:error, term()}
  def admin_refund(%Order{state: :needs_review} = order, actor) do
    Repo.transact(fn ->
      with {:ok, refunded} <-
             transition_in_transaction(order, :refunded, "refunded to your wallet", actor),
           {:ok, _entry} <- refund_wallet(order, actor) do
        {:ok, refunded}
      end
    end)
    |> announce()
    |> notify(:refunded)
  end

  # -- pubsub ------------------------------------------------------------

  @doc "Subscribes the caller to one customer's order changes."
  def subscribe(%User{id: id}), do: Phoenix.PubSub.subscribe(@pubsub, topic(id))
  def subscribe(id) when is_integer(id), do: Phoenix.PubSub.subscribe(@pubsub, topic(id))

  @doc """
  Tells a customer's pages an order changed, carrying the fresh row.

  The row travels in the message, so a page can render the new state without a
  second read.
  """
  def broadcast(%Order{user_id: user_id} = order) do
    Phoenix.PubSub.broadcast(@pubsub, topic(user_id), {:order, order})
  end

  defp announce({:ok, %Order{} = order} = ok) do
    broadcast(order)
    ok
  end

  defp announce(error), do: error

  # Tells the customer, once, that the order moved to a state worth a message.
  defp notify(%Order{} = order, event) do
    _ = Notifications.enqueue(order, event)
    :ok
  end

  defp notify({:ok, %Order{} = order} = ok, event) do
    notify(order, event)
    ok
  end

  defp notify(other, _event), do: other

  # After a committed report: notify only when the state actually changed.
  defp notify_transition({:ok, %Order{state: state} = order} = ok, previous) do
    if state != previous and state in [:completed, :refunded, :partial] do
      notify(order, state)
    end

    ok
  end

  defp notify_transition(other, _previous), do: other

  defp topic(user_id), do: "orders:user:#{user_id}"
end
