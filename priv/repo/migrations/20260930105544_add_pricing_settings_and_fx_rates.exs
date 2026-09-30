defmodule ViewNinjas.Repo.Migrations.AddPricingSettingsAndFxRates do
  use Ecto.Migration

  def change do
    # Append-only versions of the money knobs (scope.md §6, §7): the pricer reads
    # the newest row and nothing is ever edited in place.
    create table(:pricing_settings) do
      # 130% over landed by default; stored in basis points.
      add :margin_bps, :integer, null: false, default: 13_000
      # 3% by default.
      add :buffer_bps, :integer, null: false, default: 300
      # The super-admin FX override, in micros of KES per USD. Null falls back to
      # the newest fx_rates row.
      add :fx_override_ppm, :integer
      add :rounding, :string, null: false, default: "nearest_shilling"
      add :reason, :string
      add :actor_id, references(:users, on_delete: :nilify_all)
      add :effective_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # The pricer reads the newest version by effective_at, then id.
    create index(:pricing_settings, [:effective_at, :id])

    # The USD->KES series: a daily job's rows and a super-admin's manual rows.
    # Append-only; the newest rate wins.
    create table(:fx_rates) do
      add :rate_ppm, :integer, null: false
      add :source, :string, null: false
      add :fetched_at, :utc_datetime, null: false
      # Null for the job; the super-admin who set a manual rate otherwise.
      add :actor_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:fx_rates, [:fetched_at, :id])
  end
end
