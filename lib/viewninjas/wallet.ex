defmodule ViewNinjas.Wallet do
  @moduledoc """
  The wallet: an append-only ledger of signed KES cents (scope.md §6).

  The balance is the **sum** of the entries, never a column someone updates in
  place, and a correction is a new, opposite row. Entries are written by the
  money flows — a settled top-up crediting, an order captured — and never
  edited. Filtering is by `user_id`; the web layer passes `current_scope.user`.
  """

  import Ecto.Query

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Repo
  alias ViewNinjas.Wallet.LedgerEntry

  @doc "The wallet balance in KES cents. Zero when there is no ledger yet."
  @spec balance(User.t() | integer() | nil) :: integer()
  def balance(nil), do: 0
  def balance(%User{id: id}), do: balance(id)

  def balance(id) when is_integer(id) do
    Repo.one(
      from e in LedgerEntry,
        where: e.user_id == ^id,
        select: coalesce(sum(e.amount_cents), 0)
    )
  end

  @doc "The ledger, newest first."
  @spec list_entries(User.t() | integer(), pos_integer()) :: [LedgerEntry.t()]
  def list_entries(user, limit \\ 50)

  def list_entries(%User{id: id}, limit), do: list_entries(id, limit)

  def list_entries(id, limit) when is_integer(id) do
    LedgerEntry
    |> where([e], e.user_id == ^id)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Appends a ledger entry; nothing is ever updated.

  Returns `{:error, :already_recorded}` when this payment — or this order refund
  — has already produced an entry with the same reason: the database refuses the
  double write, so a replayed callback or a repeated partial report can never
  double-credit (scope.md §8, §10).
  """
  @spec record(map()) ::
          {:ok, LedgerEntry.t()} | {:error, :already_recorded} | {:error, Ecto.Changeset.t()}
  def record(attrs) do
    changeset =
      %LedgerEntry{}
      |> LedgerEntry.changeset(attrs)
      |> Ecto.Changeset.unique_constraint([:payment_id, :reason],
        name: :ledger_entries_payment_reason_index
      )
      |> Ecto.Changeset.unique_constraint([:order_id, :reason],
        name: :ledger_entries_order_reason_index
      )

    case Repo.insert(changeset) do
      {:ok, entry} ->
        {:ok, entry}

      {:error, %Ecto.Changeset{errors: errors} = failed} ->
        # The partial unique indexes fire on the first constrained field.
        if Keyword.has_key?(errors, :payment_id) or Keyword.has_key?(errors, :order_id),
          do: {:error, :already_recorded},
          else: {:error, failed}
    end
  end

  @doc "Credits a settled top-up payment."
  @spec topup(Payment.t()) ::
          {:ok, LedgerEntry.t()} | {:error, :already_recorded} | {:error, Ecto.Changeset.t()}
  def topup(%Payment{purpose: :topup, status: :settled} = payment) do
    record(%{
      user_id: payment.user_id,
      amount_cents: payment.amount_cents,
      reason: :topup,
      payment_id: payment.id
    })
  end

  @doc """
  Whether an order already has a refund entry.

  Checked before inserting a partial credit: the unique index on
  `(order_id, reason)` is the database's invariant, but a violation would abort
  the surrounding transaction, so the caller looks first.
  """
  @spec refunded?(Order.t() | integer()) :: boolean()
  def refunded?(%Order{id: order_id}), do: refunded?(order_id)

  def refunded?(order_id) when is_integer(order_id) do
    Repo.exists?(from e in LedgerEntry, where: e.order_id == ^order_id and e.reason == :refund)
  end

  @doc "Debits the wallet for an order — the same transaction that marks it paid."
  @spec capture_order(Order.t()) ::
          {:ok, LedgerEntry.t()} | {:error, :already_recorded} | {:error, Ecto.Changeset.t()}
  def capture_order(%Order{} = order) do
    record(%{
      user_id: order.user_id,
      amount_cents: -order.retail_cents,
      reason: :order_capture,
      order_id: order.id
    })
  end
end
