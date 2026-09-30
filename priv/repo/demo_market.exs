# Demo market data for local design review and manual testing.
#
#     mix run priv/repo/demo_market.exs
#
# Creates one panel, three published offers (each with a cheap / moderate /
# quality lane), and makes sure the seeded customer can actually pay: a verified
# phone and a wallet balance. Idempotent — the panel is matched on slug, a
# service on its external id, an offer on (platform, outcome), a lane on
# (offer, grade) — so running it twice changes nothing.
#
# A real catalog is curated in the back office (§9); this is only ballast for
# looking at the market. Development only.

alias ViewNinjas.{Accounts, Catalog, Repo, Wallet}
alias ViewNinjas.Catalog.{Lane, Offer}
alias ViewNinjas.Suppliers
alias ViewNinjas.Suppliers.{Supplier, SupplierService}

if Mix.env() == :prod do
  IO.puts("demo_market: refusing to run in production")

else
  # ---------------------------------------------------------------- the panel

  supplier =
    case Repo.get_by(Supplier, slug: "demo") do
      nil ->
        {:ok, supplier} =
          Suppliers.create_supplier(%{
            slug: "demo",
            base_url: "https://demo.invalid/api/v2",
            api_key: "demo-key",
            capabilities: Supplier.default_capabilities()
          })

        IO.puts("demo_market: created panel #{supplier.slug}")
        supplier

      supplier ->
        supplier
    end

  # -------------------------------------------------------------- the market
  # platform, outcome, title, then the rate for each grade in USD micros/1,000.
  # `platform` is the schema's lowercase slug (the market prints a label for it),
  # so it stays "instagram" here even though the title reads "Instagram".

  market = [
    {"instagram", "followers", "Instagram followers",
     %{cheap: 550_000, moderate: 900_000, quality: 1_400_000}},
    {"tiktok", "likes", "TikTok likes",
     %{cheap: 210_000, moderate: 410_000, quality: 690_000}},
    {"youtube", "views", "YouTube views",
     %{cheap: 780_000, moderate: 1_250_000, quality: 2_100_000}}
  ]

  # A cheap lane has a high floor (bulk), a quality lane a low one — the shape
  # these panels actually sell.
  tiers = %{cheap: {"Budget", 5_000, 250_000}, moderate: {"Standard", 1_000, 100_000}, quality: {"Premium", 100, 50_000}}

  for {platform, outcome, title, rates} <- market do
    services =
      for {grade, {tier, min, max}} <- tiers do
        %{
          external_id: "demo-#{platform}-#{outcome}-#{grade}",
          name: "#{title} · #{tier}",
          category: "Social",
          type: "Default",
          rate_micros: Map.fetch!(rates, grade),
          min: min,
          max: max,
          refill: grade != :cheap,
          cancel: grade == :quality
        }
      end

    {:ok, _stats} = Suppliers.ingest_services(supplier, services)

    offer =
      case Repo.get_by(Offer, platform: platform, outcome: outcome) do
        nil ->
          {:ok, offer} =
            Catalog.create_offer(%{
              platform: platform,
              outcome: outcome,
              title: title,
              published: true
            })

          offer

        offer ->
          offer
      end

    for {grade, _tier} <- tiers do
      external_id = "demo-#{platform}-#{outcome}-#{grade}"
      service = Repo.get_by!(SupplierService, supplier_id: supplier.id, external_id: external_id)

      case Repo.get_by(Lane, offer_id: offer.id, grade: grade) do
        nil ->
          {:ok, _lane} =
            Catalog.pin_lane(%{
              offer_id: offer.id,
              grade: grade,
              supplier_service_id: service.id,
              published: true
            })

          IO.puts("demo_market: #{title} · #{grade}")

        _lane ->
          :ok
      end
    end
  end

  # ------------------------------------------------------- a customer who can pay

  case Accounts.get_user_by_email("customer@example.com") do
    nil ->
      IO.puts("demo_market: no customer@example.com — run `mix ecto.setup` first")

    user ->
      if is_nil(user.phone_verified_at) do
        user
        |> Ecto.Changeset.change(phone_verified_at: DateTime.utc_now(:second))
        |> Repo.update!()

        IO.puts("demo_market: verified #{user.phone}")
      end

      if Wallet.balance(user) == 0 do
        {:ok, _entry} = Wallet.record(%{user_id: user.id, amount_cents: 250_000, reason: :topup})
        IO.puts("demo_market: topped the wallet up to KES 2,500")
      end
  end

  published = Lane |> Repo.all() |> Enum.count(& &1.published)
  IO.puts("demo_market: #{published} published lanes on the market")
end
