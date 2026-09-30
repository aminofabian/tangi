defmodule ViewNinjas.Repo.Migrations.AddOffersAndLanes do
  use Ecto.Migration

  def change do
    create table(:offers) do
      add :platform, :string, null: false
      add :outcome, :string, null: false
      add :title, :string, null: false
      add :description, :string
      add :sort, :integer, null: false, default: 0
      add :published, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:offers, [:published, :sort])
    create unique_index(:offers, [:platform, :outcome])

    create table(:lanes) do
      add :offer_id, references(:offers, on_delete: :delete_all), null: false
      add :grade, :string, null: false
      add :supplier_service_id, references(:supplier_services, on_delete: :restrict), null: false
      # The escape hatch (scope.md §7): a hand-set retail price in KES cents.
      add :manual_kes_cents, :integer
      add :published, :boolean, null: false, default: false
      # Set by the sync when the pinned row's price, bounds or active flag
      # changed (scope.md §9), cleared when an admin re-pins.
      add :stale_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:lanes, [:offer_id, :grade])
    create index(:lanes, [:supplier_service_id])
  end
end
