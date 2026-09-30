defmodule ViewNinjas.Blog.Clusters.TopYoutubeViewsProvidersKenya do
  @moduledoc """
  The "top YouTube views providers in Kenya" cluster: one pillar and five spokes.

  This cluster is the commercial-investigation arm of the blog — the reader is
  choosing a provider, not yet a price or a number. The pillar is written as a
  real comparison of the kinds of provider a Kenyan buyer meets (global panels,
  local shops, agencies and freelancers) rather than a landing page for our own
  shop, and it names that shop, Tangi, as one row among several — with the
  trade-offs stated honestly.
  """

  alias ViewNinjas.Blog.{Cluster, Post}

  @cluster "top-youtube-views-providers-kenya"
  @updated ~D[2026-09-30]

  @doc "The cluster's own metadata."
  @spec cluster() :: Cluster.t()
  def cluster do
    %Cluster{
      slug: @cluster,
      eyebrow: "Provider comparison",
      title: "Top YouTube Views Providers in Kenya",
      keyword: "top YouTube views providers in Kenya",
      description:
        "An honest comparison of the kinds of YouTube views provider you can buy from in Kenya — price, delivery, traffic quality, retention, support and M-Pesa payment — and how to judge any of them."
    }
  end

  @doc "Every post in the cluster, pillar first."
  @spec posts() :: [Post.t()]
  def posts do
    [
      pillar(),
      top_ten(),
      best_sites(),
      prices(),
      real_vs_fake(),
      promotion_services(),
      how_to_choose()
    ]
  end

  # ------------------------------------------------------------------ pillar

  defp pillar do
    %Post{
      slug: "top-youtube-views-providers-kenya",
      cluster: @cluster,
      kind: :pillar,
      updated_on: @updated,
      eyebrow: "Provider comparison",
      title: "Top YouTube Views Providers in Kenya: Compare the Best Services",
      meta_title: "Top YouTube Views Providers in Kenya — Compared",
      description:
        "An honest comparison of the types of YouTube views provider in Kenya — how they differ on price, delivery speed, traffic quality, retention, support and M-Pesa payment — and how to judge any of them, ours included.",
      keywords: [
        "top YouTube views providers in Kenya",
        "best YouTube views providers Kenya",
        "YouTube views providers Kenya",
        "best site to buy YouTube views Kenya",
        "buy YouTube views Kenya",
        "YouTube promotion services Kenya",
        "YouTube views services Kenya",
        "YouTube views companies Kenya",
        "real YouTube views Kenya"
      ],
      intro: [
        "Search for \"YouTube views in Kenya\" and you will find a dozen businesses selling the same four words at prices that differ tenfold. This page is the comparison we would have wanted when we started: what the different kinds of provider actually are, how they differ on the things that matter, and how to judge any of them.",
        "Full disclosure before we go further: Tangi is our own shop. We have written this as a genuine comparison anyway — including where we are not the right choice — and we compare ourselves against the categories we actually compete with, not against a straw man."
      ],
      sections: pillar_sections(),
      faqs: pillar_faqs()
    }
  end

  defp pillar_sections do
    [
      %{
        id: "what-are-providers",
        heading: "What Are YouTube Views Providers?",
        blocks: [
          {:p,
           "A YouTube views provider is a business that delivers views to a video you choose. Some are large automated platforms — usually called panels — where you sign up, pick a service from a list and pay in dollars. Some are local shops that package the same delivery for a Kenyan audience, priced in shillings and paid by M-Pesa. Others are agencies that sell full promotion campaigns, or individuals who resell someone else's service from their phone."},
          {:p,
           "They are not the same product. Two providers charging wildly different prices for \"1,000 views\" are almost always delivering from different sources, at different speeds, with different odds that the views stay. Everything that follows is about those differences."}
        ]
      },
      %{
        id: "how-services-work",
        heading: "How YouTube View Services Work",
        blocks: [
          {:p, "Under the marketing, most providers sit on the same few layers:"},
          {:ul,
           [
             "A supplier — a \"panel\" — that routes traffic to a video when an order is placed.",
             "A delivery network: real accounts through reward apps and ad pools, or automated traffic.",
             "A delivery schedule: instant, or spread over hours and days.",
             "A reseller layer: local shops and freelancers reselling a panel's capacity."
           ]},
          {:p,
           "When you buy from a local shop, you are usually buying a panel's capacity plus local payment, support and curation. That is a real difference in experience even when the underlying traffic is identical — and it is the reason a shop can be more accountable than a large foreign panel you cannot phone."}
        ]
      },
      %{
        id: "what-to-look-for",
        heading: "What to Look for in a YouTube Views Provider",
        blocks: [
          {:p, "Whatever kind of provider you are comparing, the checklist is short:"},
          {:ul,
           [
             "A clear price, in shillings, before you pay.",
             "A stated traffic source — real accounts, or automated.",
             "Realistic delivery times: hours, not \"instant\".",
             "A refill or replacement policy if delivery falls short.",
             "Support you can actually reach.",
             "A minimum order you can afford.",
             "No unrealistic guarantees."
           ]},
          {:p,
           "Two of these are worth their own articles: [how to choose a YouTube views provider in Kenya](/blog/how-to-choose-a-youtube-views-provider) turns the list into a set of questions to ask any seller, and [real vs fake YouTube views](/blog/real-vs-fake-youtube-views) explains how to tell the source behind the number."}
        ]
      },
      %{
        id: "types",
        heading: "Types of YouTube View Services",
        blocks: [
          {:p,
           "In Kenya you will meet four kinds of provider. They differ more than their prices do:"},
          {:ul,
           [
             "Global panels and marketplaces: the cheapest per 1,000, priced in dollars and paid by card, PayPal or crypto, with ticket support in another time zone and very mixed traffic quality.",
             "Local shops — like Tangi: the same delivery, priced in shillings and paid by M-Pesa, with local support and a curated grade you can choose.",
             "Social media and marketing agencies: they sell campaigns, ads and content — not usually raw views — and they charge for the strategy, not the thousand.",
             "Freelancers and resellers: cheapest and most variable. Often reselling a panel from their phone, with no visibility into the source."
           ]},
          {:p,
           "Most Kenyan buyers end up choosing between a global panel and a local shop. If you are that buyer, the rest of this page is the comparison you need."}
        ]
      },
      %{
        id: "comparing",
        heading: "Comparing YouTube Views Providers in Kenya",
        blocks: [
          {:p,
           "This is the honest picture of the four categories, across the things that actually decide whether you get what you paid for."},
          {:table,
           %{
             head: ["Factor", "Tangi (ours)", "Global panels", "Agencies", "Freelancers"],
             rows: [
               [
                 "Price",
                 "From ~KSh 240/1,000",
                 "Cheapest, in USD",
                 "Highest; campaign fees",
                 "Varies wildly"
               ],
               [
                 "Delivery",
                 "Gradual, hours to days",
                 "Often near-instant",
                 "Scheduled",
                 "Manual, uneven"
               ],
               [
                 "Traffic",
                 "Real accounts, graded",
                 "Mixed; cheap sources common",
                 "Usually ads, not views",
                 "Unknown; resold"
               ],
               [
                 "Retention",
                 "Best on the Quality grade",
                 "Often weak",
                 "Real, or not applicable",
                 "Unknown"
               ],
               [
                 "Support",
                 "Local, in-app and WhatsApp",
                 "Ticket, other time zones",
                 "Account manager",
                 "A phone number"
               ],
               [
                 "Payment",
                 "M-Pesa, in shillings",
                 "Card, PayPal or crypto",
                 "Invoice; M-Pesa",
                 "M-Pesa, informal"
               ],
               [
                 "Guarantee",
                 "Refill if delivery is short",
                 "Varies; often none",
                 "Contract terms",
                 "Rarely"
               ]
             ]
           }},
          {:callout,
           "These are honest generalisations about each category, not a claim about any specific competitor. Any individual provider can be better or worse than its category. The only row we can vouch for is our own."}
        ]
      },
      %{
        id: "pricing",
        heading: "Pricing",
        blocks: [
          {:p,
           "Expect anywhere from a few hundred shillings per 1,000 views to a few thousand. The floor is set by how the traffic is produced: real accounts routed through reward networks cost a supplier real money, so a price far below everyone else is a statement about the source, not a bargain."},
          {:p,
           "A local shop usually sits above the cheapest panel and below an agency, because you are paying for shillings, M-Pesa and support on top of the delivery. That premium is worth it only if the shop is actually accountable — see the [price comparison](/blog/youtube-views-prices-in-kenya) for the numbers."}
        ]
      },
      %{
        id: "delivery-speed",
        heading: "Delivery Speed",
        blocks: [
          {:p,
           "Fast is easy to sell and easy to detect. Automated traffic can drop thousands of views onto a video in a minute, which is both unnatural and the pattern most likely to be filtered. Real delivery is spread over hours or days."},
          {:p,
           "So a provider promising 100,000 views in five minutes is telling you two things: the traffic is automated, and it does not care whether the views survive. Gradual delivery is slower and safer."}
        ]
      },
      %{
        id: "traffic-quality",
        heading: "Audience and Traffic Quality",
        blocks: [
          {:p,
           "Where do the views come from, and who are they? A provider that can answer that — real accounts, from this region, over this window — is doing the one thing that separates a serious service from a reseller. A provider that cannot is, in practice, asking you to trust a number."},
          {:p,
           "For Kenyan creators and local businesses, geography matters. Views that all originate from a datacentre abroad are worthless to a business selling in Nairobi, and obvious to YouTube."}
        ]
      },
      %{
        id: "retention",
        heading: "Retention",
        blocks: [
          {:p,
           "Retention is how long a viewer actually watched, and it is the number YouTube cares about. It is also the hardest thing for a provider to fake, which makes it your best test. Ask what happens to retention, and treat a blank answer as an answer."}
        ]
      },
      %{
        id: "support",
        heading: "Customer Support",
        blocks: [
          {:p,
           "Something will occasionally go wrong — a short delivery, a paused order, a link that was private. What matters is whether there is a person you can reach while it is happening. A shop you can message on WhatsApp is worth more than a panel whose only contact is a ticket queue eight hours behind you."}
        ]
      },
      %{
        id: "payments",
        heading: "Payment Methods Available in Kenya",
        blocks: [
          {:p,
           "This is where global panels lose most Kenyan buyers. A panel wants a card, PayPal or crypto, in dollars, with a conversion and often a minimum. A local shop takes M-Pesa in shillings, which is the payment almost everyone in Kenya actually has."},
          {:p,
           "Beyond convenience, paying locally gives you a local name, a local price in shillings, and someone to hold to account if the order is wrong."}
        ]
      },
      %{
        id: "legit",
        heading: "Are YouTube Views Providers Legit?",
        blocks: [
          {:p,
           "\"Legit\" means two different things and it is worth separating them. It can mean the business is real and honest — it delivers what it sells, does not vanish, and tells you where the views come from. On that measure, a provider can be completely legit. It can also mean the traffic is within YouTube's rules, and there the honest answer is that paid artificial views are against YouTube's terms of service, so no provider can promise a channel is completely safe."},
          {:p,
           "A legitimate provider is the one that is straight with you about that trade-off — states its source, offers a refill, and does not pretend the practice is something it is not. The sketchy ones are the opposite: no stated source, no policy, and promises too good to be true."}
        ]
      },
      %{
        id: "avoid-poor",
        heading: "How to Avoid Poor-Quality Providers",
        blocks: [
          {:p, "The warning signs are consistent across every category:"},
          {:ul,
           [
             "No stated traffic source, or a vague one.",
             "Instant delivery, or an \"unlimited\" promise.",
             "Prices far below the market with no explanation.",
             "No refill or replacement policy.",
             "No reachable support, or a support channel that only takes messages.",
             "Guarantees about subscribers, rankings or going viral.",
             "A payment method you cannot reverse or trace."
           ]},
          {:p,
           "Read the [full breakdown of real versus fake views](/blog/real-vs-fake-youtube-views) before you spend anything."}
        ]
      },
      %{
        id: "views-vs-ads",
        heading: "YouTube Views vs YouTube Ads",
        blocks: [
          {:p,
           "A provider comparison would be incomplete without the alternative: not buying views at all, and running YouTube Ads instead. They do different jobs."},
          {:table,
           %{
             head: ["", "Bought views", "YouTube Ads"],
             rows: [
               ["You pay for", "A set number of views", "Impressions or watch time, by auction"],
               ["Control", "Quantity and grade", "Targeting, budget and schedule"],
               ["Reporting", "A number", "Full Google Ads reporting"],
               ["Best for", "Momentum and social proof", "Precise targeting and leads"]
             ]
           }},
          {:p,
           "We compare all five promotion routes — views, ads, influencers, social media and organic SEO — in [YouTube promotion services in Kenya](/blog/youtube-promotion-services-kenya)."}
        ]
      },
      %{
        id: "tangi",
        heading: "Tangi's YouTube Views Service",
        blocks: [
          {:p,
           "Tangi is our shop — the one this site runs — and the row in the table above that we can vouch for. It exists because the choice in Kenya was between a foreign panel you could not pay easily and a reseller you could not trust."},
          {:ul,
           [
             "Priced in shillings, from about KSh 240 per 1,000 views, and paid by M-Pesa.",
             "Three grades — Cheap, Moderate and Quality — so you can choose the source, not just the number.",
             "Real accounts on the better grades, delivered gradually over hours or days.",
             "A refill when delivery falls short, and support you can reach locally.",
             "A minimum of a thousand views, so a small channel can start."
           ]},
          {:p,
           "What we do not claim: we cannot promise your channel is completely safe, and we do not sell subscribers or comments. If those matter to you, we are not the right provider, and the honest thing is to say so."},
          {:cta,
           %{
             text:
               "See Tangi's YouTube views service in the shop — three grades, prices in shillings, M-Pesa checkout.",
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
             "[Top 10 YouTube views providers in Kenya](/blog/top-10-youtube-views-providers-kenya)",
             "[Best sites to buy YouTube views in Kenya](/blog/best-sites-to-buy-youtube-views-in-kenya)",
             "[YouTube views prices in Kenya: what 1,000 views cost](/blog/youtube-views-prices-in-kenya)",
             "[Real vs fake YouTube views: how to identify a quality provider](/blog/real-vs-fake-youtube-views)",
             "[YouTube promotion services in Kenya compared](/blog/youtube-promotion-services-kenya)",
             "[How to choose a YouTube views provider in Kenya](/blog/how-to-choose-a-youtube-views-provider)"
           ]},
          {:p,
           "For the buyer's view of the whole subject, start from [the complete guide to buying YouTube views in Kenya](/blog/buy-youtube-views-kenya)."}
        ]
      }
    ]
  end

  defp pillar_faqs do
    [
      %{
        question: "Which YouTube views provider in Kenya is the best?",
        answer:
          "There is no single best one — it depends on whether you value price, local payment, traffic quality or support most. A global panel is cheapest; a local shop like Tangi is easier to pay and to hold to account; an agency is best if you want ads and strategy rather than raw views. Judge any of them on source, delivery, retention and support, not on the headline price."
      },
      %{
        question: "How do I know a provider is delivering real views?",
        answer:
          "Ask where the traffic comes from, then watch the delivery: real accounts arrive gradually and some leave engagement, while automated traffic arrives in bursts and leaves nothing. The honest test is retention after delivery, not the number at the end of it."
      },
      %{
        question: "Why are some Kenyan YouTube views providers so cheap?",
        answer:
          "Because their traffic is cheaper to produce — usually automated rather than real accounts. A price far below the market is a signal about the source, and cheap automated views are the ones most likely to be removed."
      },
      %{
        question: "Can I pay a views provider in Kenya by M-Pesa?",
        answer:
          "Local shops take M-Pesa in shillings; global panels usually want a card, PayPal or crypto in dollars. If M-Pesa matters to you, that alone narrows the field to local providers."
      },
      %{
        question: "Do YouTube views providers offer a guarantee?",
        answer:
          "The good ones offer a refill or replacement when delivery falls short. Be wary of any guarantee that promises rankings, subscribers or that a channel will never be affected — nobody can honestly promise those."
      }
    ]
  end

  # --------------------------------------------------- spoke: best sites

  defp best_sites do
    %Post{
      slug: "best-sites-to-buy-youtube-views-in-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Where to buy",
      title: "Best Sites to Buy YouTube Views in Kenya",
      meta_title: "Best Sites to Buy YouTube Views in Kenya",
      description:
        "How to judge the sites selling YouTube views in Kenya — the seven factors that separate a good one from a bad one — and the four kinds of site you will meet.",
      keywords: [
        "best sites to buy YouTube views in Kenya",
        "best website to buy YouTube views Kenya",
        "YouTube views websites Kenya",
        "where to buy YouTube views Kenya",
        "YouTube views online Kenya"
      ],
      intro: [
        "\"Best\" is doing a lot of work in that search. A site can be the cheapest and still be the wrong choice, or cost more and be the one you should actually use. This page is about how to judge the sites you will find, and which kind you are most likely to want."
      ],
      sections: [
        %{
          id: "what-best-means",
          heading: "What \"Best\" Should Mean",
          blocks: [
            {:p,
             "The best site for you is the one that is honest about what it delivers, easy for you to pay, and accountable when something goes wrong. Price is one column in that table, not the whole table. A site that is 30% cheaper but cannot tell you where the views come from is not cheaper — it is a different, worse product."}
          ]
        },
        %{
          id: "what-to-examine",
          heading: "Seven Things to Examine on Any Site",
          blocks: [
            {:p, "Before you create an account anywhere, check these:"},
            {:table,
             %{
               head: ["Factor", "What to examine"],
               rows: [
                 ["Price", "Cost per 1,000 views, stated in shillings if it is a Kenyan site."],
                 ["Delivery", "Whether views are scheduled gradually or promised instantly."],
                 ["Traffic", "The stated source and geography of the views."],
                 ["Retention", "Whether the views persist, and what happens if they do not."],
                 ["Support", "Whether there is a person you can reach, and how fast."],
                 ["Payment", "Whether M-Pesa is offered, and whether the price is in shillings."],
                 ["Guarantees", "The refill or replacement policy, in writing."]
               ]
             }},
            {:p,
             "A site that answers all seven in plain language is a site worth trying. One that dodges three of them is not."}
          ]
        },
        %{
          id: "kinds-of-site",
          heading: "The Four Kinds of Site You Will Find",
          blocks: [
            {:ul,
             [
               "Global panels — self-service, priced in dollars, cheapest, support by ticket. Good if you already know what you are buying and can pay in dollars.",
               "Local shops — priced in shillings, paid by M-Pesa, with local support. Good if you want M-Pesa and someone to hold to account. Tangi is one of these.",
               "Agencies — they sell promotion and ads, not usually raw views. Good if you want a campaign run for you.",
               "Reseller sites and social-media sellers — cheapest and most variable, often a panel behind a phone. Fine only if you can verify the source."
             ]}
          ]
        },
        %{
          id: "comparing-sites",
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
                 ["Traffic quality", "Mixed", "Graded and stated", "Unknown"]
               ]
             }}
          ]
        },
        %{
          id: "how-to-try-safely",
          heading: "How to Try a Site Safely",
          blocks: [
            {:ol,
             [
               "Start with the smallest order the site allows — usually 1,000 views.",
               "Watch how the views arrive: gradually is good, instantly is not.",
               "Check the video's retention afterwards, not just the view count.",
               "Check that the views persist over the following days.",
               "Only scale up once the first order behaved the way the site promised."
             ]}
          ]
        },
        %{
          id: "red-flags",
          heading: "Red Flags",
          blocks: [
            {:ul,
             [
               "No price until you message them.",
               "Instant delivery, or \"guaranteed within minutes\".",
               "A price far below every other site, with no explanation.",
               "No refill policy, or one buried out of sight.",
               "Guarantees about subscribers or rankings.",
               "A payment method you cannot trace."
             ]}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "This article is a spoke of our [comparison of YouTube views providers in Kenya](/blog/top-youtube-views-providers-kenya). If you have a site in mind, run it past the [provider checklist](/blog/how-to-choose-a-youtube-views-provider), and see [what the prices should be](/blog/youtube-views-prices-in-kenya) before you commit."},
            {:cta,
             %{
               text:
                 "Tangi is our own local shop — shillings, M-Pesa and a stated source on every grade.",
               href: "/shop",
               label: "See the shop"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Is it better to buy from a website or a person?",
          answer:
            "A website you can read, that states its price and policy, is usually safer than a person you cannot check. If you buy from a reseller, apply the same seven checks and start with the smallest order."
        },
        %{
          question: "Which sites take M-Pesa in Kenya?",
          answer:
            "Local shops do; global panels usually do not. If M-Pesa is a requirement, filter to local providers first."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: prices

  defp prices do
    %Post{
      slug: "youtube-views-prices-in-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Prices",
      title: "YouTube Views Prices in Kenya: How Much Does 1,000 Views Cost?",
      meta_title: "YouTube Views Prices in Kenya — What 1,000 Views Cost",
      description:
        "What YouTube views cost in Kenya, from 1,000 to 100,000 views, and why two providers can quote very different prices for what looks like the same order.",
      keywords: [
        "YouTube views price Kenya",
        "buy 1,000 YouTube views Kenya",
        "YouTube views cost Kenya",
        "10,000 YouTube views Kenya",
        "cheap YouTube views Kenya",
        "YouTube promotion price Kenya"
      ],
      intro: [
        "Every provider in Kenya is quoting for \"1,000 YouTube views\", and the quotes do not match. This page is the price side of the [provider comparison](/blog/top-youtube-views-providers-kenya): what the numbers should look like, and why the cheap ones are cheap."
      ],
      sections: [
        %{
          id: "per-thousand",
          heading: "The Price per 1,000 Views",
          blocks: [
            {:p,
             "In Kenya, views are priced per 1,000. Broadly, expect to pay somewhere between a few hundred and a few thousand shillings per 1,000 views, and the grade you pick is the biggest single factor. At our own shop, at the time of writing:"},
            {:table,
             %{
               head: ["Grade", "Price per 1,000", "What it is"],
               rows: [
                 ["Cheap", "from about KSh 240", "The fastest, lowest-cost source."],
                 ["Moderate", "from about KSh 385", "The balance of price and quality."],
                 ["Quality", "from about KSh 645", "Real, steadier accounts."]
               ]
             }}
          ]
        },
        %{
          id: "tiers",
          heading: "Prices by Order Size",
          blocks: [
            {:p,
             "Here is what the common order sizes come to, across the three grades. The price scales with the quantity, so the per-thousand cost barely moves; what changes your bill is the grade and the source behind it."},
            {:table,
             %{
               head: ["Views", "Cheap", "Moderate", "Quality"],
               rows: [
                 ["1,000", "KSh 239", "KSh 383", "KSh 644"],
                 ["5,000", "KSh 1,196", "KSh 1,916", "KSh 3,219"],
                 ["10,000", "KSh 2,391", "KSh 3,832", "KSh 6,438"],
                 ["25,000", "KSh 5,978", "KSh 9,580", "KSh 16,094"],
                 ["50,000", "KSh 11,955", "KSh 19,159", "KSh 32,188"],
                 ["100,000", "KSh 23,911", "KSh 38,319", "KSh 64,375"]
               ]
             }},
            {:p,
             "Treat these as a guide at the rates in force when this was written. The shop always shows the live price for the exact number you enter, and we break down the buying-focused version of these figures in [how much it costs to buy YouTube views in Kenya](/blog/youtube-views-price-kenya)."}
          ]
        },
        %{
          id: "why-different",
          heading: "Why Prices Differ Between Providers",
          blocks: [
            {:p,
             "If one provider quotes KSh 200 for 1,000 views and another quotes KSh 2,000, they are not selling the same thing. The gap comes from:"},
            {:ul,
             [
               "The source: automated traffic is cheap to produce; real accounts are not.",
               "Retention: views that hold attention cost more than views that bounce.",
               "Geography: views from Kenya, or a specific market, cost more than a global mix.",
               "Delivery speed: a slow, natural drip is easier to guarantee than an instant burst.",
               "What surrounds it: shillings, M-Pesa, local support and a refill policy all cost the provider something — and should.",
               "The reseller chain: every layer between you and the supplier adds a markup, or takes it out of the quality."
             ]},
            {:callout,
             "A suspiciously low price is a statement about the source, not a bargain. The cheapest view and the view that stays are usually different products."}
          ]
        },
        %{
          id: "cheap",
          heading: "Is Cheap Always Bad?",
          blocks: [
            {:p,
             "No. The cheap grade exists for a reason — a fast volume boost for a launch that needs to look alive. The mistake is expecting cheap views to behave like a real audience, or buying them in a quantity that does not match the channel. Cheap is fine when it is honest about what it is and you use it for what it is for."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Compare the other providers on price and the rest in the [provider comparison](/blog/top-youtube-views-providers-kenya), or move on to judging quality in [real vs fake YouTube views](/blog/real-vs-fake-youtube-views)."},
            {:cta,
             %{
               text:
                 "See the live price for the exact number of views you want — Tangi, priced in shillings, paid by M-Pesa.",
               href: "/shop",
               label: "Check live prices"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How much does 1,000 YouTube views cost in Kenya?",
          answer:
            "Somewhere from about KSh 240 on the cheapest grade to around KSh 645 on the best, depending on the provider and the source. Anything far below that is a signal about how the views are produced."
        },
        %{
          question: "Is there a bulk discount for 100,000 views?",
          answer:
            "Not in our pricing — the price scales with the quantity, so 100,000 views costs about a hundred times 1,000. Compare the total, not just the per-thousand headline."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: real vs fake

  defp real_vs_fake do
    %Post{
      slug: "real-vs-fake-youtube-views",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Trust",
      title: "Real vs Fake YouTube Views: How to Identify a Quality Provider",
      meta_title: "Real vs Fake YouTube Views — How to Spot a Quality Provider",
      description:
        "How to tell real YouTube views from fake ones — traffic sources, retention, unnatural spikes, geography, consistency and refill guarantees — and the warning signs of a poor provider.",
      keywords: [
        "real YouTube views Kenya",
        "real YouTube views",
        "fake YouTube views",
        "are YouTube views real",
        "legitimate YouTube views providers",
        "safe YouTube views",
        "YouTube views that don't disappear"
      ],
      intro: [
        "\"Real\" and \"fake\" are not quite the two boxes they sound like. There is a range of traffic, and the provider you choose decides where on it you land. This is how to tell which one you are getting — before you have spent much."
      ],
      sections: [
        %{
          id: "traffic-sources",
          heading: "Traffic Sources",
          blocks: [
            {:p,
             "At one end, real people — often routed through reward apps, ad networks or large promotional pools — genuinely watch the video. At the other, automated traffic loads the video just long enough to register a view. Both raise your view count; only one behaves like an audience."},
            {:p,
             "The first question for any provider is therefore the only important one: where does the traffic come from? A provider that answers clearly is doing the one thing that separates a serious service from a reseller."}
          ]
        },
        %{
          id: "retention",
          heading: "Retention",
          blocks: [
            {:p,
             "Retention is how long people actually watched, and it is the hardest thing to fake — which makes it your best test. Real viewers stay for a while; automated traffic bounces in seconds, collapsing the average view duration."},
            {:p,
             "This is also why bought views will never rescue a weak video. If real people arrive and leave in five seconds, the retention graph says so regardless of where they came from."}
          ]
        },
        %{
          id: "spikes",
          heading: "Sudden Unnatural Spikes",
          blocks: [
            {:p,
             "Real audiences build as people find the video. Thousands of views in sixty seconds is not how people behave, and it is the exact pattern that gets artificial traffic filtered. A serious provider delivers gradually, because it is both safer and more realistic."}
          ]
        },
        %{
          id: "geography",
          heading: "Geographic Targeting",
          blocks: [
            {:p,
             "For a Kenyan creator or local business, geography is part of quality. Views for a Nairobi business that all originate abroad are worthless to it and obvious to YouTube. Ask whether the provider can deliver views from real accounts in your market — and treat a vague answer as a no."}
          ]
        },
        %{
          id: "consistency",
          heading: "View Consistency",
          blocks: [
            {:p,
             "Good views arrive at a believable pace and hold. Watch the count over the days after an order: does it stay, or quietly fall back as traffic is removed? A number that persists across a week is worth more than a bigger number that does not."}
          ]
        },
        %{
          id: "refills",
          heading: "Refill Guarantees",
          blocks: [
            {:p,
             "A refill policy is the provider putting its own money behind the claim: if the views drop, or delivery falls short, at whose cost? A provider with a written refill is telling you it expects the views to last. One without is telling you something too."}
          ]
        },
        %{
          id: "engagement",
          heading: "Engagement",
          blocks: [
            {:p,
             "Real traffic sometimes leaves a like, a comment or a subscription, because real people sometimes do. Automated traffic leaves nothing. It is not a guarantee — most viewers never engage — but a provider whose views have never produced a single like for anyone is selling you a number, not an audience."}
          ]
        },
        %{
          id: "not-subscribers",
          heading: "Why Views Do Not Equal Subscribers",
          blocks: [
            {:p,
             "Views are attention; a subscription is a decision. Buying views will not turn into subscribers on its own, and it will not make a video a success. If you want subscribers, the video has to be worth following for, and a clear call to action helps."}
          ]
        },
        %{
          id: "warning-signs",
          heading: "Warning Signs of a Poor Provider",
          blocks: [
            {:ul,
             [
               "No stated source for the traffic.",
               "Instant or \"unlimited\" delivery.",
               "Prices far below everyone else with no explanation.",
               "No refill or replacement policy.",
               "Guarantees about subscribers, rankings or going viral.",
               "No reachable support.",
               "Pressure to buy a large quantity before you have tested anything."
             ]},
            {:p,
             "Reading this list back against the [provider comparison](/blog/top-youtube-views-providers-kenya) is the fastest way to sort a good seller from a bad one."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "For the objection-handling version of this question, read [are bought YouTube views real](/blog/are-bought-youtube-views-real). To choose a provider properly, work through the [checklist](/blog/how-to-choose-a-youtube-views-provider)."},
            {:cta,
             %{
               text:
                 "Tangi states its source on every grade and offers a refill when delivery falls short.",
               href: "/shop",
               label: "See Tangi's service"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I tell fake views from real ones myself?",
          answer:
            "Up to a point. Watch the delivery pace (gradual is real, instant is not), check retention afterwards, and see whether the views persist over the following week. A sudden spike that does not survive is the clearest sign of automated traffic."
        },
        %{
          question: "Do real bought views ever leave likes or comments?",
          answer:
            "Sometimes, because real people sometimes engage. Most viewers do not, so do not expect engagement to scale with views — but a total absence of it across many orders tells you what kind of traffic you are buying."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: promotion services

  defp promotion_services do
    %Post{
      slug: "youtube-promotion-services-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Services",
      title: "YouTube Promotion Services in Kenya: Views, Ads & Organic Growth Compared",
      meta_title: "YouTube Promotion Services in Kenya — Views, Ads & Organic Compared",
      description:
        "A comparison of the five main ways to promote YouTube videos in Kenya — buying views, YouTube Ads, influencer promotion, social media promotion and organic SEO — and what each one actually does.",
      keywords: [
        "YouTube promotion services Kenya",
        "YouTube marketing Kenya",
        "YouTube promotion Kenya",
        "promote YouTube video Kenya",
        "YouTube advertising Kenya",
        "YouTube growth services Kenya"
      ],
      intro: [
        "A \"YouTube promotion service\" can mean five different things, and sellers rarely say which one they are. This page compares them honestly, because none of them is universally the best — each one does a different job."
      ],
      sections: [
        %{
          id: "overview",
          heading: "The Five Routes",
          blocks: [
            {:table,
             %{
               head: ["Method", "What it actually does", "Cost in Kenya", "Best for"],
               rows: [
                 [
                   "Buying views",
                   "Delivers a set number of views quickly",
                   "Low, from a few hundred KSh per 1,000",
                   "Momentum and social proof"
                 ],
                 [
                   "YouTube Ads",
                   "Puts the video in front of a targeted audience",
                   "High; set by auction",
                   "Precise targeting and leads"
                 ],
                 [
                   "Influencer promotion",
                   "Borrows a trusted creator's audience",
                   "Mid to high; negotiated",
                   "Relevant, engaged viewers"
                 ],
                 [
                   "Social media promotion",
                   "Shares the video where your audience already is",
                   "Free, or low for paid posts",
                   "Reach on WhatsApp, TikTok, Facebook"
                 ],
                 [
                   "Organic SEO",
                   "Makes the video findable over time",
                   "Free; costs work",
                   "Compounding, lasting views"
                 ]
               ]
             }}
          ]
        },
        %{
          id: "views",
          heading: "Buying Views",
          blocks: [
            {:p,
             "What it does: adds a set number of views, fast and cheaply, so a video stops looking abandoned and the algorithm has an early signal. What it does not do: create retention, subscribers or lasting growth. It is a start, not a campaign. See [the complete guide](/blog/buy-youtube-views-kenya)."}
          ]
        },
        %{
          id: "ads",
          heading: "YouTube Ads",
          blocks: [
            {:p,
             "What it does: places the video in front of an audience you choose, with real targeting and reporting, and drives outcomes you can measure. What it does not do: come cheap, or work without setup and a budget. Best when the video has to convert, not merely exist. We compare it directly in the [provider comparison](/blog/top-youtube-views-providers-kenya)."}
          ]
        },
        %{
          id: "influencers",
          heading: "Influencer Promotion",
          blocks: [
            {:p,
             "What it does: puts your video in front of a creator's audience, with the trust that comes with a recommendation. What it does not do: scale cheaply, or guarantee relevance unless you match the audience to the topic. Best when you can find a creator your viewers already follow."}
          ]
        },
        %{
          id: "social",
          heading: "Social Media Promotion",
          blocks: [
            {:p,
             "What it does: pushes the video to where Kenyans already are — WhatsApp groups and status, TikTok, Facebook and Instagram — for little or nothing. What it does not do: scale on its own, or reach strangers reliably. Best as the base layer under everything else. We cover the tactics in [how to get more YouTube views in Kenya](/blog/how-to-get-more-youtube-views-in-kenya) and [ten promotion channels](/blog/youtube-promotion-kenya)."}
          ]
        },
        %{
          id: "seo",
          heading: "Organic YouTube SEO",
          blocks: [
            {:p,
             "What it does: makes the video findable through search and suggested for months or years, at no cost per view. What it does not do: work quickly, or without a genuinely watchable video. Best as the long game, and the reason a paid boost should always be paired with it."}
          ]
        },
        %{
          id: "which",
          heading: "Which Promotion Service Should You Choose?",
          blocks: [
            {:p, "Match the tool to the job rather than looking for a winner:"},
            {:ul,
             [
               "Just launched and need it to look alive: buying views, in a modest quantity.",
               "Need leads or sales you can measure: YouTube Ads.",
               "Want a relevant, trusting audience: an influencer collaboration.",
               "No budget yet: social media promotion and organic SEO.",
               "Building for the long term: organic SEO with a paid boost at each launch."
             ]}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "This is a spoke of the [provider comparison](/blog/top-youtube-views-providers-kenya). When you are ready to buy views specifically, the [provider checklist](/blog/how-to-choose-a-youtube-views-provider) is the next step."},
            {:cta,
             %{
               text:
                 "Tangi's YouTube promotion starts with views: shillings, M-Pesa, three grades.",
               href: "/shop",
               label: "See the shop"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Are paid promotion and buying views the same thing?",
          answer:
            "No. Paid promotion is usually ads or sponsored placements with targeting and reporting; buying views is a set number of views delivered to your video. They do different jobs and are priced very differently."
        },
        %{
          question: "Which promotion method is cheapest in Kenya?",
          answer:
            "Sharing to WhatsApp and TikTok costs only your time. After that, buying views is the cheapest way to give a video a base, well below the cost of a YouTube Ads campaign."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: how to choose

  defp how_to_choose do
    %Post{
      slug: "how-to-choose-a-youtube-views-provider",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Checklist",
      title: "How to Choose a YouTube Views Provider in Kenya",
      meta_title: "How to Choose a YouTube Views Provider in Kenya",
      description:
        "A ten-question checklist for choosing a YouTube views provider in Kenya — what to ask before you buy, what a good answer sounds like, and the claims that should send you elsewhere.",
      keywords: [
        "YouTube views provider Kenya",
        "how to buy YouTube views Kenya",
        "YouTube views provider",
        "trusted YouTube views Kenya",
        "YouTube promotion provider Kenya",
        "YouTube views service Kenya"
      ],
      intro: [
        "Choosing a provider is really a short interview. Ask the same ten questions of every seller and the right one separates itself. Here they are, with what a good answer sounds like."
      ],
      sections: [
        %{
          id: "checklist",
          heading: "The Ten Questions",
          blocks: [
            {:p, "Before you buy from any provider, check each of these:"},
            {:ol,
             [
               "Does the provider clearly explain its service? A real one says what it sells, in plain language, and in shillings.",
               "What type of traffic is being delivered? Real accounts, or automated. A good answer names the source.",
               "Can you choose the quantity? You should be able to start at 1,000.",
               "Is delivery gradual or immediate? Gradual over hours or days is the safe answer.",
               "What happens if the views drop? There should be a stated policy, not a shrug.",
               "Is there a refill policy? Written, and easy to find.",
               "What payment methods are supported? For Kenya, M-Pesa in shillings.",
               "Is there identifiable customer support? A person, a channel, and a response time.",
               "Does it make unrealistic guarantees? It should not promise subscribers, rankings or going viral.",
               "Does it explain what the service does not guarantee? An honest provider does."
             ]}
          ]
        },
        %{
          id: "good-answers",
          heading: "What the Answers Should Sound Like",
          blocks: [
            {:ul,
             [
               "\"Real accounts on the better grades; a faster source on the cheapest.\"",
               "\"Delivery takes hours to a couple of days.\"",
               "\"If it falls short, we refill the difference.\"",
               "\"M-Pesa, priced in shillings.\"",
               "\"We cannot promise your channel is completely safe — we can promise the source.\""
             ]},
            {:p,
             "That last one matters most. Any provider that dodges the question of what it cannot guarantee is selling you confidence it does not have."}
          ]
        },
        %{
          id: "ask-about-guarantees",
          heading: "Ask What Is Not Guaranteed",
          blocks: [
            {:p,
             "You are not buying subscribers, comments or a ranking. You are buying views, from a stated source, delivered over a stated window. A provider that says so is being straight with you; one that implies more is setting you up for disappointment."}
          ]
        },
        %{
          id: "trial",
          heading: "Start Small, Then Decide",
          blocks: [
            {:p,
             "Whatever anyone promises, the cheapest way to choose is to test: put a small order through, watch how the views arrive, check the retention, and see whether the count holds over the following week. One honest small order tells you more than any sales page."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Compare the providers themselves in the [pillar comparison](/blog/top-youtube-views-providers-kenya), judge quality in [real vs fake YouTube views](/blog/real-vs-fake-youtube-views), or check the [prices](/blog/youtube-views-prices-in-kenya) before you commit."},
            {:cta,
             %{
               text:
                 "Tangi answers all ten questions in the shop — source, grades, delivery, refill and M-Pesa.",
               href: "/shop",
               label: "Check Tangi against the list"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "What is the single most important question to ask a provider?",
          answer:
            "Where the traffic comes from. A provider that names its source can be judged; one that cannot is asking you to trust a number. Everything else — delivery, refill, support — follows from that answer."
        },
        %{
          question: "Should I buy a small order first?",
          answer:
            "Yes. The smallest order a provider allows is the cheapest due diligence there is: it shows you the delivery pace, the retention and whether the views persist before you commit to a larger number."
        }
      ]
    }
  end

  # --------------------------------------------------- spoke: top 10

  defp top_ten do
    %Post{
      slug: "top-10-youtube-views-providers-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Top 10",
      title: "Top 10 YouTube Views Providers in Kenya",
      meta_title: "Top 10 YouTube Views Providers in Kenya (Compared)",
      description:
        "The ten kinds of YouTube views provider you can buy from in Kenya, ranked for a Kenyan creator paying by M-Pesa — price, delivery, traffic quality and what to watch out for.",
      keywords: [
        "top 10 YouTube views providers in Kenya",
        "best YouTube views providers in Kenya",
        "YouTube views companies Kenya",
        "top YouTube views provider Kenya",
        "ranked YouTube views providers Kenya"
      ],
      intro: [
        "\"Top 10\" usually means ten company names, a star rating and a reason to click the first one. We are not going to do that, because we cannot honestly rank ten businesses we have not audited — and neither can most of the sites that publish those lists. What we can do is describe the ten kinds of provider a Kenyan buyer actually meets, rank them for one specific buyer, and say openly which one is ours.",
        "The buyer we have in mind: a Kenyan creator or small business on a phone, paying by M-Pesa, who wants views that arrive steadily and stay. If that is you, this is the order to consider them in."
      ],
      sections: top_ten_sections(),
      faqs: [
        %{
          question: "Which is the best YouTube views provider in Kenya?",
          answer:
            "It depends what you value most. Ours, Tangi, is built for a Kenyan buyer who wants M-Pesa and local support; a global panel is cheaper if you can pay in dollars; an agency is better if you want a campaign rather than views. Judge any of them on source, delivery, retention and support — not on the headline price."
        },
        %{
          question: "Are these ten providers ranked?",
          answer:
            "They are ranked provider profiles, not named companies — we cannot verify another business's traffic or results, so we describe the kinds of provider and rank them for one buyer. Tangi is the only named entry, and it is ours."
        },
        %{
          question: "Which provider will not lose my views?",
          answer:
            "None can guarantee it. The best protection is real traffic delivered gradually, with a refill if delivery falls short — the opposite of an instant burst from a cheap source."
        },
        %{
          question: "Can I buy from a global panel using M-Pesa?",
          answer:
            "Usually not — most want a card, PayPal or crypto in dollars. If M-Pesa is how you pay, that alone narrows the list to local providers."
        }
      ]
    }
  end

  defp top_ten_sections do
    [
      %{
        id: "how-we-ranked",
        heading: "How We Ranked This List",
        blocks: [
          {:p,
           "We ranked provider profiles — not companies — for fit against one buyer, on four things: how easy it is to pay from Kenya, how honest the traffic source is likely to be, whether the views tend to stay, and whether there is anyone to hold to account when something goes wrong."},
          {:callout,
           "No paid placements, and no third-party business is named and rated here — we cannot verify other companies' traffic or results, so we describe what each kind of provider is. The one exception is number one, which is ours, and it is labelled as such."},
          {:p,
           "That is more useful than a fake ranking, and it is the only honest version of this article."}
        ]
      },
      %{
        id: "the-ten",
        heading: "The Ten Provider Profiles",
        blocks: [
          {:h3, "1. Tangi — the local shop (ours)"},
          {:p,
           "Profile: a Kenyan shop selling YouTube views priced in shillings, paid by M-Pesa, in three grades — Cheap, Moderate and Quality. Real accounts on the better grades, delivered gradually over hours or days, with a refill when delivery falls short."},
          {:ul,
           [
             "Best for: a Kenyan creator on a phone who wants M-Pesa and someone local to hold to account.",
             "Price: from about KSh 240 per 1,000 views.",
             "Watch out: we sell views only — not subscribers or comments — and we are not the absolute cheapest per 1,000."
           ]},
          {:h3, "2. Large global self-service panels"},
          {:p,
           "Profile: automated platforms with hundreds of services, priced in dollars and paid by card, PayPal or crypto. Most deliver almost instantly, and support is a ticket queue in another time zone."},
          {:ul,
           [
             "Best for: buyers who already know panels, can pay in dollars and want the lowest price per 1,000.",
             "Price: the cheapest per 1,000 anywhere.",
             "Watch out: mixed traffic quality, instant delivery is the most easily filtered, and little you can do if an order goes wrong."
           ]},
          {:h3, "3. Local generalist social-media shops"},
          {:p,
           "Profile: Kenyan shops selling followers, likes, comments and views as bundles, paid by M-Pesa. They rarely state where the views come from."},
          {:ul,
           [
             "Best for: convenience, when you want several things at once.",
             "Price: low to mid, in shillings.",
             "Watch out: an unstated source, and bundles that often include bot engagement, which carries more risk than views alone."
           ]},
          {:h3, "4. Social-media marketing agencies"},
          {:p,
           "Profile: agencies that sell promotion campaigns — content, ad management and reporting — invoiced in shillings. They generally do not sell raw views."},
          {:ul,
           [
             "Best for: businesses that want a campaign run for them rather than a number.",
             "Price: the highest per outcome, because you are paying for strategy and people.",
             "Watch out: results depend on the creative, and you are not buying a guaranteed view count."
           ]},
          {:h3, "5. Freelance resellers on WhatsApp and Instagram"},
          {:p,
           "Profile: individuals reselling a panel from their phone, priced in shillings and paid by M-Pesa. The most common provider you will meet, and the least accountable."},
          {:ul,
           [
             "Best for: a quick, cheap order from someone you already know and trust.",
             "Price: cheap.",
             "Watch out: the source is unknown, there is usually no policy, and there is no recourse if the order fails or the views drop."
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
          {:h3, "7. Music and artist promotion services"},
          {:p,
           "Profile: services aimed at musicians, bundling views with playlist pushes, blog placements and distribution."},
          {:ul,
           [
             "Best for: an artist launching a single who wants a coordinated push.",
             "Price: mid to high, often as a package.",
             "Watch out: claims about playlist placements and guaranteed reach are frequently inflated; ask what is paid placement and what is organic."
           ]},
          {:h3, "8. Influencer and creator networks"},
          {:p,
           "Profile: they put your video in front of a network of real creators' audiences, so the reach is genuine but the volume is modest."},
          {:ul,
           [
             "Best for: relevant, trusting viewers rather than a bare number.",
             "Price: higher per viewer, negotiated.",
             "Watch out: it is reach, not views; relevance depends entirely on matching the audience to your topic."
           ]},
          {:h3, "9. YouTube Ads management services"},
          {:p,
           "Profile: agencies and freelancers who run Google Ads for your video, billed in shillings or dollars, with real targeting and reporting."},
          {:ul,
           [
             "Best for: measurable outcomes — clicks, leads, sales.",
             "Price: the most expensive route, because you pay for the ads and the management.",
             "Watch out: it is the advertising route, not views, and it needs a video that converts to be worth it."
           ]},
          {:h3, "10. White-label resellers bundling views, likes and watch time"},
          {:p,
           "Profile: sellers offering views, likes and watch hours as one package, usually near an instant delivery."},
          {:ul,
           [
             "Best for: someone trying to look maximally established in one order.",
             "Price: cheap per item.",
             "Watch out: this is the riskiest bundle there is. Watch time and likes from the same cheap source as the views are exactly what gets a video's reach limited — treat it as a last option, if at all."
           ]}
        ]
      },
      %{
        id: "side-by-side",
        heading: "The Ten, Side by Side",
        blocks: [
          {:p, "The same ten profiles, at a glance:"},
          {:table,
           %{
             head: ["Provider type", "Price", "Payment", "Delivery", "Watch out"],
             rows: [
               [
                 "Tangi (ours)",
                 "From ~KSh 240/1k",
                 "M-Pesa",
                 "Gradual",
                 "Views only; not the cheapest"
               ],
               [
                 "Global panels",
                 "Cheapest, USD",
                 "Card/PayPal",
                 "Near-instant",
                 "Mixed traffic; little support"
               ],
               [
                 "Local shops",
                 "Low–mid, KES",
                 "M-Pesa",
                 "Varies",
                 "Source unstated; bot bundles"
               ],
               ["Agencies", "Highest", "Invoice/M-Pesa", "Scheduled", "Strategy, not raw views"],
               ["Freelancers", "Cheap", "M-Pesa", "Uneven", "Unknown source; no recourse"],
               [
                 "Marketplaces",
                 "Panel price, USD",
                 "Card",
                 "The panel's",
                 "Affiliate reviews; no delivery"
               ],
               [
                 "Music services",
                 "Mid–high",
                 "M-Pesa/invoice",
                 "Packaged",
                 "Inflated placement claims"
               ],
               [
                 "Creator networks",
                 "High per viewer",
                 "Negotiated",
                 "Moderate",
                 "Reach, not views"
               ],
               [
                 "Ads managers",
                 "Highest",
                 "KES/USD",
                 "Paced",
                 "Ads, not views; needs a converter"
               ],
               [
                 "Bundlers",
                 "Cheap per item",
                 "M-Pesa",
                 "Near-instant",
                 "Watch time + likes are risky"
               ]
             ]
           }},
          {:p,
           "Read the last column as the whole point of the table. Every provider is cheap at something and expensive at something else."}
        ]
      },
      %{
        id: "how-to-use",
        heading: "How to Use This List",
        blocks: [
          {:p, "Use the list as a filter, not a shopping cart:"},
          {:ol,
           [
             "Decide what you are buying: views for momentum, or a campaign with outcomes.",
             "Cut the list to the providers that take M-Pesa, if that is how you pay.",
             "Check the traffic source and the refill policy before the price.",
             "Start with the smallest order and watch how it behaves.",
             "Scale only once it did what it promised."
           ]},
          {:p,
           "If you only take one step, take the third one — the [provider checklist](/blog/how-to-choose-a-youtube-views-provider) is that step, written out. And read [real vs fake YouTube views](/blog/real-vs-fake-youtube-views) so you know what you are looking at when the order lands."}
        ]
      },
      %{
        id: "next",
        heading: "Where to Go Next",
        toc: false,
        blocks: [
          {:p,
           "This list is a spoke of our [comparison of YouTube views providers in Kenya](/blog/top-youtube-views-providers-kenya). To go deeper, see [where to buy](/blog/best-sites-to-buy-youtube-views-in-kenya), [what it costs](/blog/youtube-views-prices-in-kenya), or [the whole buying guide](/blog/buy-youtube-views-kenya)."},
          {:cta,
           %{
             text:
               "Tangi is number one on this list because it is ours — judge it against the same checklist as everyone else.",
             href: "/shop",
             label: "Check Tangi against the list"
           }}
        ]
      }
    ]
  end
end
