defmodule ViewNinjas.Suppliers.Supplier do
  @moduledoc """
  A wholesale panel (scope.md §5, §6).

  The API key is encrypted at rest (`encrypted_api_key`, via Cloak) and never
  logged. Capabilities are data the UI reads — they gate what an admin is
  offered, they do not gate the sync.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Encrypted.Binary, as: EncryptedBinary
  alias ViewNinjas.Suppliers.SupplierService

  @type t :: %__MODULE__{}

  schema "suppliers" do
    # Exposed as `api_key`, stored encrypted in the `encrypted_api_key` column.
    field :api_key, EncryptedBinary, source: :encrypted_api_key, redact: true
    field :slug, :string
    field :base_url, :string
    field :capabilities, :map, default: %{}
    field :last_balance_micros, :integer
    field :last_balance_at, :utc_datetime
    field :active, :boolean, default: false
    # Set when a balance probe finds the panel below its float (scope.md §10).
    field :paused_at, :utc_datetime

    has_many :services, SupplierService

    timestamps(type: :utc_datetime)
  end

  @doc "The capability set a v2 panel is assumed to have."
  def default_capabilities do
    %{
      "services" => true,
      "add" => true,
      "status" => true,
      "balance" => true,
      "refill" => true,
      "refill_status" => true,
      "cancel" => false,
      "multi_status_limit" => 100
    }
  end

  @doc "Whether this panel implements an action, per its capability set."
  def capable?(%__MODULE__{capabilities: capabilities}, action) do
    Map.get(capabilities || %{}, to_string(action), false) == true
  end

  @doc "Whether new placement on this panel is stopped (scope.md §10)."
  @spec paused?(t() | nil) :: boolean()
  def paused?(%__MODULE__{paused_at: nil}), do: false
  def paused?(%__MODULE__{}), do: true
  def paused?(_supplier), do: false

  def changeset(supplier, attrs) do
    supplier
    |> cast(attrs, [
      :slug,
      :base_url,
      :api_key,
      :capabilities,
      :active,
      :last_balance_micros,
      :last_balance_at,
      :paused_at
    ])
    |> validate_required([:slug, :base_url, :api_key])
    |> validate_format(:base_url, ~r{^https://}, message: "must be an https URL")
    |> validate_length(:slug, max: 40)
    |> unique_constraint(:slug)
  end

  def balance_changeset(supplier, attrs) do
    cast(supplier, attrs, [:last_balance_micros, :last_balance_at])
  end
end
