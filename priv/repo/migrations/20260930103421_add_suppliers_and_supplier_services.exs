defmodule ViewNinjas.Repo.Migrations.AddSuppliersAndSupplierServices do
  use Ecto.Migration

  def change do
    create table(:suppliers) do
      add :slug, :string, null: false
      add :base_url, :string, null: false
      # Cloak ciphertext, never the plaintext key (scope.md §12).
      add :encrypted_api_key, :binary
      add :capabilities, :map, null: false, default: %{}
      add :last_balance_micros, :bigint
      add :last_balance_at, :utc_datetime
      add :active, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:suppliers, [:slug])

    create table(:supplier_services) do
      add :supplier_id, references(:suppliers, on_delete: :delete_all), null: false
      add :external_id, :string, null: false
      add :name, :string
      add :category, :string
      add :type, :string
      # USD per 1,000 units, in micros of a dollar ("0.90" -> 900_000).
      add :rate_micros, :bigint
      add :min, :integer
      add :max, :integer
      add :refill, :boolean, null: false, default: false
      add :cancel, :boolean, null: false, default: false
      add :active, :boolean, null: false, default: true
      add :shortlisted_at, :utc_datetime
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # The sync upserts on it.
    create unique_index(:supplier_services, [:supplier_id, :external_id])
    # The catalog workspace filters on supplier + active, and on the shortlist.
    create index(:supplier_services, [:supplier_id, :active])
    create index(:supplier_services, [:shortlisted_at])
  end
end
