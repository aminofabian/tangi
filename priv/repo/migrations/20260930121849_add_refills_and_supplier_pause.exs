defmodule ViewNinjas.Repo.Migrations.AddRefillsAndSupplierPause do
  use Ecto.Migration

  # After the sale (scope.md §6, §10; build-plan.md M9): refills, the supplier
  # float that pauses a low panel before a customer pays, and the database
  # invariant that an order is refunded at most once.
  def change do
    alter table(:suppliers) do
      # Set when a balance probe finds the panel under its float. A paused panel
      # keeps syncing but takes no new orders.
      add :paused_at, :utc_datetime
    end

    create table(:refills) do
      add :order_id, references(:orders, on_delete: :restrict), null: false
      # The panel's id for the refill, once the one call has answered.
      add :supplier_refill_id, :string
      add :state, :string, null: false, default: "requested"
      # Why it was rejected, or why a person is looking.
      add :reason, :string

      timestamps(type: :utc_datetime)
    end

    # One refill per order: a rejected refill stays rejected and never opens a
    # second (scope.md §10).
    create unique_index(:refills, [:order_id])

    # An order is refunded at most once at the database level, so a repeated
    # partial report can never double-credit the wallet.
    create unique_index(:ledger_entries, [:order_id, :reason],
             where: "order_id IS NOT NULL",
             name: :ledger_entries_order_reason_index
           )
  end
end
