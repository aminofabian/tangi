defmodule ViewNinjas.Repo.Migrations.AddOrdersPaymentsAndLedger do
  use Ecto.Migration

  # The money tables (scope.md §6, §8; build-plan.md M7). `orders` is created
  # fully shaped rather than grown later — a mid-flight change to a table that is
  # already taking money is exactly what the additive rule avoids. `order_events`
  # and `ledger_entries` are append-only; a correction is a new, opposite row.
  def change do
    create table(:orders) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :lane_id, references(:lanes, on_delete: :restrict), null: false
      add :link, :string, null: false
      add :quantity, :integer, null: false
      # The price, frozen at the moment of payment (scope.md §7): a later edit to
      # the knobs never moves what a customer already paid.
      add :retail_cents, :integer, null: false
      add :cost_usd_micros, :integer
      add :margin_bps, :integer, null: false
      add :buffer_bps, :integer, null: false
      add :fx_rate_id, references(:fx_rates, on_delete: :nilify_all)
      # The supplier side is filled in when the order is placed (M8).
      add :supplier_id, references(:suppliers, on_delete: :nilify_all)
      add :supplier_service_id, references(:supplier_services, on_delete: :nilify_all)
      add :supplier_order_id, :string
      add :state, :string, null: false, default: "awaiting_payment"

      timestamps(type: :utc_datetime)
    end

    create index(:orders, [:state])
    create index(:orders, [:user_id, :inserted_at])
    # The status batch groups by supplier over non-terminal orders (M8).
    create index(:orders, [:supplier_id, :state])

    create table(:order_events) do
      add :order_id, references(:orders, on_delete: :delete_all), null: false
      add :from_state, :string
      add :to_state, :string, null: false
      add :reason, :string
      add :actor_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:order_events, [:order_id, :inserted_at])

    create table(:payments) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      # Null for a wallet top-up, which is not tied to an order.
      add :order_id, references(:orders, on_delete: :nilify_all)
      add :purpose, :string, null: false
      add :amount_cents, :integer, null: false
      add :malipo_payment_id, :string
      # One attempt, one key (scope.md §8): re-sending it returns the original
      # payment and never prompts twice.
      add :idempotency_key, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :receipt, :string
      add :failure_kind, :string
      add :failure_message, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:payments, [:malipo_payment_id])
    create unique_index(:payments, [:idempotency_key])
    # The sweep finds pending payments past their window.
    create index(:payments, [:status, :inserted_at])

    create table(:ledger_entries) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      # Signed: negative is a debit. The wallet balance is the sum, never a column.
      add :amount_cents, :integer, null: false
      add :reason, :string, null: false
      add :payment_id, references(:payments, on_delete: :nilify_all)
      add :order_id, references(:orders, on_delete: :nilify_all)
      # Null when the system writes it.
      add :actor_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:ledger_entries, [:user_id, :inserted_at])

    # A payment can credit the ledger at most once: the database itself refuses a
    # double write, so a replayed callback can never double-credit (§8).
    create unique_index(:ledger_entries, [:payment_id, :reason],
             where: "payment_id IS NOT NULL",
             name: :ledger_entries_payment_reason_index
           )
  end
end
