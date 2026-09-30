defmodule ViewNinjas.Blog.Clusters.TopTiktokFollowersProvidersKenya do
  @moduledoc """
  The "top TikTok followers providers in Kenya" cluster: one pillar and five
  spokes.

  As with the YouTube providers cluster, the pillar is a comparison and not a
  disguised landing page: it lays out the objective criteria a buyer should
  check, describes the ten kinds of provider a Kenyan buyer meets, and names
  our own shop, Tangi, as one entry — with the trade-offs stated.
  """

  alias ViewNinjas.Blog.{Cluster, Post}

  @cluster "top-tiktok-followers-providers-kenya"
  @updated ~D[2026-09-30]

  @doc "The cluster's own metadata."
  @spec cluster() :: Cluster.t()
  def cluster do
    %Cluster{
      slug: @cluster,
      eyebrow: "TikTok growth in Kenya",
      title: "Top TikTok Followers Providers in Kenya",
      keyword: "top TikTok followers providers in Kenya",
      description:
        "A comparison of the kinds of TikTok followers provider you can buy from in Kenya — price, delivery, refill, M-Pesa and support — and how to tell a real service from a reseller."
    }
  end

  @doc "Every post in the cluster, pillar first."
  @spec posts() :: [Post.t()]
  def posts do
    [
      pillar(),
      best_sites(),
      price(),
      real_vs_fake(),
      organic_growth(),
      followers_vs_views()
    ]
  end

  # ------------------------------------------------------------------ pillar

  defp pillar do
    %Post{
      slug: "top-tiktok-followers-providers-kenya",
      cluster: @cluster,
      kind: :pillar,
      updated_on: @updated,
      eyebrow: "Provider comparison",
      title: "Top 10 TikTok Followers Providers in Kenya",
      meta_title: "Top 10 TikTok Followers Providers in Kenya (Compared)",
      description:
        "A practical comparison of the kinds of TikTok followers provider in Kenya — price, minimum order, delivery, refill, M-Pesa and support — and how to judge any of them, ours included.",
      keywords: [
        "top TikTok followers providers in Kenya",
        "best TikTok followers providers Kenya",
        "TikTok followers providers Kenya",
        "best site to buy TikTok followers Kenya",
        "buy TikTok followers Kenya",
        "TikTok followers Kenya",
        "TikTok growth services Kenya",
        "TikTok promotion services Kenya",
        "TikTok followers website Kenya"
      ],
      intro: [
        "TikTok grows on followers: the number on your profile is the first thing a new viewer, a brand or a client checks. That is why the market for TikTok followers in Kenya has become crowded — and why the providers in it are so hard to compare fairly.",
        "This page does the comparison honestly: the objective criteria that actually matter, the ten kinds of provider you will meet, what followers cost in shillings, and how to tell a real service from a reseller. Full disclosure — number one on our list is our own shop, Tangi, and it is labelled as such."
      ],
      sections: pillar_sections(),
      faqs: pillar_faqs()
    }
  end

  defp pillar_sections do
    [
      %{
        id: "what-are-providers",
        heading: "What Are TikTok Followers Providers?",
        blocks: [
          {:p,
           "A TikTok followers provider is a business that adds followers to a TikTok profile you choose. Some are large self-service platforms — panels — where you paste your handle, pick a service and pay in dollars. Some are local shops that package the same delivery for a Kenyan audience, priced in shillings and paid by M-Pesa. Others are agencies selling growth, or individuals reselling someone else's service from their phone."},
          {:p,
           "They are not the same product. Two providers quoting very different prices for \"1,000 followers\" are almost always delivering from different sources, at different speeds, with different odds that the followers stay. The comparison below is about those differences, not the numbers on the marketing page."}
        ]
      },
      %{
        id: "how-we-compare",
        heading: "How We Compare TikTok Followers Providers",
        blocks: [
          {:p,
           "We compare providers on ten objective things. None of them is marketing copy, and you can check every one of them before you pay:"},
          {:table,
           %{
             head: ["Criterion", "What to check"],
             rows: [
               [
                 "Price",
                 "Cost per 1,000 followers, stated in shillings if it is a Kenyan provider."
               ],
               ["Minimum order", "Whether you can start at 1,000, or are pushed to 10,000."],
               ["Delivery speed", "Gradual over hours or days, or promised instantly."],
               ["Refill policy", "What happens if followers drop after delivery."],
               ["Payment options", "Card, PayPal, crypto or a local method."],
               ["M-Pesa availability", "Whether you can pay the way most Kenyans do."],
               ["Customer support", "A reachable person, and how quickly they reply."],
               ["Targeting options", "Whether the followers can be aimed at Kenya, or at all."],
               ["Order tracking", "Whether you can watch delivery progress."],
               ["Password", "Whether they ask for your TikTok login — they never should."]
             ]
           }},
          {:callout,
           "One criterion is non-negotiable: a real provider never needs your password. You are buying followers for a public profile, and nobody needs to log in as you to deliver them. Anyone who asks for your TikTok login is not a provider you want."}
        ]
      },
      %{
        id: "top-ten",
        heading: "Top 10 TikTok Followers Providers in Kenya",
        blocks: [
          {:p,
           "These are ranked for one buyer — a Kenyan creator or business on a phone, paying by M-Pesa, who wants followers that stay. They are provider profiles, not named companies we have audited, because we cannot verify another business's delivery or results. The one exception is number one, which is ours."},
          {:h3, "1. Tangi — the local shop (ours)"},
          {:p,
           "Profile: TikTok followers priced in shillings and paid by M-Pesa, delivered gradually, with a refill when delivery falls short and support you can reach locally."},
          {:ul,
           [
             "Best for: a Kenyan creator or brand that wants M-Pesa and someone local to hold to account.",
             "Price: competitive with a global panel once you account for payment and support.",
             "Watch out: it is our own shop, so judge it on the same criteria as everyone else — and we are not the cheapest raw number."
           ]},
          {:h3, "2. Large global self-service panels"},
          {:p,
           "Profile: automated platforms with hundreds of services, priced in dollars and paid by card, PayPal or crypto. Most deliver almost instantly, and support is a ticket queue in another time zone."},
          {:ul,
           [
             "Best for: buyers who already know panels, can pay in dollars and want the lowest price per 1,000.",
             "Price: the cheapest per 1,000 anywhere.",
             "Watch out: follower quality is mixed, instant delivery is the most easily filtered, and there is little you can do if an order goes wrong."
           ]},
          {:h3, "3. Local generalist social-media shops"},
          {:p,
           "Profile: Kenyan shops selling followers, likes, comments and views as bundles, paid by M-Pesa. They rarely state where the followers come from."},
          {:ul,
           [
             "Best for: convenience, when you want several things at once.",
             "Price: low to mid, in shillings.",
             "Watch out: an unstated source, and bundles that often include bot engagement, which carries more risk than followers alone."
           ]},
          {:h3, "4. TikTok-specialist growth agencies"},
          {:p,
           "Profile: agencies that sell a growth plan — content, posting, paid promotion and reporting — rather than a bare follower count."},
          {:ul,
           [
             "Best for: brands that want the account run, not just topped up.",
             "Price: the highest, usually a monthly retainer.",
             "Watch out: you are paying for time and strategy; results depend on the content, and followers are not guaranteed."
           ]},
          {:h3, "5. Freelance resellers on WhatsApp, Instagram and Telegram"},
          {:p,
           "Profile: individuals reselling a panel from their phone, priced in shillings and paid by M-Pesa. The most common provider you will meet, and the least accountable."},
          {:ul,
           [
             "Best for: a quick, cheap order from someone you already know and trust.",
             "Price: cheap.",
             "Watch out: the source is unknown, there is usually no policy, and there is no recourse if the order fails or the followers drop."
           ]},
          {:h3, "6. Panel marketplaces and comparison sites"},
          {:p,
           "Profile: aggregators that list dozens of panels with prices and reviews, then send you to the panel to buy. Still priced in dollars."},
          {:ul,
           [
             "Best for: comparing many panels in one place before you choose.",
             "Price: whatever the underlying panel charges.",
             "Watch out: reviews are often affiliate-driven, and the marketplace is not the provider — it does not deliver or guarantee your order."
           ]},
          {:h3, "7. Influencer and creator collaboration networks"},
          {:p,
           "Profile: they put your profile in front of a network of real creators' audiences, so followers arrive because real people chose to follow."},
          {:ul,
           [
             "Best for: an engaged, relevant following rather than a bare number.",
             "Price: higher per follower, negotiated.",
             "Watch out: it is slow and modest in volume; relevance depends entirely on matching the audience to your niche."
           ]},
          {:h3, "8. TikTok Ads and promotion agencies"},
          {:p,
           "Profile: agencies and freelancers who run TikTok Ads for your videos, billed in shillings or dollars, with real targeting and reporting."},
          {:ul,
           [
             "Best for: measurable outcomes — profile visits, clicks, sales.",
             "Price: the most expensive route, because you pay for the ads and the management.",
             "Watch out: it is the advertising route, not followers as such, and it needs a video that converts to be worth it."
           ]},
          {:h3, "9. Content studios and account-management services"},
          {:p,
           "Profile: studios that film, edit and post for you, growing the account by doing the work rather than buying the number."},
          {:ul,
           [
             "Best for: businesses with no time to make content.",
             "Price: high and ongoing.",
             "Watch out: slower than buying followers, and entirely dependent on the content being good."
           ]},
          {:h3, "10. White-label resellers bundling followers, likes and views"},
          {:p,
           "Profile: sellers offering followers, likes and views as one package, usually near an instant delivery."},
          {:ul,
           [
             "Best for: someone trying to look maximally established in one order.",
             "Price: cheap per item.",
             "Watch out: this is the riskiest bundle there is. Followers, likes and views from the same cheap source are exactly what gets an account's reach limited — treat it as a last option, if at all."
           ]}
        ]
      },
      %{
        id: "cost",
        heading: "How Much Do TikTok Followers Cost in Kenya?",
        blocks: [
          {:p,
           "Followers are priced per 1,000, and the price depends far more on the source than on the quantity. Across the Kenyan market you will see roughly these bands:"},
          {:table,
           %{
             head: ["Package", "Typical price", "Search intent"],
             rows: [
               ["1,000 followers", "KSh 300 – 1,200", "Entry-level"],
               ["5,000 followers", "KSh 1,500 – 6,000", "Small creator"],
               ["10,000 followers", "KSh 3,000 – 12,000", "Growth"],
               ["25,000 followers", "KSh 7,500 – 30,000", "Established account"],
               ["50,000+ followers", "KSh 15,000 – 60,000", "Large campaigns"]
             ]
           }},
          {:p,
           "The range is wide because cheap followers and followers that stay are different products. We break the numbers down, and explain what the price hides, in [how much TikTok followers cost in Kenya](/blog/tiktok-followers-price-kenya)."}
        ]
      },
      %{
        id: "how-to-choose",
        heading: "How to Choose a TikTok Followers Provider",
        blocks: [
          {:ol,
           [
             "Check the price per 1,000 and the minimum order.",
             "Confirm the payment method — and whether M-Pesa is offered.",
             "Ask where the followers come from, and whether they can be targeted to Kenya.",
             "Check the refill policy, in writing.",
             "Confirm delivery is gradual, not instant.",
             "Make sure nobody is asking for your password.",
             "Start with the smallest order and watch how it behaves."
           ]},
          {:p,
           "Our [provider checklist](/blog/how-to-choose-a-tiktok-followers-provider) turns this into the questions to ask any seller."}
        ]
      },
      %{
        id: "real",
        heading: "Are Purchased TikTok Followers Real?",
        blocks: [
          {:p,
           "Honest answer: it depends on the provider. Some services deliver accounts that are genuinely run by people and choose to follow. Others add automated accounts that never engage. Both raise the number; only one behaves like an audience."},
          {:p,
           "The number is not the thing to test — retention and engagement are. Followers that vanish within days, or an account whose engagement ratio collapses as the follower count climbs, tell you which kind you bought. Read [real vs fake TikTok followers](/blog/real-vs-fake-tiktok-followers) for the full test."}
        ]
      },
      %{
        id: "kenyan",
        heading: "Can You Buy Kenyan TikTok Followers?",
        blocks: [
          {:p,
           "Sometimes, but be careful with the promise. Follower services are not as geographically targetable as views, and many providers cannot guarantee followers from a specific country at all. A provider who advertises \"Kenyan followers\" may be describing a broad regional mix rather than a verified audience."},
          {:p,
           "Ask directly whether the followers can be targeted to Kenya, and what happens if they are not. If the answer is vague, assume the followers are untargeted, and judge the order accordingly."}
        ]
      },
      %{
        id: "followers-vs-views",
        heading: "TikTok Followers vs TikTok Views",
        blocks: [
          {:p, "They are measured at different levels, and buying one does not buy the other."},
          {:table,
           %{
             head: ["Metric", "Level", "What it does"],
             rows: [
               ["Followers", "Profile", "Grows the audience that sees your future videos."],
               ["Views", "Video", "Makes a specific video look watched and feeds the algorithm."],
               ["Likes", "Video", "Signals that content is appreciated."],
               ["Comments", "Video", "Creates interaction and discussion."],
               ["Shares", "Video", "Extends distribution to new feeds."]
             ]
           }},
          {:p,
           "Which one to buy depends on your goal — a fuller explanation is in [TikTok followers vs views](/blog/tiktok-followers-vs-views)."}
        ]
      },
      %{
        id: "followers-vs-ads",
        heading: "TikTok Followers vs TikTok Ads",
        blocks: [
          {:p,
           "Buying followers buys a number. TikTok Ads buys distribution — it puts your videos in front of a chosen audience and lets you measure what happened."},
          {:table,
           %{
             head: ["", "Bought followers", "TikTok Ads"],
             rows: [
               [
                 "You pay for",
                 "A set number of followers",
                 "Impressions, clicks or conversions, by auction"
               ],
               ["Control", "Quantity and grade", "Targeting, budget and schedule"],
               ["Reporting", "A number", "Full TikTok Ads reporting"],
               [
                 "Best for",
                 "A fuller-looking profile, fast",
                 "Real reach and measurable outcomes"
               ]
             ]
           }},
          {:p,
           "Most serious accounts use ads for reach and, if they buy at all, a modest follower order for the profile. Ads are the slower, costlier, more durable route."}
        ]
      },
      %{
        id: "tangi",
        heading: "Tangi TikTok Followers",
        blocks: [
          {:p,
           "Tangi is our shop — the one this site runs, and the entry we can vouch for on the list above. If you want TikTok followers in Kenya without a foreign panel or an unaccountable reseller, it is built for exactly that."},
          {:ul,
           [
             "Priced in shillings and paid by M-Pesa, the way most Kenyans pay.",
             "Delivered gradually, not in one unnatural burst.",
             "A refill when delivery falls short, and support you can reach locally.",
             "No password, ever — you never hand over your TikTok login.",
             "A minimum you can afford, so a small account can start."
           ]},
          {:p,
           "What we do not claim: we cannot promise a specific follower count, engagement, or that a TikTok account is completely unaffected. We can tell you where the followers come from and stand behind the delivery — which is the honest version of a guarantee."},
          {:cta,
           %{
             text:
               "Browse the shop to see what is on sale right now, priced in shillings and paid by M-Pesa.",
             href: "/shop",
             label: "Visit the shop"
           }}
        ]
      },
      %{
        id: "next",
        heading: "Where to Go Next",
        toc: false,
        blocks: [
          {:ul,
           [
             "[Best sites to buy TikTok followers in Kenya](/blog/best-sites-to-buy-tiktok-followers-in-kenya)",
             "[How much TikTok followers cost in Kenya](/blog/tiktok-followers-price-kenya)",
             "[Real vs fake TikTok followers](/blog/real-vs-fake-tiktok-followers)",
             "[How to grow your TikTok followers in Kenya](/blog/how-to-grow-tiktok-followers-in-kenya)",
             "[TikTok followers vs TikTok views](/blog/tiktok-followers-vs-views)"
           ]},
          {:p,
           "For the equivalent comparison on the other platform, see our [YouTube views providers in Kenya](/blog/top-youtube-views-providers-kenya)."}
        ]
      }
    ]
  end

  defp pillar_faqs do
    [
      %{
        question: "Which is the best TikTok followers provider in Kenya?",
        answer:
          "It depends what you value most. Ours, Tangi, is built for a Kenyan buyer who wants M-Pesa and local support; a global panel is cheaper if you can pay in dollars; an agency is better if you want the account grown rather than topped up. Judge any of them on source, delivery, refill and support."
      },
      %{
        question: "How much does 1,000 TikTok followers cost in Kenya?",
        answer:
          "Broadly KSh 300 to KSh 1,200 for 1,000 followers, depending on the provider and the quality of the followers. A price far below that is a signal about how the followers are produced."
      },
      %{
        question: "Do I have to give my TikTok password?",
        answer:
          "No. A real provider delivers followers to a public profile and never needs to log in as you. Never give your password, and treat any provider who asks as one to avoid."
      },
      %{
        question: "Can I buy specifically Kenyan TikTok followers?",
        answer:
          "Sometimes, but not reliably — follower services are less geographically targetable than views. Ask directly whether followers can be targeted to Kenya, and treat a vague answer as a no."
      },
      %{
        question: "Will bought followers stay?",
        answer:
          "From a good provider, largely yes; from a cheap one, often not. Check the refill policy, watch the count for a few days after delivery, and prefer providers that deliver gradually rather than instantly."
      }
    ]
  end

  # --------------------------------------------------- spoke: best sites

  defp best_sites do
    %Post{
      slug: "best-sites-to-buy-tiktok-followers-in-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Where to buy",
      title: "Best Sites to Buy TikTok Followers in Kenya",
      meta_title: "Best Sites to Buy TikTok Followers in Kenya",
      description:
        "How to judge the sites selling TikTok followers in Kenya — the checks that separate a good one from a bad one — the kinds of site you will find, and how to order safely.",
      keywords: [
        "best site to buy TikTok followers Kenya",
        "where to buy TikTok followers Kenya",
        "best website for TikTok followers Kenya",
        "TikTok followers website Kenya",
        "buy TikTok followers online Kenya"
      ],
      intro: [
        "\"Best site\" is the wrong question on its own. A site can be the cheapest and still the wrong choice. This page is about how to judge the sites you will find, order safely, and spot the ones to walk away from."
      ],
      sections: [
        %{
          id: "good-provider",
          heading: "What Makes a Good Provider",
          blocks: [
            {:p, "A good site answers the same questions every time:"},
            {:ul,
             [
               "A clear price per 1,000 followers, in shillings.",
               "A minimum order you can afford.",
               "A stated source for the followers.",
               "Gradual delivery, not an instant burst.",
               "A written refill policy.",
               "M-Pesa, if it is a Kenyan site.",
               "Support you can reach.",
               "No request for your password."
             ]}
          ]
        },
        %{
          id: "kinds-of-site",
          heading: "The Kinds of Site You Will Find",
          blocks: [
            {:ul,
             [
               "Global panels — self-service, in dollars, cheapest, support by ticket. Good if you already know what you are buying.",
               "Local shops — shillings and M-Pesa, with local support. Tangi is one of these.",
               "Marketplaces — lists of panels with reviews; the site is not the provider.",
               "Reseller sites and social-media sellers — cheapest and most variable; often a panel behind a phone."
             ]}
          ]
        },
        %{
          id: "compare",
          heading: "Comparing the Kinds Side by Side",
          blocks: [
            {:table,
             %{
               head: ["", "Global panel", "Local shop", "Reseller"],
               rows: [
                 ["Price", "Lowest", "Low to mid", "Lowest"],
                 ["Currency", "USD", "KES", "Usually KES"],
                 ["Payment", "Card, PayPal, crypto", "M-Pesa", "M-Pesa"],
                 ["Support", "Ticket, other time zones", "Local, fast", "A phone number"],
                 ["Accountable to", "A company abroad", "A local shop", "Often nobody"],
                 ["Follower source", "Mixed", "Stated", "Unknown"]
               ]
             }}
          ]
        },
        %{
          id: "ordering",
          heading: "How to Order Safely",
          blocks: [
            {:ol,
             [
               "Make sure your profile is public so followers can be delivered.",
               "Start with the smallest order — usually 1,000 followers.",
               "Watch how the followers arrive: gradually is good, instantly is not.",
               "Check the count again after a few days, not just on delivery.",
               "Only scale up once the first order behaved the way the site promised."
             ]},
            {:p,
             "The [full provider comparison](/blog/top-tiktok-followers-providers-kenya) is the wider view; this page is the site checklist."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "See [what followers should cost](/blog/tiktok-followers-price-kenya) before you buy, and read [real vs fake TikTok followers](/blog/real-vs-fake-tiktok-followers) so you know what you are looking at when the order lands."},
            {:cta,
             %{
               text: "Tangi is our own local shop — shillings, M-Pesa and a stated source.",
               href: "/shop",
               label: "See the shop"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Is it safer to buy from a website or a person?",
          answer:
            "A site you can read, that states its price and policy, is usually safer than a person you cannot check. If you buy from a reseller, apply the same checks and start with the smallest order."
        },
        %{
          question: "Do sites need my TikTok login?",
          answer:
            "No. Followers are delivered to a public profile, so no legitimate site needs your password. Anyone who asks for it should be avoided."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: price

  defp price do
    %Post{
      slug: "tiktok-followers-price-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Prices",
      title: "How Much Do TikTok Followers Cost in Kenya?",
      meta_title: "TikTok Followers Price in Kenya — What They Cost",
      description:
        "What TikTok followers cost in Kenya, from 1,000 to 50,000+, and why the price alone tells you almost nothing about what you are buying.",
      keywords: [
        "TikTok followers price Kenya",
        "TikTok followers cost Kenya",
        "1,000 TikTok followers Kenya",
        "10,000 TikTok followers Kenya",
        "cheap TikTok followers Kenya",
        "TikTok followers packages Kenya"
      ],
      intro: [
        "Followers are priced per 1,000, and the quotes you will get for the same 1,000 range from a few hundred shillings to a few thousand. Here is what the numbers mean, and what the price leaves out."
      ],
      sections: [
        %{
          id: "packages",
          heading: "TikTok Followers Packages and Prices",
          blocks: [
            {:p, "Across the Kenyan market, typical bands look like this:"},
            {:table,
             %{
               head: ["Package", "Typical price", "Search intent"],
               rows: [
                 ["1,000 followers", "KSh 300 – 1,200", "Entry-level"],
                 ["5,000 followers", "KSh 1,500 – 6,000", "Small creator"],
                 ["10,000 followers", "KSh 3,000 – 12,000", "Growth"],
                 ["25,000 followers", "KSh 7,500 – 30,000", "Established account"],
                 ["50,000+ followers", "KSh 15,000 – 60,000", "Large campaigns"]
               ]
             }},
            {:p,
             "The price scales with quantity, so the per-follower cost barely moves between the small and large packages. What changes the bill is the source behind the followers, not the size of the order."}
          ]
        },
        %{
          id: "why-not-price",
          heading: "Why Price Alone Is Not Enough",
          blocks: [
            {:p,
             "Two providers can quote the same price and sell you different things. Before you compare on price, compare on the specification:"},
            {:ul,
             [
               "Minimum quantity: a provider that only sells 10,000 at a time is not cheaper for a small account.",
               "Delivery: followers that arrive in a burst look bought and are the easiest to filter.",
               "Refill conditions: some policies cover drops for 30 days, some for a week, some not at all.",
               "Service type: \"followers\" can mean real accounts, mixed accounts, or automated ones.",
               "Extras: M-Pesa, order tracking and after-sale support all cost the provider something — and should."
             ]},
            {:p,
             "Kenyan services advertise very different combinations of these: some offer M-Pesa but no refill, some offer a refill but no tracking, some claim targeting they cannot deliver. Compare the whole specification, not the headline price."}
          ]
        },
        %{
          id: "reading-a-quote",
          heading: "How to Read a Quote",
          blocks: [
            {:ol,
             [
               "Convert everything to a price per 1,000, in shillings.",
               "Check the minimum, and whether it suits your account.",
               "Check the delivery window and the refill term.",
               "Check the payment method and whether M-Pesa is offered.",
               "Decide whether the difference in price is explained by the difference in service."
             ]},
            {:p,
             "If a quote is dramatically cheaper and nothing else explains it, the explanation is the follower source. See [real vs fake TikTok followers](/blog/real-vs-fake-tiktok-followers)."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Compare the providers themselves in the [provider comparison](/blog/top-tiktok-followers-providers-kenya), or read [TikTok followers vs views](/blog/tiktok-followers-vs-views) if you are not yet sure what to buy."},
            {:cta,
             %{
               text:
                 "Browse the shop to see what is on sale, priced in shillings and paid by M-Pesa.",
               href: "/shop",
               label: "Visit the shop"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How much should I expect to pay for 1,000 TikTok followers in Kenya?",
          answer:
            "Broadly KSh 300 to KSh 1,200. Below that, assume the followers are the automated kind; above it, you may be paying for targeting, a refill or local support."
        },
        %{
          question: "Are larger TikTok followers packages cheaper per follower?",
          answer:
            "Not automatically. The price usually scales with quantity, so the per-follower cost stays roughly flat. Compare the whole specification, not just the total."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: real vs fake

  defp real_vs_fake do
    %Post{
      slug: "real-vs-fake-tiktok-followers",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Trust",
      title: "Real vs Fake TikTok Followers: How to Choose a Quality Provider",
      meta_title: "Real vs Fake TikTok Followers — How to Choose a Quality Provider",
      description:
        "How to tell real TikTok followers from fake ones — quality, retention, spikes, engagement ratios, refills, delivery patterns and password requests — and what a provider's claims can and cannot prove.",
      keywords: [
        "real TikTok followers Kenya",
        "real TikTok followers",
        "fake TikTok followers",
        "legitimate TikTok followers provider",
        "safe TikTok followers Kenya",
        "genuine TikTok followers Kenya",
        "TikTok followers that don't disappear"
      ],
      intro: [
        "Providers make very different claims about \"real\" and \"high-quality\" followers, and those words are not regulated. This article separates what a provider claims from what you can actually verify, and gives you the tests that work either way."
      ],
      sections: [
        %{
          id: "quality",
          heading: "Follower Quality",
          blocks: [
            {:p,
             "At one end, followers are accounts genuinely run by people who chose to follow. At the other, they are automated accounts created to be sold. Both raise the number; only one behaves like an audience."},
            {:p,
             "Because \"real\" is a marketing word, do not rely on it. Rely on what you can observe after delivery."}
          ]
        },
        %{
          id: "retention",
          heading: "Retention",
          blocks: [
            {:p,
             "The most useful test is retention: are the followers still there a week later? Real followers persist; automated ones are often removed or quietly disappear. A provider with a written refill policy is effectively promising this test will pass — which is why it matters more than the adjective on the sales page."}
          ]
        },
        %{
          id: "spikes",
          heading: "Sudden Follower Spikes",
          blocks: [
            {:p,
             "Real audiences grow as people discover you. Thousands of followers in minutes is not how people behave, and it is the pattern most likely to be filtered. A serious provider delivers gradually, because it is both safer and more believable."}
          ]
        },
        %{
          id: "engagement-ratio",
          heading: "Engagement and Follower Ratios",
          blocks: [
            {:p,
             "Watch the ratio between your follower count and your typical views, likes and comments. Real growth keeps the ratio roughly sensible; a follower count that jumps while engagement stays flat is the signature of bought, inactive followers — and brands and the algorithm both notice."},
            {:p,
             "This is the strongest evidence either way, and it is one you can check yourself, without trusting anyone's claim."}
          ]
        },
        %{
          id: "refills",
          heading: "Refill Policies",
          blocks: [
            {:p,
             "A refill policy is the provider putting its own money behind the claim. It should be written, and it should cover follower drops for a stated period. A provider without one is telling you it does not expect the followers to last."}
          ]
        },
        %{
          id: "delivery-patterns",
          heading: "Delivery Patterns",
          blocks: [
            {:p,
             "Ask how delivery works before you buy: over how many hours or days, and at what rate. Gradual delivery is slower and safer; instant delivery is easier to sell and easier to detect."}
          ]
        },
        %{
          id: "password",
          heading: "Password Requirements",
          blocks: [
            {:p,
             "This is a hard line. Followers are delivered to a public profile, so no legitimate provider needs your password. A provider that asks for it is asking for control of your account, not to deliver a number — avoid it completely."}
          ]
        },
        %{
          id: "cheap",
          heading: "Suspiciously Cheap Services",
          blocks: [
            {:p,
             "A price far below the market is the clearest signal of all. Real, retained followers cost the provider money to deliver; a price that ignores that is describing a cheaper source. The bargain is in the source, not in the value."}
          ]
        },
        %{
          id: "claims",
          heading: "Claims vs What You Can Verify",
          blocks: [
            {:p, "Split what a provider says from what you can check:"},
            {:table,
             %{
               head: ["They claim", "You can verify"],
               rows: [
                 ["\"Real followers\"", "Whether the count holds a week later"],
                 ["\"High quality\"", "The engagement-to-follower ratio"],
                 ["\"Kenyan followers\"", "Whether the mix looks local over time"],
                 ["\"Guaranteed\"", "Whether the refill policy is written and honoured"]
               ]
             }},
            {:p,
             "Buy on the right-hand column. Read the [provider comparison](/blog/top-tiktok-followers-providers-kenya) for how the kinds of provider stack up on it."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "This is the trust spoke of the [TikTok followers provider comparison](/blog/top-tiktok-followers-providers-kenya). If the followers are settled, the next question is usually [followers vs views](/blog/tiktok-followers-vs-views)."},
            {:cta,
             %{
               text:
                 "Tangi states the follower source, delivers gradually and offers a refill when delivery falls short.",
               href: "/shop",
               label: "See the shop"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How can I tell if my followers are real?",
          answer:
            "Check retention first — are they still there in a week? — then the ratio of followers to views and likes. Real followers hold and engage at a believable rate; bought inactive followers do neither."
        },
        %{
          question: "Do providers really need my password for followers?",
          answer:
            "No. Followers can be delivered to any public profile without logging in. A provider asking for your password is a red flag, not a requirement."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: organic growth

  defp organic_growth do
    %Post{
      slug: "how-to-grow-tiktok-followers-in-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Organic growth",
      title: "How to Grow Your TikTok Followers in Kenya",
      meta_title: "How to Grow Your TikTok Followers in Kenya",
      description:
        "Practical, organic ways to grow TikTok followers in Kenya — trends, hooks, TikTok SEO, hashtags, posting frequency, Lives, comments and collaborations — with paid growth as one tool among many.",
      keywords: [
        "how to grow TikTok followers Kenya",
        "grow TikTok Kenya",
        "increase TikTok followers Kenya",
        "TikTok growth Kenya",
        "get more TikTok followers",
        "TikTok marketing Kenya",
        "grow TikTok account Kenya"
      ],
      intro: [
        "Bought followers fill a number; organic followers build an audience. The channels that last in Kenya use both, but the organic work is the engine. Here is how to earn followers, in the order we would fix things."
      ],
      sections: [
        %{
          id: "trends",
          heading: "Use Kenyan Trends, Not Just Global Ones",
          blocks: [
            {:p,
             "TikTok rewards relevance. A sound or format that is trending in Kenya will reach Kenyan viewers far better than a global trend your audience has already scrolled past. Watch what is rising locally, and move on it quickly — trends are worth more in the first day or two."}
          ]
        },
        %{
          id: "hooks",
          heading: "Nail the First Two Seconds",
          blocks: [
            {:p,
             "TikTok decides whether to keep showing your video based on how people react in the first moments. Open with the payoff, the question or the surprise — never with an intro. If the hook does not land, nothing else about the video matters."}
          ]
        },
        %{
          id: "seo",
          heading: "TikTok SEO and Hashtags",
          blocks: [
            {:p,
             "TikTok is a search engine too. Put the words people search into the video, the caption and the on-screen text:"},
            {:ul,
             [
               "Use the phrases people type: \"how to\", \"best\", \"in Kenya\", \"Nairobi\", \"recipe\", \"tutorial\".",
               "Write a caption that says what the video is, naturally.",
               "Use a few relevant hashtags, not thirty.",
               "Include a local reference where it fits — a place, a festival, a term your audience uses.",
               "Say the keyword out loud; TikTok reads captions and audio."
             ]}
          ]
        },
        %{
          id: "frequency",
          heading: "Post Often, and Consistently",
          blocks: [
            {:p,
             "TikTok rewards volume and consistency more than any other platform. A posting rhythm you can actually keep — several short videos a week — beats occasional polished ones. The algorithm needs data, and data comes from volume."}
          ]
        },
        %{
          id: "live",
          heading: "Go Live",
          blocks: [
            {:p,
             "TikTok Live surfaces you to your own followers and to people browsing Lives, and it converts viewers into followers faster than almost anything else. A regular Live — a Q&A, a behind-the-scenes, a skill demonstration — turns passive viewers into a community."}
          ]
        },
        %{
          id: "comments",
          heading: "Work the Comments",
          blocks: [
            {:p,
             "Reply to comments, pin the good ones, and answer questions with a follow-up video. Comments are free engagement, they extend a video's reach, and they give you the next video's idea. Replying is also how you turn a viewer into a follower."}
          ]
        },
        %{
          id: "storytelling",
          heading: "Short-Form Storytelling",
          blocks: [
            {:p,
             "The accounts that grow have a reason to be followed, not just a feed of clips. A series, a character, a running lesson or a point of view gives viewers a reason to tap follow rather than scroll on. Decide what your account is for, and deliver it every time."}
          ]
        },
        %{
          id: "collabs",
          heading: "Collaborate With Kenyan Creators",
          blocks: [
            {:p,
             "A duet, a stitch or a joint video with another Kenyan creator swaps audiences that already like the same thing — the cheapest relevant followers you will ever get. Approach creators your own size; the swap is fairer and the audiences overlap more."}
          ]
        },
        %{
          id: "repost",
          heading: "Repost What Works",
          blocks: [
            {:p,
             "When a video performs, do not retire it. Repost the idea in a new format, cut the best moment into a fresh video, or make a follow-up. You already know it works — reuse it rather than starting from scratch every time."}
          ]
        },
        %{
          id: "convert",
          heading: "Convert Viewers Into Followers",
          blocks: [
            {:p,
             "A video can reach a hundred thousand people and still convert none of them. Ask for the follow — once, at the point of value — tell viewers what they get by following, and keep a consistent identity so the follow feels worth it. Reach is wasted without a reason to stay."}
          ]
        },
        %{
          id: "paid",
          heading: "Where Paid Growth Fits",
          blocks: [
            {:p,
             "Organic growth is the engine; a modest order of [TikTok followers](/blog/top-tiktok-followers-providers-kenya) is the ignition — it stops a new profile looking empty while the real audience builds. Keep the paid number smaller than what you expect to earn, and let the organic work above do the rest."},
            {:cta,
             %{
               text:
                 "Give a new TikTok profile a fair start — browse the shop for followers and views in Kenya.",
               href: "/shop",
               label: "Visit the shop"
             }}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "This is the organic-growth spoke of the [TikTok followers provider comparison](/blog/top-tiktok-followers-providers-kenya). If you are deciding what to buy, read [followers vs views](/blog/tiktok-followers-vs-views)."}
          ]
        }
      ],
      faqs: [
        %{
          question: "How long does it take to grow TikTok followers organically?",
          answer:
            "It varies, but most Kenyan accounts see steady growth after a few weeks of consistent posting, once a format starts to land. Volume, hooks and the follow ask decide how fast it goes."
        },
        %{
          question: "Do I need to post every day?",
          answer:
            "Daily is ideal for TikTok, but consistency matters more than the exact number. A rhythm you can keep several times a week beats sporadic bursts."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: followers vs views

  defp followers_vs_views do
    %Post{
      slug: "tiktok-followers-vs-views",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Explainer",
      title: "TikTok Followers vs TikTok Views: What's the Difference?",
      meta_title: "TikTok Followers vs Views — What's the Difference?",
      description:
        "TikTok followers, views, likes, shares and comments measure different things. This explains each one, what it does for your account, and which to buy for your goal.",
      keywords: [
        "TikTok followers vs views",
        "buy TikTok followers or views",
        "TikTok followers and views Kenya",
        "TikTok views Kenya",
        "TikTok engagement Kenya",
        "TikTok followers package"
      ],
      intro: [
        "If you know you want to grow but are not sure what to buy, this is the page for you. Followers, views, likes, shares and comments are not interchangeable — each measures something different, and each does a different job for your account."
      ],
      sections: [
        %{
          id: "the-metrics",
          heading: "Each Metric, and What It Does",
          blocks: [
            {:table,
             %{
               head: ["Metric", "Level", "What it does for you"],
               rows: [
                 [
                   "Followers",
                   "Profile",
                   "Grows the audience that sees your future videos and judges your credibility."
                 ],
                 [
                   "Views",
                   "Video",
                   "Makes a video look watched and gives the algorithm an early signal."
                 ],
                 ["Likes", "Content", "Signals that a piece of content is appreciated."],
                 ["Shares", "Distribution", "Pushes the video into other people's feeds."],
                 ["Comments", "Interaction", "Starts conversation and extends a video's reach."]
               ]
             }},
            {:p,
             "Followers are a profile-level metric; the other four are per-video. Buying one does not buy the others."}
          ]
        },
        %{
          id: "followers",
          heading: "Followers: The Profile Metric",
          blocks: [
            {:p,
             "Followers decide how your account is judged. A brand, a client or a new viewer checks the number before they check anything else, and your followers are the base audience that sees each new video. Followers are the slowest metric to build and the one that compounds."}
          ]
        },
        %{
          id: "views",
          heading: "Views: The Video Metric",
          blocks: [
            {:p,
             "Views measure how many times a video played. They feed discovery — a video with an early burst of views is more likely to be pushed into more feeds — but they do not add to your base audience. A viral video with no follow ask often produces views and no followers."}
          ]
        },
        %{
          id: "engagement",
          heading: "Likes, Shares and Comments",
          blocks: [
            {:p,
             "These are content-level signals. Likes show appreciation, shares extend distribution, and comments create interaction — and TikTok weighs them when deciding how far to push a video. They matter for a specific video's reach more than for your profile."}
          ]
        },
        %{
          id: "which-to-buy",
          heading: "Which Should You Buy?",
          blocks: [
            {:ul,
             [
               "Want a fuller-looking profile fast: followers.",
               "Want to give a specific video momentum: views.",
               "Want a video to look appreciated: likes and comments.",
               "Want to extend a video's reach: shares.",
               "Want the account to actually grow: organic work first, then a modest paid order."
             ]},
            {:p,
             "Most Kenyan buyers start with a small followers order for the profile, and views for the videos they are actively promoting. The [provider comparison](/blog/top-tiktok-followers-providers-kenya) covers who to buy from; [how to grow your followers](/blog/how-to-grow-tiktok-followers-in-kenya) covers the organic side."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Once you know what you are buying, see [what followers cost](/blog/tiktok-followers-price-kenya) and how to check you got [real ones](/blog/real-vs-fake-tiktok-followers)."},
            {:cta,
             %{
               text:
                 "Browse the shop for TikTok followers, views and likes in Kenya, priced in shillings.",
               href: "/shop",
               label: "Visit the shop"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Should I buy followers or views first?",
          answer:
            "If your profile is new and looks empty, followers first; if you have a specific video you are pushing, views. Followers change how the profile is judged, while views change how a single video performs."
        },
        %{
          question: "Do views turn into followers?",
          answer:
            "They can, but not automatically. A video only converts viewers into followers if it gives them a reason to follow — a series, a clear value, and an explicit ask."
        }
      ]
    }
  end
end
