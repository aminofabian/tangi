defmodule ViewNinjas.CatalogTest do
  @moduledoc """
  Offers, lanes, and the curation workspace (build-plan.md M4, scope.md §9).
  """

  use ViewNinjas.DataCase, async: true

  import ViewNinjas.CatalogFixtures
  import ViewNinjas.SuppliersFixtures

  alias ViewNinjas.Catalog
  alias ViewNinjas.Catalog.{Grade, Lane, Suggestions}
  alias ViewNinjas.Pricing
  alias ViewNinjas.Pricing.Params
  alias ViewNinjas.Suppliers

  describe "offers" do
    test "create_offer/1 builds an unpublished offer" do
      assert {:ok, offer} =
               Catalog.create_offer(%{
                 platform: "instagram",
                 outcome: "followers",
                 title: "Instagram followers"
               })

      refute offer.published
      assert offer.title == "Instagram followers"
    end

    test "create_offer/1 rejects a duplicate (platform, outcome, target)" do
      attrs = %{platform: "instagram", outcome: "followers", title: "One"}
      assert {:ok, _} = Catalog.create_offer(attrs)

      assert {:error, changeset} = Catalog.create_offer(%{attrs | title: "Two"})
      assert {"has already been taken", _} = changeset.errors[:platform]
    end

    test "a target is what lets two Facebook likes offers both exist" do
      page = %{
        platform: "facebook",
        outcome: "likes",
        target: "page",
        title: "Facebook page likes"
      }

      post = %{
        platform: "facebook",
        outcome: "likes",
        target: "post",
        title: "Facebook post likes"
      }

      # The collision that made this necessary: same platform, same outcome.
      assert {:ok, page_offer} = Catalog.create_offer(page)
      assert {:ok, post_offer} = Catalog.create_offer(post)
      assert page_offer.id != post_offer.id
      assert page_offer.target == "page"
      assert post_offer.target == "post"

      # The same target twice is still a duplicate.
      assert {:error, _} = Catalog.create_offer(%{page | title: "Again"})
    end

    test "create_offer/1 refuses a target nobody knows" do
      assert {:error, changeset} =
               Catalog.create_offer(%{
                 platform: "facebook",
                 outcome: "likes",
                 target: "banana",
                 title: "x"
               })

      assert {"is not a known target", _} = changeset.errors[:target]
    end

    test "an offer with no target keeps the old two-part uniqueness" do
      assert {:ok, _} =
               Catalog.create_offer(%{
                 platform: "youtube",
                 outcome: "views",
                 title: "One"
               })

      assert {:error, _} =
               Catalog.create_offer(%{
                 platform: "youtube",
                 outcome: "views",
                 target: "",
                 title: "Two"
               })
    end

    test "create_offer/1 demands a lowercase platform and outcome" do
      assert {:error, changeset} =
               Catalog.create_offer(%{platform: "Instagram", outcome: "Followers", title: "x"})

      assert changeset.errors[:platform]
      assert changeset.errors[:outcome]
    end

    test "get_offer!/1 preloads lanes with their pinned service and panel" do
      lane = lane_fixture()

      offer = Catalog.get_offer!(lane.offer_id)

      assert [%Lane{id: id, supplier_service: %{supplier: %{slug: _}}}] = offer.lanes
      assert id == lane.id
    end

    test "publishing an offer is visible in list_offers/1" do
      offer = offer_fixture()
      assert Catalog.list_offers(published: true) == []

      {:ok, _} = Catalog.publish_offer(offer)

      assert [%{id: id}] = Catalog.list_offers(published: true)
      assert id == offer.id
    end
  end

  describe "pin_lane/1" do
    test "pins a service as a grade" do
      offer = offer_fixture()
      service = service_fixture()

      assert {:ok, lane} =
               Catalog.pin_lane(%{
                 offer_id: offer.id,
                 grade: :cheap,
                 supplier_service_id: service.id
               })

      assert lane.grade == :cheap
      refute lane.published
    end

    test "re-pinning a grade updates the same lane rather than adding one" do
      offer = offer_fixture()
      first = service_fixture()
      second = service_fixture()

      {:ok, lane} =
        Catalog.pin_lane(%{offer_id: offer.id, grade: :moderate, supplier_service_id: first.id})

      {:ok, repinned} =
        Catalog.pin_lane(%{offer_id: offer.id, grade: :moderate, supplier_service_id: second.id})

      assert repinned.id == lane.id
      assert repinned.supplier_service_id == second.id
      assert Repo.aggregate(Lane, :count) == 1
    end

    test "re-pinning clears the stale flag — an admin has looked" do
      lane = lane_fixture()
      service = lane.supplier_service

      assert Catalog.flag_stale_lanes(service.supplier_id, [service.external_id]) == 1

      stale = Catalog.get_lane!(lane.id)
      assert Lane.stale?(stale)

      {:ok, _} =
        Catalog.pin_lane(%{
          offer_id: stale.offer_id,
          grade: stale.grade,
          supplier_service_id: stale.supplier_service_id
        })

      refute Lane.stale?(Catalog.get_lane!(lane.id))
    end

    test "the three grades are all pinnable on one offer" do
      offer = offer_fixture()

      for grade <- Grade.all() do
        {:ok, _} =
          Catalog.pin_lane(%{
            offer_id: offer.id,
            grade: grade,
            supplier_service_id: service_fixture().id
          })
      end

      assert Catalog.get_offer!(offer.id).lanes |> Enum.map(& &1.grade) == Grade.all()
    end
  end

  describe "publish / unpublish / unpin" do
    test "a lane publishes and unpublishes without touching its offer" do
      lane = lane_fixture()

      {:ok, published} = Catalog.publish_lane(lane)
      assert published.published

      {:ok, unpublished} = Catalog.unpublish_lane(published)
      refute unpublished.published
    end

    test "unpin_lane/1 removes the lane" do
      lane = lane_fixture()

      assert {:ok, _} = Catalog.unpin_lane(lane)
      assert Catalog.get_lane(lane.id) == nil
    end
  end

  defp published_lane(service, grade) do
    lane = lane_fixture(%{service: service, grade: grade})
    {:ok, published} = Catalog.publish_lane(lane)
    published
  end

  describe "flag_stale_lanes/2" do
    test "flags only the lanes pinned to the changed rows" do
      supplier = supplier_fixture()
      moved = service_fixture(%{supplier: supplier, external_id: "111"})
      still = service_fixture(%{supplier: supplier, external_id: "222"})

      moved_lane = lane_fixture(%{service: moved, grade: :cheap})
      still_lane = lane_fixture(%{service: still, grade: :moderate})

      assert Catalog.flag_stale_lanes(supplier.id, ["111"]) == 1

      assert Lane.stale?(Catalog.get_lane!(moved_lane.id))
      refute Lane.stale?(Catalog.get_lane!(still_lane.id))
    end

    test "an empty change list flags nothing" do
      lane_fixture()
      assert Catalog.flag_stale_lanes(1, []) == 0
    end

    test "another panel's lanes are left alone" do
      mine = lane_fixture()
      other = supplier_fixture()
      service_fixture(%{supplier: other, external_id: "111"})

      assert Catalog.flag_stale_lanes(other.id, ["111"]) == 0
      refute Lane.stale?(Catalog.get_lane!(mine.id))
    end
  end

  describe "unpublish_stale_lanes/2" do
    test "takes the published lanes pinned to a changed row off sale" do
      supplier = supplier_fixture()
      moved = service_fixture(%{supplier: supplier, external_id: "111"})
      still = service_fixture(%{supplier: supplier, external_id: "222"})

      moved_lane = published_lane(moved, :cheap)
      still_lane = published_lane(still, :moderate)

      assert Catalog.unpublish_stale_lanes(supplier.id, ["111"]) == 1

      refute Catalog.get_lane!(moved_lane.id).published
      assert Catalog.get_lane!(still_lane.id).published
    end

    test "an empty change list unpublishes nothing" do
      lane_fixture()
      assert Catalog.unpublish_stale_lanes(1, []) == 0
    end
  end

  describe "a paused panel's lane" do
    test "is visible but not on sale" do
      offer = published_offer_fixture()
      lane = List.first(offer.lanes)
      assert Lane.on_sale?(lane)

      {:ok, _} = Suppliers.pause(lane.supplier_service.supplier, "under the float")

      reloaded = Catalog.get_offer!(offer.id).lanes |> Enum.find(&(&1.id == lane.id))
      assert Lane.paused?(reloaded)
      refute Lane.on_sale?(reloaded)
    end
  end

  describe "the workspace — list_services/2 and count_services/1" do
    test "filters by panel, category, search, refill, cancel and shortlist" do
      secsers = supplier_fixture(%{slug: "secsers"})
      jap = supplier_fixture(%{slug: "jap"})

      a =
        service_fixture(%{
          supplier: secsers,
          name: "IG followers - refill",
          category: "Instagram",
          refill: true,
          cancel: true
        })

      _b =
        service_fixture(%{
          supplier: jap,
          name: "TikTok likes",
          category: "TikTok",
          refill: false,
          cancel: false,
          external_id: "777"
        })

      assert ids(Catalog.list_services(%{supplier: "secsers"})) == [a.id]
      assert ids(Catalog.list_services(%{category: "Instagram"})) == [a.id]
      assert ids(Catalog.list_services(%{q: "refill"})) == [a.id]
      assert ids(Catalog.list_services(%{refill: true})) == [a.id]
      assert ids(Catalog.list_services(%{cancel: true})) == [a.id]

      {:ok, _} = Catalog.toggle_shortlist(a)
      assert ids(Catalog.list_services(%{shortlisted: true})) == [a.id]
      assert Catalog.count_services(%{shortlisted: true}) == 1
      assert Catalog.count_services(%{}) == 2
    end

    test "bounds filters to rows that can sell the quote quantity" do
      sells = service_fixture(%{min: 100, max: 10_000})
      big = service_fixture(%{min: 5_000, max: 50_000, external_id: "5000"})

      assert ids(Catalog.list_services(%{bounds: true})) == [sells.id]
      assert Catalog.count_services(%{}) == 2
      assert Catalog.count_services(%{bounds: true}) == 1
      assert big.min == 5_000
    end

    test "sorts by cost, name, panel and recency" do
      cheap = service_fixture(%{name: "Zeta", rate_micros: 100_000})
      dear = service_fixture(%{name: "Alpha", rate_micros: 900_000, external_id: "999"})

      assert ids(Catalog.list_services(%{sort: :cost})) == [cheap.id, dear.id]
      assert ids(Catalog.list_services(%{sort: :cost_desc})) == [dear.id, cheap.id]
      assert ids(Catalog.list_services(%{sort: :name})) == [dear.id, cheap.id]
    end

    test "the computed KES ceiling agrees with the Elixir pricer, to the cent" do
      rates = [88_888, 123_456, 900_000, 1_234_567, 4_999_999]

      supplier = supplier_fixture()

      {:ok, _} =
        Suppliers.ingest_services(
          supplier,
          Enum.map(rates, &service_attrs(%{external_id: to_string(&1), rate_micros: &1}))
        )

      for ceiling <- [2_700, 2_800, 3_800, 27_600, 37_800, 153_300, 1_000_000] do
        expected =
          rates
          |> Enum.filter(&(Pricing.retail_kes_cents(&1) <= ceiling))
          |> Enum.sort()

        got =
          Catalog.list_services(%{max_kes_cents: ceiling})
          |> Enum.map(& &1.rate_micros)
          |> Enum.sort()

        assert got == expected, "ceiling #{ceiling} disagreed"
      end
    end

    test "list_categories/0 returns the distinct categories" do
      service_fixture(%{category: "Instagram"})
      service_fixture(%{category: "Instagram"})
      service_fixture(%{category: "TikTok"})

      assert Catalog.list_categories() == ["Instagram", "TikTok"]
    end
  end

  describe "suggestions" do
    test "offers cheapest refillable, cheapest, and the closest name" do
      _cheap_plain = service_fixture(%{external_id: "1", rate_micros: 100_000, refill: false})
      cheap_refill = service_fixture(%{external_id: "2", rate_micros: 200_000, refill: true})

      _named =
        service_fixture(%{
          external_id: "3",
          name: "Instagram followers premium",
          rate_micros: 800_000
        })

      subject =
        service_fixture(%{external_id: "9", name: "Instagram followers", rate_micros: 500_000})

      suggestions = Suggestions.for_service(subject)

      assert {_, %{id: id}} = Enum.find(suggestions, fn {reason, _} -> reason == :cheapest end)
      assert id != subject.id

      assert {:cheapest_refillable, %{id: refill_id}} =
               Enum.find(suggestions, fn {reason, _} -> reason == :cheapest_refillable end)

      assert refill_id == cheap_refill.id
      assert Enum.any?(suggestions, fn {reason, _} -> reason == :name_match end)
      refute Enum.any?(suggestions, fn {_reason, service} -> service.id == subject.id end)
    end

    test "a lone service suggests nothing" do
      service = service_fixture()
      assert Suggestions.for_service(service) == []
    end

    test "labels read as buyer-safe copy" do
      assert Suggestions.label(:cheapest_refillable) == "Cheapest refillable"
      assert Suggestions.label(:cheapest) == "Cheapest of any kind"
      assert Suggestions.label(:name_match) == "Closest name"
    end
  end

  describe "lane pricing" do
    test "a manual price wins over the formula" do
      lane = lane_fixture(%{manual_kes_cents: 99_900})

      assert Lane.retail_kes_cents(lane, Params.defaults()) == 99_900
    end

    test "without a manual price it is the flat-margin quote over the pinned rate" do
      service = service_fixture(%{rate_micros: 900_000})
      lane = lane_fixture(%{service: service})

      assert Lane.retail_kes_cents(lane, Params.defaults()) == Pricing.retail_kes_cents(900_000)
    end

    test "a lane priced at or under landed-plus-buffer is underpriced" do
      service = service_fixture(%{rate_micros: 900_000})
      params = Params.defaults()
      floor = Pricing.landed_kes_cents(900_000)

      at_floor = lane_fixture(%{service: service, manual_kes_cents: floor})
      under = lane_fixture(%{service: service, manual_kes_cents: floor - 100, grade: :moderate})
      above = lane_fixture(%{service: service, grade: :quality})

      assert Lane.underpriced?(at_floor, params)
      assert Lane.underpriced?(under, params)
      refute Lane.underpriced?(above, params)
    end
  end

  describe "the publish guardrail" do
    test "a lane at or under landed-plus-buffer cannot be published" do
      service = service_fixture(%{rate_micros: 900_000})
      floor = Pricing.landed_kes_cents(900_000)
      lane = lane_fixture(%{service: service, manual_kes_cents: floor})

      assert {:error, :underpriced} = Catalog.publish_lane(lane)
      refute Catalog.get_lane!(lane.id).published
    end

    test "a well-priced lane publishes" do
      lane = lane_fixture()

      assert {:ok, published} = Catalog.publish_lane(lane)
      assert published.published
    end

    test "a lane with no rate to price from is unpriceable" do
      service = service_fixture(%{rate_micros: nil})
      lane = lane_fixture(%{service: service})

      assert {:error, :unpriceable} = Catalog.publish_lane(lane)
    end

    test "pinning with publish on an underpriced lane saves it unpublished" do
      offer = offer_fixture()
      service = service_fixture(%{rate_micros: 900_000})
      floor = Pricing.landed_kes_cents(900_000)

      assert {:ok, lane} =
               Catalog.pin_lane(%{
                 offer_id: offer.id,
                 grade: :cheap,
                 supplier_service_id: service.id,
                 manual_kes_cents: floor,
                 published: true
               })

      refute lane.published
      refute Catalog.get_lane!(lane.id).published
    end

    test "pinning with publish on a well-priced lane publishes it" do
      offer = offer_fixture()
      service = service_fixture(%{rate_micros: 900_000})

      assert {:ok, lane} =
               Catalog.pin_lane(%{
                 offer_id: offer.id,
                 grade: :cheap,
                 supplier_service_id: service.id,
                 published: true
               })

      assert lane.published
      assert Catalog.get_lane!(lane.id).published
    end
  end

  describe "the market" do
    test "shows only published offers that carry a published lane" do
      shown = published_offer_fixture(%{title: "Shown"})
      _no_lanes = offer_fixture(%{title: "No lanes", published: true})
      _hidden_offer = published_offer_fixture(%{title: "Hidden offer", published: false})

      draft = offer_fixture(%{title: "Unpublished lane", published: true})
      lane_fixture(%{offer: draft})

      assert Catalog.list_market_offers() |> Enum.map(& &1.id) == [shown.id]
    end

    test "carries only the published lanes, cheapest grade first" do
      offer = offer_fixture(%{published: true})
      cheap = service_fixture(%{rate_micros: 900_000, external_id: "1"})
      quality = service_fixture(%{rate_micros: 3_000_000, external_id: "3"})
      draft = service_fixture(%{rate_micros: 100_000, external_id: "2"})

      {:ok, _} =
        Catalog.pin_lane(%{
          offer_id: offer.id,
          grade: :cheap,
          supplier_service_id: cheap.id,
          published: true
        })

      {:ok, _} =
        Catalog.pin_lane(%{
          offer_id: offer.id,
          grade: :quality,
          supplier_service_id: quality.id,
          published: true
        })

      {:ok, _} =
        Catalog.pin_lane(%{
          offer_id: offer.id,
          grade: :moderate,
          supplier_service_id: draft.id
        })

      assert Catalog.get_market_offer(offer.id).lanes |> Enum.map(& &1.grade) == [
               :cheap,
               :quality
             ]
    end

    test "the from-price is the cheapest published lane" do
      offer = offer_fixture(%{published: true})
      cheap = service_fixture(%{rate_micros: 900_000, external_id: "1"})
      dear = service_fixture(%{rate_micros: 3_000_000, external_id: "3"})

      for {grade, service} <- [{:cheap, cheap}, {:quality, dear}] do
        {:ok, _} =
          Catalog.pin_lane(%{
            offer_id: offer.id,
            grade: grade,
            supplier_service_id: service.id,
            published: true
          })
      end

      market = Catalog.get_market_offer(offer.id)

      assert Catalog.from_kes_cents(market, Params.defaults()) ==
               Pricing.retail_kes_cents(900_000)
    end

    test "the platform list is what is actually for sale" do
      published_offer_fixture(%{platform: "instagram", outcome: "followers"})
      published_offer_fixture(%{platform: "tiktok", outcome: "likes"})

      hidden = offer_fixture(%{platform: "youtube", outcome: "views", published: true})
      lane_fixture(%{offer: hidden})

      assert Catalog.list_market_platforms() == ["instagram", "tiktok"]
    end

    test "get_market_offer/1 is nil for an unpublished or laneless offer" do
      hidden = offer_fixture(%{published: false})
      assert Catalog.get_market_offer(hidden.id) == nil

      empty = offer_fixture(%{published: true})
      assert Catalog.get_market_offer(empty.id) == nil

      assert Catalog.get_market_offer(nil) == nil
    end
  end

  defp ids(services), do: Enum.map(services, & &1.id)
end
