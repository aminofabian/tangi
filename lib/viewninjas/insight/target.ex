defmodule ViewNinjas.Insight.Target do
  @moduledoc """
  A goal for a metric and a period (scope.md §6, §11).

  Append-only, like the money knobs: a change is a new `effective_at` row, never
  an edit, so the target a past week was judged against stays knowable.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User

  @type t :: %__MODULE__{}

  @metrics ~w(revenue orders new_customers margin)a
  @periods ~w(day week month)a

  schema "targets" do
    belongs_to :setter, User, foreign_key: :set_by

    field :metric, Ecto.Enum, values: @metrics
    field :period, Ecto.Enum, values: @periods
    # The goal. Revenue is in KES cents, margin in basis points, the rest a count.
    field :value_cents, :integer
    field :effective_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "The metrics a target can be set for."
  @spec metrics() :: [atom()]
  def metrics, do: @metrics

  @doc "The periods a target can be set for."
  @spec periods() :: [atom()]
  def periods, do: @periods

  @doc "What a metric's value means, for the form and the screen."
  @spec unit(atom() | String.t()) :: :cents | :count | :bps
  def unit(metric) when metric in [:revenue, "revenue"], do: :cents
  def unit(metric) when metric in [:margin, "margin"], do: :bps
  def unit(_metric), do: :count

  def changeset(target, attrs) do
    target
    |> cast(attrs, [:metric, :period, :value_cents, :effective_at, :set_by])
    |> validate_required([:metric, :period, :value_cents, :effective_at])
    |> validate_number(:value_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:set_by)
  end
end
