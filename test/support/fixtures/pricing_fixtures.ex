defmodule ViewNinjas.PricingFixtures do
  @moduledoc """
  Test helpers for the money knobs and the FX series (build-plan.md M5).
  """

  alias ViewNinjas.Pricing

  @doc "Appends a settings version; defaults to the §7 knobs."
  def settings_fixture(attrs \\ %{}, actor \\ nil) do
    attrs = Enum.into(attrs, %{margin_bps: 13_000, buffer_bps: 300})
    {:ok, settings} = Pricing.append_settings(attrs, actor)
    settings
  end

  @doc "Records an FX rate; defaults to the §7 rate."
  def fx_rate_fixture(attrs \\ %{}, actor \\ nil) do
    attrs = Enum.into(attrs, %{rate_ppm: 129_400_000, source: "fixture"})
    {:ok, rate} = Pricing.record_fx_rate(attrs, actor)
    rate
  end
end
