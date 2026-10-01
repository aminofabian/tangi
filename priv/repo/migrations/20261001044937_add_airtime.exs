defmodule ViewNinjas.Repo.Migrations.AddAirtime do
  use Ecto.Migration

  # Airtime (docs/instalipa-airtime.md §5). A second product line with its own
  # table — one row per recipient, one rail transaction each — plus the saved
  # numbers a customer reuses, and the ledger link that makes a debit and its
  # refund refuse to happen twice.
  def change do
    create table(:airtime_orders) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      # Groups the rows of one bulk purchase; a single buy carries one uuid too.
      add :batch_id, :string
      add :phone, :string, null: false
      # Face value in KES cents, a whole number of shillings (scope §3.6).
      add :amount_cents, :integer, null: false
      add :state, :string, null: false, default: "awaiting_payment"
      # Our reference to the rail, echoed on the status. One per row, unique.
      add :reference, :string, null: false
      add :idempotency_key, :string, null: false
      # What the rail said back.
      add :instalipa_id, :string
      add :instalipa_status, :string
      add :discount_cents, :integer
      add :float_cents, :integer
      add :receipt, :string
      add :failure_kind, :string
      add :failure_message, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:airtime_orders, [:reference])
    create unique_index(:airtime_orders, [:idempotency_key])
    create unique_index(:airtime_orders, [:instalipa_id], where: "instalipa_id IS NOT NULL")
    create index(:airtime_orders, [:user_id, :inserted_at])
    # The sweep looks for sends still in flight.
    create index(:airtime_orders, [:state, :inserted_at])
    create index(:airtime_orders, [:batch_id])

    create table(:airtime_events) do
      add :airtime_order_id, references(:airtime_orders, on_delete: :delete_all), null: false
      add :from_state, :string
      add :to_state, :string, null: false
      add :reason, :string
      add :actor_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:airtime_events, [:airtime_order_id, :inserted_at])

    create table(:saved_recipients) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :phone, :string, null: false
      # What the customer calls it: "Mum", "Wanjiku". Optional.
      add :label, :string
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # A number is saved once per customer, so picking it twice never duplicates.
    create unique_index(:saved_recipients, [:user_id, :phone])

    alter table(:ledger_entries) do
      add :airtime_order_id, references(:airtime_orders, on_delete: :nilify_all)
    end

    # One airtime order can be debited and refunded at most once, each, so a
    # replayed job cannot double-charge or double-credit (scope §7).
    create unique_index(:ledger_entries, [:airtime_order_id, :reason],
             where: "airtime_order_id IS NOT NULL",
             name: :ledger_entries_airtime_reason_index
           )
  end
end
