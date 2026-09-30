defmodule ViewNinjas.Insight.AnalyticsDaily do
  @moduledoc """
  One day's rollup (scope.md §6, §11): derived and rebuildable, never the source
  of truth. The charts read these rows so the phone does not sum the raw tables.

  A day is upserted by `ViewNinjas.Insight.rollup_day/1`; re-running it for a past
  day simply rewrites the numbers from the raw rows.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "analytics_daily" do
    field :day, :date
    field :visits, :integer, default: 0
    field :uniques, :integer, default: 0
    field :signups, :integer, default: 0
    field :orders, :integer, default: 0
    field :revenue_cents, :integer, default: 0
    field :cost_cents, :integer, default: 0
    field :profit_cents, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  def changeset(day, attrs) do
    day
    |> cast(attrs, [
      :day,
      :visits,
      :uniques,
      :signups,
      :orders,
      :revenue_cents,
      :cost_cents,
      :profit_cents
    ])
    |> validate_required([:day])
    |> unique_constraint(:day)
  end
end
