defmodule ViewNinjas.Pricing.FxRate do
  @moduledoc """
  One USD→KES rate on the append-only series (scope.md §6).

  The daily job records a `"daily"` row with no actor; a super-admin correcting
  a bad day records a `"manual"` row with one. A rate is never edited, only
  appended; the newest row wins, unless a settings version pins an override.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User

  @type t :: %__MODULE__{}

  @sources ~w(daily manual fixture)

  schema "fx_rates" do
    belongs_to :actor, User
    field :rate_ppm, :integer
    field :source, :string
    field :fetched_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "The sources a rate can carry."
  @spec sources() :: [String.t()]
  def sources, do: @sources

  @doc "The label shown for a source."
  @spec label(String.t()) :: String.t()
  def label("daily"), do: "daily"
  def label("manual"), do: "manual override"
  def label("fixture"), do: "fixture"
  def label(other), do: to_string(other)

  def changeset(fx_rate, attrs) do
    fx_rate
    |> cast(attrs, [:rate_ppm, :source, :fetched_at])
    |> validate_required([:rate_ppm, :source, :fetched_at])
    |> validate_number(:rate_ppm, greater_than: 0)
    |> validate_inclusion(:source, @sources)
  end
end
