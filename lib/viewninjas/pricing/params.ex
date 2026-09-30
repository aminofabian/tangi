defmodule ViewNinjas.Pricing.Params do
  @moduledoc """
  The four numbers a quote depends on (scope.md §7): the margin and buffer in
  basis points, the FX rate in micros of KES per USD, and the rounding rule.

  A plain value object, so a quote can be reproduced from a snapshot. `Pricing`
  turns the current settings and FX into one of these, and the arithmetic takes
  it as an argument rather than reaching for the database on every call.
  """

  @typedoc "Micros of KES per USD, e.g. 129.40 -> 129_400_000."
  @type fx_ppm :: integer()

  @typedoc "The rounding rules the pricer understands. Only one, for now."
  @type rounding :: :nearest_shilling

  @type t :: %__MODULE__{
          margin_bps: integer(),
          buffer_bps: integer(),
          fx_ppm: fx_ppm(),
          rounding: rounding()
        }

  defstruct margin_bps: 13_000,
            buffer_bps: 300,
            fx_ppm: 129_400_000,
            rounding: :nearest_shilling

  @doc "The §7 defaults, used when no settings version or FX rate has been recorded."
  @spec defaults() :: t()
  def defaults, do: %__MODULE__{}
end
