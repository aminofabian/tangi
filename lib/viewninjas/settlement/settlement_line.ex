defmodule ViewNinjas.Settlement.SettlementLine do
  @moduledoc """
  One line of a Malipo settlement statement, landed raw (scope.md §10;
  `docs/malipo-connect.md` §10).

  Append-only, keyed on `(statement_id, provider_ref)` so a re-import of the same
  statement is a no-op. `kind` is the classification the reconciliation reaches —
  `matched`, `amount_mismatch`, `provider_only` or `local_only` — never a
  judgement made here.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @kinds ~w(matched amount_mismatch provider_only local_only)a

  schema "settlement_lines" do
    field :statement_id, :string
    field :provider_ref, :string
    field :receipt, :string
    field :gross_cents, :integer
    field :fee_cents, :integer
    field :net_cents, :integer
    field :settled_on, :date
    field :kind, Ecto.Enum, values: @kinds

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The four buckets a line can land in."
  @spec kinds() :: [atom()]
  def kinds, do: @kinds

  def changeset(line, attrs) do
    line
    |> cast(attrs, [
      :statement_id,
      :provider_ref,
      :receipt,
      :gross_cents,
      :fee_cents,
      :net_cents,
      :settled_on,
      :kind
    ])
    |> validate_required([:statement_id, :provider_ref])
    |> unique_constraint([:statement_id, :provider_ref])
  end
end
