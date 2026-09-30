defmodule ViewNinjas.Pricing.SettingsTest do
  @moduledoc """
  The append-only money knobs and the FX series (build-plan.md M5, scope.md §6–7).
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.AccountsFixtures
  import ViewNinjas.PricingFixtures
  import ViewNinjas.SuppliersFixtures

  alias ViewNinjas.Catalog
  alias ViewNinjas.Pricing
  alias ViewNinjas.Pricing.Params
  alias ViewNinjas.Suppliers

  describe "the defaults" do
    test "with nothing recorded, the pricer uses the §7 defaults" do
      assert Pricing.current() == Params.defaults()
      assert Pricing.current_settings() == nil
      assert Pricing.current_fx() == nil

      assert Pricing.margin_bps() == 13_000
      assert Pricing.buffer_bps() == 300
      assert Pricing.fx_ppm() == 129_400_000
    end

    test "the §7 worked example holds from the defaults" do
      assert Pricing.retail_kes_cents(900_000, 1000, Pricing.current()) == 27_600
    end
  end

  describe "append_settings/2" do
    test "records a version with its actor and reason" do
      actor = super_admin_fixture()

      assert {:ok, version} =
               Pricing.append_settings(
                 %{margin_bps: 15_000, buffer_bps: 500, reason: "costs rose"},
                 actor
               )

      assert version.margin_bps == 15_000
      assert version.buffer_bps == 500
      assert version.actor_id == actor.id
      assert version.reason == "costs rose"
      assert version.effective_at
    end

    test "is append-only: a change is a new row, never an edit" do
      first = settings_fixture(%{margin_bps: 13_000}, nil)
      second = settings_fixture(%{margin_bps: 20_000}, nil)

      versions = Pricing.list_settings()

      assert Enum.map(versions, & &1.id) == [second.id, first.id]
      # The older version is untouched.
      assert Pricing.get_settings!(first.id).margin_bps == 13_000
      assert Pricing.current_settings().id == second.id
      assert Pricing.margin_bps() == 20_000
    end

    test "rejects a negative margin and a zero FX override" do
      assert {:error, margin} = Pricing.append_settings(%{margin_bps: -1, buffer_bps: 300}, nil)
      assert margin.errors[:margin_bps]

      assert {:error, fx} =
               Pricing.append_settings(
                 %{margin_bps: 13_000, buffer_bps: 300, fx_override_ppm: 0},
                 nil
               )

      assert fx.errors[:fx_override_ppm]
    end

    test "broadcasts a change so listeners can re-quote" do
      Pricing.subscribe()
      settings_fixture()
      assert_receive {:pricing, :changed}
    end
  end

  describe "the FX series" do
    test "record_fx_rate/2 appends and the newest wins" do
      first = fx_rate_fixture(%{rate_ppm: 128_000_000, source: "daily"})
      second = fx_rate_fixture(%{rate_ppm: 131_000_000, source: "daily"})

      assert Pricing.current_fx().id == second.id
      assert Pricing.fx_ppm() == 131_000_000
      assert Pricing.get_fx_rate!(first.id).rate_ppm == 128_000_000
    end

    test "a manual override carries its actor" do
      actor = super_admin_fixture()
      rate = fx_rate_fixture(%{rate_ppm: 135_000_000, source: "manual"}, actor)

      assert rate.actor_id == actor.id
      assert ViewNinjas.Pricing.FxRate.label(rate.source) == "manual override"
    end

    test "a settings override wins over the recorded series" do
      fx_rate_fixture(%{rate_ppm: 128_000_000})
      settings_fixture(%{margin_bps: 13_000, buffer_bps: 300, fx_override_ppm: 140_000_000})

      assert Pricing.fx_ppm() == 140_000_000
    end

    test "an unreadable rate is rejected" do
      assert {:error, changeset} = Pricing.record_fx_rate(%{rate_ppm: 0, source: "daily"}, nil)
      assert changeset.errors[:rate_ppm]

      assert {:error, changeset} = Pricing.record_fx_rate(%{rate_ppm: 1, source: "guess"}, nil)
      assert changeset.errors[:source]
    end
  end

  describe "a change re-quotes the catalog" do
    test "the §7 golden example holds from a recorded version and rate" do
      settings_fixture(%{margin_bps: 13_000, buffer_bps: 300})
      fx_rate_fixture(%{rate_ppm: 129_400_000, source: "fixture"})

      assert Pricing.current().margin_bps == 13_000
      assert Pricing.current().fx_ppm == 129_400_000
      assert Pricing.retail_kes_cents(900_000, 1000, Pricing.current()) == 27_600
    end

    test "raising the margin raises the quote" do
      fx_rate_fixture()
      before = Pricing.retail_kes_cents(900_000, 1000, Pricing.current())

      settings_fixture(%{margin_bps: 20_000, buffer_bps: 300})
      after_ = Pricing.retail_kes_cents(900_000, 1000, Pricing.current())

      assert after_ > before
    end

    test "the SQL ceiling filter agrees with the Elixir pricer under raised knobs" do
      settings_fixture(%{margin_bps: 15_000, buffer_bps: 500})
      fx_rate_fixture(%{rate_ppm: 130_000_000})

      rates = [88_888, 123_456, 900_000, 1_234_567]
      params = Pricing.current()

      supplier = supplier_fixture()

      {:ok, _} =
        Suppliers.ingest_services(
          supplier,
          Enum.map(rates, &service_attrs(%{external_id: to_string(&1), rate_micros: &1}))
        )

      for ceiling <- [3_000, 4_000, 27_600, 40_000, 1_000_000] do
        expected =
          rates
          |> Enum.filter(&(Pricing.retail_kes_cents(&1, 1000, params) <= ceiling))
          |> Enum.sort()

        got =
          Catalog.list_services(%{max_kes_cents: ceiling}, params: params)
          |> Enum.map(& &1.rate_micros)
          |> Enum.sort()

        assert got == expected, "ceiling #{ceiling} disagreed"
      end
    end
  end
end
