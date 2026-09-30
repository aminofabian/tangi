defmodule ViewNinjas.Repo.Migrations.AddOrderFulfilmentColumns do
  use Ecto.Migration

  # What the supplier reports back after placement (scope.md §6, §10; M8).
  # Additive: the M7 columns stay as they are.
  def change do
    alter table(:orders) do
      # The supplier's own words for the order's state, kept raw for admin.
      add :supplier_status, :string
      # The panel's numbers, so margin is real rather than estimated.
      add :start_count, :integer
      add :remains, :integer
      # The supplier's real USD charge, in micros. Null until the first status.
      add :charge_usd_micros, :integer
      # Mostly "USD"; a panel billing otherwise is stopped and surfaced (§10).
      add :currency, :string, default: "USD"
    end

    # The status batch scans non-terminal orders grouped by supplier (§10).
    create index(:orders, [:supplier_id, :state],
             where: "state NOT IN ('completed', 'refunded', 'canceled', 'abandoned', 'failed')",
             name: :orders_open_by_supplier_index
           )

    # A status response names the supplier's order id; this is how we find our row.
    create index(:orders, [:supplier_id, :supplier_order_id],
             where: "supplier_order_id IS NOT NULL",
             name: :orders_supplier_order_index
           )
  end
end
