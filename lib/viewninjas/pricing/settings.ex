defmodule ViewNinjas.Pricing.Settings do
  @moduledoc """
  One append-only version of the money knobs (scope.md §6, §7).

  The pricer always reads the newest version by `effective_at`; nothing is ever
  edited in place. Every change is audited — who, from, to, when, and why.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ViewNinjas.Accounts.User
  alias ViewNinjas.Pricing.{FxRate, Params}

  @type t :: %__MODULE__{}

  @roundings [:nearest_shilling]

  schema "pricing_settings" do
    belongs_to :actor, User
    field :margin_bps, :integer, default: 13_000
    field :buffer_bps, :integer, default: 300
    field :fx_override_ppm, :integer
    field :rounding, Ecto.Enum, values: @roundings, default: :nearest_shilling
    field :reason, :string
    field :effective_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "The rounding rules the pricer understands."
  @spec roundings() :: [atom()]
  def roundings, do: @roundings

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:margin_bps, :buffer_bps, :fx_override_ppm, :rounding, :reason, :effective_at])
    |> validate_required([:margin_bps, :buffer_bps, :effective_at])
    |> validate_number(:margin_bps, greater_than_or_equal_to: 0)
    |> validate_number(:buffer_bps, greater_than_or_equal_to: 0)
    |> validate_number(:fx_override_ppm, greater_than: 0)
  end

  @doc """
  Projects a settings version and an FX rate onto the pricer's value object.

  Margin, buffer and rounding come from the version; FX is the version's
  override when it set one, otherwise the newest recorded rate, otherwise the
  §7 default. A nil version (nothing recorded yet) yields the defaults.
  """
  @spec to_params(t() | nil, FxRate.t() | nil) :: Params.t()
  def to_params(settings, fx_rate) do
    defaults = Params.defaults()

    %Params{
      margin_bps: pick(settings && settings.margin_bps, defaults.margin_bps),
      buffer_bps: pick(settings && settings.buffer_bps, defaults.buffer_bps),
      fx_ppm:
        pick(settings && settings.fx_override_ppm, fx_rate && fx_rate.rate_ppm) ||
          defaults.fx_ppm,
      rounding: pick(settings && settings.rounding, defaults.rounding)
    }
  end

  defp pick(nil, fallback), do: fallback
  defp pick(value, _fallback), do: value
end
