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

  describe "display_kes_cents/3" do
    test "keeps a sub-shilling conversion visible" do
      # 0.0012 USD per 1,000. Nearest shilling is 0; the selling price is 37 cents.
      assert Pricing.retail_kes_cents(1_200) == 0
      assert Pricing.display_kes_cents(1_200) == 37
      assert Pricing.format_selling_cents(37) == "KSh 0.37"
    end

    test "a shilling quote stays a whole-shilling quote" do
      assert Pricing.display_kes_cents(900_000) == Pricing.retail_kes_cents(900_000)
      assert Pricing.format_selling_cents(27_600) == "KSh 276"
    end

    test "a positive margin beats landed even when both round to zero shillings" do
      assert Pricing.beats_landed?(1_200)
    end
  end

  describe "the build-up figures" do
    test "the landed cost is shown with the same rule as the selling price" do
      # 0.90 USD per 1,000: landed is KSh 120, the selling price KSh 276.
      assert Pricing.landed_display_cents(900_000) == 12_000
      assert Pricing.format_selling_cents(Pricing.landed_display_cents(900_000)) == "KSh 120"
      assert Pricing.display_kes_cents(900_000) == 27_600
    end

    test "a sub-shilling landed cost stays visible in cents" do
      assert Pricing.landed_display_cents(1_200) == 16
      assert Pricing.format_selling_cents(16) == "KSh 0.16"
    end

    test "the FX rate and the basis points print the way a build-up shows them" do
      assert Pricing.format_fx_ppm(129_400_000) == "129.40"
      assert Pricing.format_fx_ppm(nil) == "—"
      assert Pricing.format_bps(13_000) == "130%"
      assert Pricing.format_bps(300) == "3%"
      assert Pricing.format_bps(nil) == "—"
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
