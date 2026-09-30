defmodule ViewNinjas.Overview do
  @moduledoc """
  The first admin overview (scope.md §10, §11; build-plan.md M9).

  Three questions, all answered from rows the earlier milestones already write:
  how an order travels from paid to completed, whether payments settle, and how
  much money is at risk right now. Profit, progress and traffic are M10's job —
  this is deliberately a read, nothing here is stored.
  """

  import Ecto.Query

  alias ViewNinjas.Orders.Order
  alias ViewNinjas.Payments.Payment
  alias ViewNinjas.Repo

  # The order's journey, in order, from money taken to work done.
  @funnel ~w(paid placing placed in_progress partial completed)a

  @doc "The order funnel: `[{state, count}]`, in order."
  @spec funnel() :: [{atom(), non_neg_integer()}]
  def funnel do
    counts = counts_by(Order, :state)

    Enum.map(@funnel, &{&1, Map.get(counts, &1, 0)})
  end

  @doc "Payments by status: `%{settled: n, failed: n, pending: n}`."
  @spec payment_counts() :: %{atom() => non_neg_integer()}
  def payment_counts, do: counts_by(Payment, :status)

  @doc "The retail in KES cents of every order still owed — the money at risk."
  @spec money_at_risk_cents() :: non_neg_integer()
  def money_at_risk_cents do
    Order
    |> where([o], o.state in ^Order.open_states())
    |> select([o], coalesce(sum(o.retail_cents), 0))
    |> Repo.one()
  end

  @doc "How many orders are waiting on a person: `%{needs_review: n, partial: n}`."
  @spec review_counts() :: %{atom() => non_neg_integer()}
  def review_counts do
    %{
      needs_review: count_state(:needs_review),
      partial: count_state(:partial)
    }
  end

  defp count_state(state) do
    Order |> where([o], o.state == ^state) |> select([o], count(o.id)) |> Repo.one()
  end

  defp counts_by(schema, field) do
    schema
    |> group_by([r], field(r, ^field))
    |> select([r], {field(r, ^field), count(r.id)})
    |> Repo.all()
    |> Map.new()
  end
end
