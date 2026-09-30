defmodule ViewNinjas.PricingTest do
  @moduledoc """
  The integer quote engine (scope.md §7). The worked example is the contract;
  everything else guards the arithmetic at the edges.
  """

  use ViewNinjas.DataCase, async: true

  alias ViewNinjas.Pricing
  alias ViewNinjas.Pricing.Params

  doctest ViewNinjas.Pricing

  @defaults %Params{}

  describe "retail_kes_cents/3" do
    test "reproduces the §7 worked example: 0.90 USD/1k at 129.40, 1000 units -> KSh 276" do
      # 0.90 USD per 1,000 is 900_000 micros.
      assert Pricing.retail_kes_cents(900_000) == 27_600
      assert Pricing.format_kes_cents(Pricing.retail_kes_cents(900_000)) == "KSh 276"
    end

    test "scales with quantity by the flat rate" do
      assert Pricing.retail_kes_cents(900_000, 500) == 13_800
      assert Pricing.retail_kes_cents(900_000, 2000) == 55_200
    end

    test "rounds a whole shilling, never a fraction" do
      assert rem(Pricing.retail_kes_cents(900_000), 100) == 0
    end

    test "a higher margin raises the quote" do
      raised = %Params{@defaults | margin_bps: 15_000}

      assert Pricing.retail_kes_cents(900_000, 1000, raised) >
               Pricing.retail_kes_cents(900_000, 1000, @defaults)
    end

    test "a zero rate costs nothing rather than crashing" do
      assert Pricing.retail_kes_cents(0) == 0
    end

    test "a huge rate stays exact integer arithmetic" do
      assert is_integer(Pricing.retail_kes_cents(1_000_000_000_000))
    end

    test "a missing rate is nil, not an error" do
      assert Pricing.retail_kes_cents(nil) == nil
      assert Pricing.retail_kes_cents(nil, 500) == nil
    end
  end

  describe "the pricing ladder" do
    test "landed cost + buffer sits under retail, as the margin requires" do
      rate = 900_000

      landed = Pricing.landed_kes_cents(rate)
      retail = Pricing.retail_kes_cents(rate)

      assert landed == 12_000
      assert retail > landed
    end

    test "each step is the documented multiple of the one before" do
      cost_usd = Pricing.cost_usd_ppm(900_000, 1000)
      cost_kes = Pricing.cost_kes_ppm(cost_usd, @defaults)
      landed = Pricing.landed_ppm(cost_kes, @defaults)

      assert cost_usd == 900_000
      assert cost_kes == 116_460_000
      assert landed == 119_953_800
      assert Pricing.retail_ppm(landed, @defaults) == 275_893_740
    end

    test "landed is nil-safe too" do
      assert Pricing.landed_kes_cents(nil) == nil
    end
  end

  describe "round_to_shilling/1" do
    test "is half up" do
      assert Pricing.round_to_shilling(500_000) == 1
      assert Pricing.round_to_shilling(499_999) == 0
      assert Pricing.round_to_shilling(1_500_000) == 2
    end
  end

  describe "format_kes_cents/1" do
    test "renders KES as whole shillings with thousands separators, never decimals" do
      assert Pricing.format_kes_cents(125_000) == "KSh 1,250"
      assert Pricing.format_kes_cents(100_200_000) == "KSh 1,002,000"
      assert Pricing.format_kes_cents(27_600) == "KSh 276"
    end

    test "is nil-safe" do
      assert Pricing.format_kes_cents(nil) == nil
    end
  end
end
