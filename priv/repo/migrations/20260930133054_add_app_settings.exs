defmodule ViewNinjas.Repo.Migrations.AddAppSettings do
  use Ecto.Migration

  # Operational settings the super-admin sets in the back office (scope.md §7,
  # §11): the rail key, the SMS credentials, the FX source and the like. Values
  # are encrypted at rest with the Vault, one row per key, with the person who
  # last changed it — so a settings row is never a place a secret leaks from, and
  # never a silent edit.
  #
  # Bootstrap values stay in the environment: DATABASE_URL, SECRET_KEY_BASE,
  # CLOAK_KEY, PORT and PHX_HOST are needed before the database is reachable, and
  # the key that decrypts this table cannot live inside it.
  def change do
    create table(:app_settings) do
      add :key, :string, null: false
      # Cloak ciphertext, never plaintext (even for non-secrets, for uniformity).
      add :encrypted_value, :binary
      # Whether the value is masked in the back office.
      add :secret, :boolean, null: false, default: false
      add :updated_by_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:app_settings, [:key])
  end
end
