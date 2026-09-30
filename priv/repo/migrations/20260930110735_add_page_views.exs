defmodule ViewNinjas.Repo.Migrations.AddPageViews do
  use Ecto.Migration

  # First-party page views (scope.md §6, §13; build-plan.md M6): append-only,
  # PII-free — a daily-rotating visitor hash instead of an IP or a cookie, no
  # third-party scripts. Written from M6 even though nothing reads it until M10,
  # so the traffic panel has history instead of starting empty.
  def change do
    create table(:page_views) do
      add :at, :utc_datetime, null: false
      add :path, :string, null: false
      add :referrer, :string
      add :utm_source, :string
      add :utm_medium, :string
      add :utm_campaign, :string
      # Rotates daily, so it cannot follow a person from one day to the next.
      add :visitor_hash, :string
      add :device_class, :string
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # The traffic panel reads by day; append-only, so no other index is needed.
    create index(:page_views, [:at])
    create index(:page_views, [:path, :at])
  end
end
