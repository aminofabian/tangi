defmodule ViewNinjas.Repo.Migrations.AddInsightTablesAndPaymentFees do
  use Ecto.Migration

  # Insight (scope.md §6, §10, §11; build-plan.md M10): the P&L's inputs, the
  # goals, the settlement reconciliation, and a rebuildable daily rollup over the
  # `page_views` that have been accruing since M6.
  def change do
    # What the money cost to collect. Null until a settlement statement names it —
    # never assumed from a rate (scope.md §10).
    alter table(:payments) do
      add :fee_cents, :integer
    end

    # Fixed and one-off costs that belong to no customer. SMS and the payment fee
    # live on their own rows and are derived, not re-entered here.
    create table(:costs) do
      add :kind, :string, null: false
      add :amount_cents, :integer, null: false
      add :incurred_on, :date, null: false
      add :note, :string
      add :actor_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:costs, [:incurred_on])

    # A goal for a metric and period. Append-only, like the money knobs: a change
    # is a new effective row, never an edit.
    create table(:targets) do
      add :metric, :string, null: false
      add :period, :string, null: false
      # The goal. A count metric (orders, customers) stores the count here too.
      add :value_cents, :integer, null: false
      add :set_by, references(:users, on_delete: :nilify_all)
      add :effective_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:targets, [:metric, :period, :effective_at])

    # One line of a settlement statement, landed raw. Append-only; a re-import of
    # the same statement is a no-op, keyed on (statement_id, provider_ref).
    create table(:settlement_lines) do
      add :statement_id, :string, null: false
      # The Malipo id, or the M-Pesa receipt, as the statement gives them.
      add :provider_ref, :string, null: false
      add :receipt, :string
      add :gross_cents, :integer
      add :fee_cents, :integer
      add :net_cents, :integer
      add :settled_on, :date
      # matched | amount_mismatch | provider_only | local_only
      add :kind, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:settlement_lines, [:statement_id, :provider_ref])
    create index(:settlement_lines, [:kind])

    # The daily rollup: derived, rebuildable, never the source of truth. One row
    # per day, so the charts are cheap on a phone (scope.md §11).
    create table(:analytics_daily) do
      add :day, :date, null: false
      add :visits, :integer, null: false, default: 0
      add :uniques, :integer, null: false, default: 0
      add :signups, :integer, null: false, default: 0
      add :orders, :integer, null: false, default: 0
      add :revenue_cents, :integer, null: false, default: 0
      add :cost_cents, :integer, null: false, default: 0
      add :profit_cents, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:analytics_daily, [:day])
  end
end
