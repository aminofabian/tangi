defmodule ViewNinjas.Settings.Setting do
  @moduledoc """
  One operational setting, set by a super-admin (scope.md §7, §11).

  The value is encrypted at rest with the Vault, so a row is never a place a
  secret leaks from; `secret` decides only whether the back office masks it.
  `updated_by` records who last changed it, so there is no silent edit.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Encrypted.Binary, as: EncryptedBinary

  @type t :: %__MODULE__{}

  schema "app_settings" do
    field :key, :string
    field :value, EncryptedBinary, source: :encrypted_value, redact: true
    field :secret, :boolean, default: false

    belongs_to :updated_by, User

    timestamps(type: :utc_datetime)
  end

  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:key, :value, :secret, :updated_by_id])
    |> validate_required([:key, :value])
    |> unique_constraint(:key)
  end
end
