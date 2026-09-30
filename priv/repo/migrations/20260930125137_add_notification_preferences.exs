defmodule ViewNinjas.Repo.Migrations.AddNotificationPreferences do
  use Ecto.Migration

  # Notification preferences (scope.md §6, §11; build-plan.md M11): one row per
  # channel a customer can be reached on, and the quiet hours they do not want it
  # used in. Transactional SMS reuses `sms_messages`; nothing else is new.
  def change do
    create table(:notification_preferences) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # sms | email
      add :channel, :string, null: false
      add :opted_in, :boolean, null: false, default: true
      # "21:00-07:00" in local (Africa/Nairobi) time; null means any hour.
      add :quiet_hours, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:notification_preferences, [:user_id, :channel])
  end
end
