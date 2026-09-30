defmodule ViewNinjas.Repo.Migrations.AddOtpAndSmsTables do
  use Ecto.Migration

  def change do
    # Build-plan.md M2: the phone captured in M1 is null until proven.
    alter table(:users) do
      add :phone_verified_at, :utc_datetime
    end

    create table(:otp_challenges) do
      add :phone, :string, null: false
      add :code_hash, :binary
      add :purpose, :string, null: false, default: "phone_verification"
      add :expires_at, :utc_datetime, null: false
      add :attempts, :integer, null: false, default: 0
      add :consumed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # The abuse lookup: "the recent challenges for this number".
    create index(:otp_challenges, [:phone, :inserted_at])

    create table(:sms_messages) do
      add :to, :string, null: false
      add :template, :string, null: false
      add :provider, :string, null: false
      add :provider_ref, :string
      add :status, :string, null: false, default: "queued"
      add :cost_micros, :integer

      timestamps(type: :utc_datetime)
    end

    # The daily spend cap sums today's rows; delivery callbacks look up by ref.
    create index(:sms_messages, [:inserted_at])
    create index(:sms_messages, [:provider_ref])
  end
end
