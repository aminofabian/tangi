defmodule ViewNinjas.Blog.Clusters.BuyDataBundlesKenya do
  @moduledoc """
  The "buy data bundles in Kenya" cluster: one pillar and thirteen spokes.

  This is an **informational** cluster, not a product one. Tangi sells airtime, not
  data bundles (`docs/instalipa-airtime.md` §16 puts bundles out of scope), so
  nothing here claims otherwise: the pages describe how the Kenyan market works,
  and every call to action points at airtime or the shop.

  That constraint shapes the copy. There are **no prices** anywhere — bundle
  prices and validity periods change constantly, so a figure written here would be
  wrong within a month. Instead the guides teach the durable parts: how a bundle
  differs from airtime, how to choose by cost per gigabyte, how to buy for another
  number, and how daily, weekly and monthly validity change the maths.

  ## The cluster

      pillar  buy-data-bundles-kenya
        │
        ├── networks:  buy-safaricom-data-bundles · buy-airtel-data-bundles
        │              buy-telkom-data-bundles · buy-faiba-data-bundles
        ├── methods:   buy-safaricom-data-with-mpesa · buy-airtel-data-with-mpesa
        │              buy-data-bundles-online-kenya
        ├── audience:  buy-data-bundles-for-another-number
        ├── validity:  daily-data-bundles-kenya · weekly-data-bundles-kenya
        │              monthly-data-bundles-kenya
        └── compare:   best-data-bundles-kenya · cheapest-data-bundles-kenya

  Like the airtime cluster, every spoke links back up to the pillar and the pillar
  links down to every spoke, so a crawler that lands anywhere can reach the set.
  """

  alias ViewNinjas.Blog.{Cluster, Post}

  @cluster "buy-data-bundles-kenya"
  @updated ~D[2026-10-01]

  @doc "The cluster's own metadata."
  @spec cluster() :: Cluster.t()
  def cluster do
    %Cluster{
      slug: @cluster,
      eyebrow: "Data in Kenya",
      title: "Buy Data Bundles in Kenya",
      keyword: "buy data bundles in Kenya",
      description:
        "How to buy data bundles in Kenya for Safaricom, Airtel, Telkom and Faiba — online, by USSD, with M-Pesa, for another number, and how to compare them."
    }
  end

  @doc "Every post in the cluster, pillar first."
  @spec posts() :: [Post.t()]
  def posts do
    [
      pillar(),
      safaricom(),
      airtel(),
      telkom(),
      faiba(),
      safaricom_mpesa(),
      airtel_mpesa(),
      online(),
      for_another_number(),
      daily(),
      weekly(),
      monthly(),
      best(),
      cheapest()
    ]
  end

  # ------------------------------------------------------------------ pillar

  defp pillar do
    %Post{
      slug: @cluster,
      cluster: @cluster,
      kind: :pillar,
      updated_on: @updated,
      eyebrow: "Complete guide",
      title: "Buy Data Bundles in Kenya: Safaricom, Airtel, Telkom & Faiba",
      meta_title: "Buy Data Bundles in Kenya — Safaricom, Airtel, Telkom & Faiba",
      description:
        "How to buy data bundles in Kenya on Safaricom, Airtel, Telkom and Faiba — online, by USSD, with M-Pesa and for another number, and how to compare them.",
      keywords: [
        "buy data bundles in Kenya",
        "buy data bundles Kenya",
        "data bundles Kenya",
        "internet bundles Kenya",
        "buy data online Kenya",
        "buy bundles with M-Pesa",
        "buy data bundles for another number",
        "daily data bundles Kenya",
        "monthly data bundles Kenya",
        "data bundle offers Kenya"
      ],
      intro: [
        "A data bundle is how most Kenyans buy internet: you pay for a set amount of data with a set validity — a day, a week, a month — and it expires whether you used it or not. Safaricom, Airtel, Telkom and Faiba all sell bundles, and the idea is the same on each; the bundles, the prices and the validity periods are not.",
        "This guide covers how to buy data bundles in Kenya on every network, the channels that sell them — the network app, USSD, a website, an agent — and the choices that decide whether you get value: validity, all-network versus social bundles, and how to compare by cost per gigabyte."
      ],
      sections: pillar_sections(),
      faqs: pillar_faqs()
    }
  end

  defp pillar_sections do
    [
      %{
        id: "how-bundles-work",
        heading: "How Data Bundles Work in Kenya",
        blocks: [
          {:p,
           "A bundle buys three things at once: a volume of data, a validity period, and sometimes a restriction on what that data can be used for. A 1 GB daily bundle and a 1 GB monthly bundle hold the same data; what differs is how long you have to use it."},
          {:p,
           "Two consequences follow, and they explain most of the frustration people have with bundles. First, unused data expires — a daily bundle you do not finish is gone at the end of the day, not carried over. Second, a bundle is not airtime: airtime is a shilling balance you can spend on anything, while a bundle only gives data, and that data does not convert back to airtime."},
          {:callout,
           "Bundle prices and validity periods change often. Treat any figure you see as a starting point and confirm the current price on the network before you buy."}
        ]
      },
      %{
        id: "ways-to-buy",
        heading: "The Ways to Buy Data Bundles in Kenya",
        blocks: [
          {:p,
           "Four channels sell bundles, and they differ in two ways that matter: whether they need data to use, and whether they can serve a number that is not your own."},
          {:table,
           %{
             head: [
               "Channel",
               "Your own number",
               "Another number",
               "Needs data",
               "Pay with M-Pesa"
             ],
             rows: [
               ["Network app (mySafaricom, Airtel, etc.)", "Yes", "Often", "Yes", "Varies"],
               ["USSD menu", "Yes", "Sometimes", "No", "Varies"],
               ["Bundle or airtime website", "Yes", "Yes", "Yes", "Yes"],
               ["Shop or agent", "Yes", "Yes", "No", "Varies"]
             ]
           }},
          {:p,
           "The route you pick comes down to two questions: is the number yours, and do you have data to reach the channel in the first place?"}
        ]
      },
      %{
        id: "safaricom",
        heading: "Buy Safaricom Data Bundles",
        blocks: [
          {:p,
           "Safaricom is Kenya's largest network, so most searches for data bundles in Kenya start here. Bundles are bought in the mySafaricom app, through the network's data menu over USSD, on a bundle website, or from an agent — and Safaricom's own mobile money means paying is rarely the awkward part."},
          {:p,
           "The detail — channels, buying for another Safaricom number, and choosing a bundle — is in [buy Safaricom data bundles](/blog/buy-safaricom-data-bundles)."}
        ]
      },
      %{
        id: "airtel",
        heading: "Buy Airtel Data Bundles",
        blocks: [
          {:p,
           "Airtel competes largely on bundle value, so its offers change often and are worth checking rather than assuming. Bundles come through the Airtel app, the network's USSD menu, Airtel Money, or a third-party website that carries Airtel."},
          {:p,
           "See [buy Airtel data bundles](/blog/buy-airtel-data-bundles) for the channels and the choices."}
        ]
      },
      %{
        id: "telkom",
        heading: "Buy Telkom Data Bundles",
        blocks: [
          {:p,
           "Telkom bundles are bought through Telkom's own app and menus, through T-Kash, and through services that carry Telkom. Telkom's bundles have their own shape, so it is worth confirming what a given bundle covers before you buy."},
          {:p, "More in [buy Telkom data bundles](/blog/buy-telkom-data-bundles)."}
        ]
      },
      %{
        id: "faiba",
        heading: "Buy Faiba Data Bundles",
        blocks: [
          {:p,
           "Faiba, run by JTL, sells mobile bundles through its own app and channels, alongside its fixed home internet. Faiba lines are less common than Safaricom's, so if you are buying through a general website, check that it carries Faiba before you pay."},
          {:p, "Details are in [buy Faiba data bundles](/blog/buy-faiba-data-bundles)."}
        ]
      },
      %{
        id: "mpesa",
        heading: "Buying Data Bundles With M-Pesa",
        blocks: [
          {:p,
           "M-Pesa is Kenya's default way to move money, and it is a common way to pay for a bundle bought somewhere other than the network's own menu: you choose the bundle on a website or app, and pay the total in shillings with M-Pesa."},
          {:p,
           "The Safaricom-specific path — bundles bought inside Safaricom's own channels and paid from M-Pesa — is in [buy Safaricom data with M-Pesa](/blog/buy-safaricom-data-with-mpesa). Paying a service with M-Pesa to buy Airtel data is in [buy Airtel data with M-Pesa](/blog/buy-airtel-data-with-mpesa)."}
        ]
      },
      %{
        id: "online",
        heading: "Buying Data Bundles Online",
        blocks: [
          {:p,
           "Buying online means you are not tied to one network: you pick the network, the bundle and the number, and pay — usually with M-Pesa. It is the fastest route when the number belongs to someone else, or when you are buying for more than one line."},
          {:p,
           "The general walkthrough is in [buy data bundles online in Kenya](/blog/buy-data-bundles-online-kenya)."}
        ]
      },
      %{
        id: "for-someone",
        heading: "Buying Data Bundles for Another Number",
        blocks: [
          {:p,
           "Top-up is a normal way to keep someone online — a student, a househelp, a boda rider — and most online channels let you enter a recipient number rather than only your own. The one thing to get right is the bundle: a social bundle bought for someone who needs general browsing is money wasted."},
          {:p,
           "The full guide is [buy data bundles for another number](/blog/buy-data-bundles-for-another-number)."}
        ]
      },
      %{
        id: "validity",
        heading: "Daily, Weekly and Monthly Bundles",
        blocks: [
          {:p,
           "Validity is the quietest and most expensive choice in bundles. A short bundle is cheap up front but wastes data if you do not finish it; a long bundle carries you through but ties up more money and can leave data stranded if you run out early anyway."},
          {:p,
           "The rule of thumb: match validity to how steadily you use data. Heavy but uneven days suit [daily bundles](/blog/daily-data-bundles-kenya); a fairly steady week suits [weekly bundles](/blog/weekly-data-bundles-kenya); a line used every day suits [monthly bundles](/blog/monthly-data-bundles-kenya)."}
        ]
      },
      %{
        id: "compare",
        heading: "How to Compare Bundles Without Getting Burned",
        blocks: [
          {:p,
           "Bundles are not compared by headline price, because a bundle is data *and* time. The fair comparison is cost per gigabyte — the price divided by the data you actually get — and then whether the validity suits you."},
          {:ul,
           [
             "Cost per GB first: a cleverly marketed bundle can be worse per gigabyte than a plain one.",
             "Check the validity: a cheap large bundle that expires in a day is only cheap if you use it in a day.",
             "Check what it covers: social or app-specific bundles are cheap because they exclude general browsing.",
             "Check auto-renew: a bundle that renews itself is convenient until you forget it is on.",
             "Check the network: bundles are usually tied to the sim they were bought for."
           ]},
          {:p,
           "For the frameworks in full, see [the best data bundles in Kenya](/blog/best-data-bundles-kenya) and [the cheapest data bundles in Kenya](/blog/cheapest-data-bundles-kenya)."}
        ]
      },
      %{
        id: "tangi",
        heading: "A Note on Tangi",
        blocks: [
          {:p,
           "Tangi sells airtime, not data bundles — so this cluster is a buyer's guide to the Kenyan market rather than a shop for bundles. We keep it because bundle-or-airtime is the choice every Kenyan phone user makes, and because the same questions (another number, M-Pesa, validity) decide both."},
          {:p,
           "When you want airtime for any Kenyan line, that is what Tangi does: see [buy airtime in Kenya](/blog/buy-airtime-kenya)."}
        ]
      },
      %{
        id: "next",
        heading: "Where to Start",
        toc: false,
        blocks: [
          {:p,
           "Pick the network you are buying for, the way you want to pay, or the validity you need, from the guides above. Not sure where to begin? [The best data bundles in Kenya](/blog/best-data-bundles-kenya) and [the cheapest](/blog/cheapest-data-bundles-kenya) are the comparison pages. For the airtime side of the same market, see [buy airtime in Kenya](/blog/buy-airtime-kenya)."},
          {:cta,
           %{
             text:
               "Buying airtime rather than a bundle? Tangi tops up any Kenyan line — face value, paid with M-Pesa, delivered in seconds.",
             href: "/airtime",
             label: "Buy airtime"
           }}
        ]
      }
    ]
  end

  defp pillar_faqs do
    [
      %{
        question: "What is a data bundle in Kenya?",
        answer:
          "A set amount of mobile data with a validity period — for example 1 GB valid for a day. It expires at the end of that period, used or not, so a bundle is data plus time."
      },
      %{
        question: "Can I buy data bundles for another number in Kenya?",
        answer:
          "Often, yes. Network apps and bundle websites usually let you enter a recipient number, and some USSD menus do too. Check that the channel carries the recipient's network before you pay."
      },
      %{
        question: "Do data bundles expire?",
        answer:
          "Usually, yes. A daily bundle ends at the end of the day and a monthly bundle at the end of its period, and unused data is generally not carried over. Some bundles are sold as no-expiry — check before assuming."
      },
      %{
        question: "What is the difference between airtime and a data bundle?",
        answer:
          "Airtime is a shilling balance you can spend on anything, including occasional data. A bundle is a fixed allowance of data for a set period, and it is usually far cheaper per gigabyte than using airtime."
      },
      %{
        question: "What is the cheapest way to buy data in Kenya?",
        answer:
          "Per gigabyte, a bundle is almost always cheaper than spending airtime. Beyond that, the cheapest bundle is the one sized to how you actually use data — an oversized bundle you do not finish is money wasted."
      },
      %{
        question: "Can I buy data bundles with M-Pesa?",
        answer:
          "On bundle and airtime websites, yes — you pay in shillings with M-Pesa and the bundle is sent to the number. Some network channels also let you pay from M-Pesa."
      },
      %{
        question: "Do I need data to buy a data bundle?",
        answer:
          "Not if you use USSD, which works over the network signal alone. Apps and websites need a connection to reach them."
      },
      %{
        question: "Why does my bundle finish faster than expected?",
        answer:
          "Usually background apps, video or automatic updates. Bundle size and how you use data decide this — the daily, weekly and monthly guides explain how to size a bundle to your habits."
      }
    ]
  end

  # ------------------------------------------------------ spoke: Safaricom

  defp safaricom do
    %Post{
      slug: "buy-safaricom-data-bundles",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Safaricom",
      title: "Buy Safaricom Data Bundles in Kenya",
      meta_title: "Buy Safaricom Data Bundles in Kenya — App, USSD & M-Pesa",
      description:
        "How to buy Safaricom data bundles in Kenya — in the mySafaricom app, over USSD, on a website, and for another Safaricom number, and how to choose one.",
      keywords: [
        "buy Safaricom data bundles",
        "buy Safaricom bundles",
        "Safaricom data bundles Kenya",
        "Safaricom bundles online",
        "mySafaricom data bundles",
        "buy Safaricom data"
      ],
      intro: [
        "Safaricom is Kenya's largest network, so its bundles are the ones most people buy first. A Safaricom bundle is bought through Safaricom's own channels or through a service that carries Safaricom, and it is tied to the Safaricom line you are topping up.",
        "This page covers the channels, buying for another Safaricom number, and the choices that decide whether a bundle is good value."
      ],
      sections: [
        %{
          id: "channels",
          heading: "How to Buy Safaricom Bundles",
          blocks: [
            {:p, "Safaricom bundles are sold through four routes:"},
            {:ul,
             [
               "The mySafaricom app: the clearest way, and it will show you the current bundles and their validity.",
               "The Safaricom data menu over USSD: works with no data bundle, which matters when you are out of data and need to buy more.",
               "A bundle or airtime website that carries Safaricom, paid with M-Pesa.",
               "An agent or shop, if you would rather buy in person."
             ]},
            {:p,
             "Safaricom's own mobile money means paying is rarely the hard part: M-Pesa is how the money moves on Safaricom's channels, and it is how you pay a website that sells Safaricom bundles."}
          ]
        },
        %{
          id: "another-number",
          heading: "Buying Bundles for Another Safaricom Number",
          blocks: [
            {:p,
             "You can top up a Safaricom line that is not your own — the app and websites usually let you enter a recipient number rather than only your own. Check the number carefully before you pay: a bundle sent to the wrong line cannot be recalled."},
            {:p,
             "If the person you are buying for is on a different network, a bundle bought for Safaricom will not help them. Bundles are tied to the network they were sold for."}
          ]
        },
        %{
          id: "choose",
          heading: "Choosing a Safaricom Bundle",
          blocks: [
            {:ul,
             [
               "Validity first: a daily, weekly or monthly bundle of the same size is the same data for a different length of time — pick the one that matches how steadily you use it.",
               "Check what it covers: some bundles are limited to specific apps or social media, and those do not cover general browsing.",
               "Compare cost per gigabyte, not headline price, when two bundles look similar.",
               "Watch auto-renew: a bundle that renews itself is convenient until you forget it is on."
             ]},
            {:p,
             "For the wider comparison, see [the best data bundles in Kenya](/blog/best-data-bundles-kenya) and [the cheapest](/blog/cheapest-data-bundles-kenya)."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or compare another network: [Airtel](/blog/buy-airtel-data-bundles), [Telkom](/blog/buy-telkom-data-bundles) or [Faiba](/blog/buy-faiba-data-bundles)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How do I buy Safaricom data bundles?",
          answer:
            "Through the mySafaricom app, the Safaricom data menu over USSD, a bundle website paid with M-Pesa, or an agent. The app is the clearest because it shows current bundles and validity."
        },
        %{
          question: "Can I buy Safaricom bundles for another number?",
          answer:
            "Usually, yes — the app and bundle websites let you enter a recipient number. The bundle is tied to the Safaricom line you name, so check the number before paying."
        },
        %{
          question: "Can I buy Safaricom bundles without data?",
          answer:
            "Yes, over USSD — the network's data menu runs on the signal alone, so you can top up even when you have no data left."
        }
      ]
    }
  end

  # --------------------------------------------------------- spoke: Airtel

  defp airtel do
    %Post{
      slug: "buy-airtel-data-bundles",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Airtel",
      title: "Buy Airtel Data Bundles in Kenya",
      meta_title: "Buy Airtel Data Bundles in Kenya — App, USSD & Airtel Money",
      description:
        "How to buy Airtel data bundles in Kenya — in the Airtel app, over USSD, with Airtel Money or a website paid by M-Pesa, and how to choose a bundle.",
      keywords: [
        "buy Airtel data bundles",
        "buy Airtel bundles",
        "Airtel data bundles Kenya",
        "Airtel bundles online",
        "Airtel data bundles",
        "buy Airtel data"
      ],
      intro: [
        "Airtel competes in Kenya largely on bundle value, which is good news if you shop around — and a reason to check current offers rather than assume. Bundles are tied to the Airtel line you are topping up.",
        "This page covers the channels, buying for another Airtel number, and how to tell a good Airtel bundle from a marketed one."
      ],
      sections: [
        %{
          id: "channels",
          heading: "How to Buy Airtel Bundles",
          blocks: [
            {:ul,
             [
               "The Airtel app: buy for your own line, and often for another Airtel number.",
               "The Airtel USSD menu: works with no data, so it is the fallback when you are out.",
               "Airtel Money: Airtel's own mobile money, used to pay for bundles inside Airtel's channels.",
               "A bundle or airtime website that carries Airtel, usually paid with M-Pesa."
             ]},
            {:p,
             "Because Airtel's offers move often, the app and the network's own pages are the honest source for what is available today, rather than any list written in advance."}
          ]
        },
        %{
          id: "another-number",
          heading: "Buying Bundles for Another Airtel Number",
          blocks: [
            {:p,
             "You can buy for another Airtel line — enter the recipient number on the app or a website rather than your own. A bundle bought for Airtel will not work on a Safaricom, Telkom or Faiba line, so match the network to the recipient."},
            {:p,
             "Read the number back before you confirm. A bundle that lands on the wrong line is not refunded."}
          ]
        },
        %{
          id: "choose",
          heading: "Choosing an Airtel Bundle",
          blocks: [
            {:ul,
             [
               "Compare cost per gigabyte, not the headline price.",
               "Check the validity: the same data over a day and over a month are very different offers.",
               "Check whether the bundle covers everything or only certain apps.",
               "Check whether it auto-renews, so you are not paying for a bundle you forgot about."
             ]},
            {:p,
             "The comparison frameworks are in [the best data bundles in Kenya](/blog/best-data-bundles-kenya)."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or jump to [Safaricom](/blog/buy-safaricom-data-bundles), [Telkom](/blog/buy-telkom-data-bundles) or [Faiba](/blog/buy-faiba-data-bundles)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How do I buy Airtel data bundles in Kenya?",
          answer:
            "Through the Airtel app, the Airtel USSD menu, Airtel Money, or a bundle website that carries Airtel and takes M-Pesa."
        },
        %{
          question: "Can I buy Airtel bundles for another number?",
          answer:
            "Yes, usually through the app or a website — enter the recipient's Airtel number. The bundle will not work on another network's line."
        },
        %{
          question: "Why check Airtel bundles often?",
          answer:
            "Airtel changes its bundle offers frequently, so the current price and validity in the app matter more than any figure written down earlier."
        }
      ]
    }
  end

  # --------------------------------------------------------- spoke: Telkom

  defp telkom do
    %Post{
      slug: "buy-telkom-data-bundles",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Telkom",
      title: "Buy Telkom Data Bundles in Kenya",
      meta_title: "Buy Telkom Data Bundles in Kenya — App, USSD & T-Kash",
      description:
        "How to buy Telkom data bundles in Kenya — through the Telkom app and menus, with T-Kash, or on a website that carries Telkom, and how to choose one.",
      keywords: [
        "buy Telkom data bundles",
        "buy Telkom bundles",
        "Telkom data bundles Kenya",
        "Telkom bundles online",
        "Telkom data bundles",
        "T-Kash data bundles"
      ],
      intro: [
        "Telkom sells its bundles through its own app and menus, and through services that carry the network. Telkom also runs T-Kash, its mobile money, which is how many Telkom customers pay.",
        "This page covers the channels, buying for another Telkom number, and what to check in a Telkom bundle."
      ],
      sections: [
        %{
          id: "channels",
          heading: "How to Buy Telkom Bundles",
          blocks: [
            {:ul,
             [
               "The Telkom app: buy for your own line, and for another Telkom number where the app allows it.",
               "The Telkom USSD menu: for when you have no data.",
               "T-Kash, Telkom's mobile money: top up and pay for bundles inside Telkom's own channels.",
               "A bundle or airtime website that carries Telkom, usually paid with M-Pesa."
             ]},
            {:p,
             "Telkom bundles are tied to Telkom lines, so a bundle bought here will not top up a Safaricom, Airtel or Faiba number."}
          ]
        },
        %{
          id: "another-number",
          heading: "Buying Bundles for Another Telkom Number",
          blocks: [
            {:p,
             "As with the other networks, you can usually buy for another Telkom line by entering the recipient's number rather than your own. Confirm the number before you pay — a delivered bundle is not recalled."}
          ]
        },
        %{
          id: "choose",
          heading: "Choosing a Telkom Bundle",
          blocks: [
            {:ul,
             [
               "Check the validity — daily, weekly and monthly change the value of the same amount of data.",
               "Check what the bundle covers, especially if it is marketed as a social or app bundle.",
               "Compare cost per gigabyte against other networks' bundles if the line is yours to choose."
             ]},
            {:p,
             "See [the best data bundles in Kenya](/blog/best-data-bundles-kenya) for how to compare across networks."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or read [Safaricom](/blog/buy-safaricom-data-bundles), [Airtel](/blog/buy-airtel-data-bundles) or [Faiba](/blog/buy-faiba-data-bundles)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How do I buy Telkom data bundles?",
          answer:
            "Through the Telkom app, the Telkom USSD menu, T-Kash, or a bundle website that carries Telkom and takes M-Pesa."
        },
        %{
          question: "What is T-Kash?",
          answer:
            "T-Kash is Telkom's mobile money service. Telkom customers use it to top up and to pay for bundles inside Telkom's channels."
        },
        %{
          question: "Can I buy Telkom bundles for another number?",
          answer:
            "Yes, usually by entering the recipient's Telkom number instead of your own. The bundle works only on a Telkom line."
        }
      ]
    }
  end

  # ---------------------------------------------------------- spoke: Faiba

  defp faiba do
    %Post{
      slug: "buy-faiba-data-bundles",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Faiba",
      title: "Buy Faiba Data Bundles in Kenya",
      meta_title: "Buy Faiba Data Bundles in Kenya — App, USSD & JTL",
      description:
        "How to buy Faiba data bundles in Kenya — through JTL's Faiba app and channels, and on a website that carries Faiba, plus how to choose one.",
      keywords: [
        "buy Faiba data bundles",
        "buy Faiba bundles",
        "Faiba data bundles Kenya",
        "Faiba bundles online",
        "JTL Faiba bundles",
        "buy Faiba data"
      ],
      intro: [
        "Faiba is the mobile brand of JTL, and it sits alongside JTL's fixed home internet. Faiba bundles are bought through JTL's own app and channels, and through services that carry Faiba.",
        "This page covers the channels, buying for another Faiba number, and what to check before you buy."
      ],
      sections: [
        %{
          id: "channels",
          heading: "How to Buy Faiba Bundles",
          blocks: [
            {:ul,
             [
               "The Faiba app, run by JTL: buy for your own Faiba line, and for another line where the app allows it.",
               "JTL's USSD and self-service menus: the fallback when you have no data.",
               "A bundle or airtime website that carries Faiba, usually paid with M-Pesa.",
               "A JTL agent or shop, since Faiba has fewer outlets than the large networks."
             ]},
            {:p,
             "Faiba lines are less common than Safaricom's, so if you are buying on a general website, confirm it carries Faiba before you pay — not every service does."}
          ]
        },
        %{
          id: "home-vs-mobile",
          heading: "Faiba Mobile Bundles and Faiba Home Internet",
          blocks: [
            {:p,
             "JTL sells both mobile bundles and fixed home internet under the Faiba name, and they are different products with different buying routes. If you are topping up a phone line, you want a Faiba mobile bundle; the home internet is set up as a fixed line, not a phone top-up."}
          ]
        },
        %{
          id: "choose",
          heading: "Choosing a Faiba Bundle",
          blocks: [
            {:ul,
             [
               "Check the validity of the bundle, not just the data size.",
               "Check what it covers, especially for app-specific offers.",
               "Compare cost per gigabyte if the line is yours to move between networks."
             ]},
            {:p,
             "The cross-network frameworks are in [the best data bundles in Kenya](/blog/best-data-bundles-kenya)."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or read [Safaricom](/blog/buy-safaricom-data-bundles), [Airtel](/blog/buy-airtel-data-bundles) or [Telkom](/blog/buy-telkom-data-bundles)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How do I buy Faiba data bundles?",
          answer:
            "Through JTL's Faiba app, JTL's USSD and self-service menus, a website that carries Faiba, or a JTL agent."
        },
        %{
          question: "Is Faiba mobile the same as Faiba home internet?",
          answer:
            "No. They are both JTL products, but a phone top-up is a mobile bundle and the home internet is a fixed line set up separately."
        },
        %{
          question: "Does every bundle website sell Faiba?",
          answer:
            "No. Faiba is less widely carried than Safaricom or Airtel, so check that a service supports Faiba before you pay."
        }
      ]
    }
  end

  # ------------------------------------------- spoke: Safaricom data + M-Pesa

  defp safaricom_mpesa do
    %Post{
      slug: "buy-safaricom-data-with-mpesa",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "M-Pesa",
      title: "Buy Safaricom Data With M-Pesa in Kenya",
      meta_title: "Buy Safaricom Data With M-Pesa in Kenya",
      description:
        "How to pay for Safaricom data bundles with M-Pesa in Kenya — on a website or a channel that takes M-Pesa, and what to check before you confirm.",
      keywords: [
        "buy Safaricom data with M-Pesa",
        "Safaricom bundles M-Pesa",
        "pay for Safaricom data with M-Pesa",
        "Safaricom data M-Pesa",
        "buy Safaricom bundles online"
      ],
      intro: [
        "M-Pesa is Safaricom's own mobile money, so paying for Safaricom data with M-Pesa is the natural combination. There are two ways it happens: inside Safaricom's own channels, where M-Pesa is the money rail, and on a website that sells Safaricom bundles and takes M-Pesa.",
        "This page explains the mechanism and the handful of things worth checking before you confirm."
      ],
      sections: [
        %{
          id: "how",
          heading: "How Paying With M-Pesa Works",
          blocks: [
            {:p,
             "The shape is the same everywhere: you choose the Safaricom bundle for the line you are topping up, the service shows you the total in shillings, and you approve an M-Pesa payment. Once it clears, the bundle is sent to that Safaricom number."},
            {:p,
             "M-Pesa moves the money; the bundle is what you bought. The two are easy to confuse, so keep the confirmation message — it is your receipt for both."}
          ]
        },
        %{
          id: "channels",
          heading: "Where You Can Pay With M-Pesa",
          blocks: [
            {:ul,
             [
               "Inside Safaricom's own app and menus, where M-Pesa is part of the flow.",
               "On a bundle or airtime website that carries Safaricom and lists M-Pesa as a payment option.",
               "Through a shop or agent that accepts M-Pesa."
             ]},
            {:p,
             "Not every channel offers M-Pesa for every purchase, so confirm the payment options shown on the screen you are using rather than assuming."}
          ]
        },
        %{
          id: "watch",
          heading: "What to Check Before You Confirm",
          blocks: [
            {:ul,
             [
               "The number: a bundle sent to the wrong Safaricom line is not refunded.",
               "The bundle: size and validity, since the price alone does not tell you the value.",
               "The total: check whether the channel adds a fee on top of the bundle price.",
               "The receipt: keep the M-Pesa confirmation and the bundle confirmation together."
             ]}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or read [buy Safaricom data bundles](/blog/buy-safaricom-data-bundles) for the channels themselves. For airtime paid with M-Pesa, see [buy airtime with M-Pesa](/blog/buy-airtime-with-mpesa)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy Safaricom data bundles with M-Pesa?",
          answer:
            "Yes — M-Pesa is Safaricom's own mobile money, and it is how you pay inside Safaricom's channels and on websites that carry Safaricom bundles. Check the payment options on the screen you are using."
        },
        %{
          question: "Does paying with M-Pesa add a fee?",
          answer:
            "The bundle price is set by the offer; whether a channel adds a fee on top varies. Look at the total before you approve the M-Pesa payment."
        },
        %{
          question: "Do I need data to pay with M-Pesa?",
          answer:
            "No. M-Pesa works over the USSD menu on the network signal, so you can buy a bundle even when you are out of data."
        }
      ]
    }
  end

  # ---------------------------------------------- spoke: Airtel data + M-Pesa

  defp airtel_mpesa do
    %Post{
      slug: "buy-airtel-data-with-mpesa",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "M-Pesa",
      title: "Buy Airtel Data With M-Pesa in Kenya",
      meta_title: "Buy Airtel Data With M-Pesa in Kenya",
      description:
        "How to buy Airtel data in Kenya and pay with M-Pesa — through a website that carries Airtel, and how that differs from Airtel Money.",
      keywords: [
        "buy Airtel data with M-Pesa",
        "Airtel bundles M-Pesa",
        "pay for Airtel data with M-Pesa",
        "Airtel data M-Pesa",
        "buy Airtel bundles online"
      ],
      intro: [
        "Airtel is not Safaricom, so paying for Airtel data with M-Pesa is a cross-network payment: you use M-Pesa, but the bundle is for an Airtel line. That is common on websites that sell bundles for several networks at once.",
        "This page explains when M-Pesa is the right rail for Airtel data, and how it differs from Airtel's own mobile money."
      ],
      sections: [
        %{
          id: "two-rails",
          heading: "M-Pesa and Airtel Money",
          blocks: [
            {:p,
             "Airtel has its own mobile money, Airtel Money, which is what you use inside Airtel's channels. M-Pesa is the alternative — useful when you are paying a service rather than Airtel itself, or when M-Pesa is simply what you have."},
            {:p,
             "Either way, the money movement is separate from the bundle: paying successfully is not the same as the bundle arriving, so wait for the bundle confirmation."}
          ]
        },
        %{
          id: "how",
          heading: "How to Pay for Airtel Data With M-Pesa",
          blocks: [
            {:ol,
             [
               "Choose Airtel as the network and pick the bundle and validity you want.",
               "Enter the Airtel number you are topping up — yours or someone else's.",
               "Choose M-Pesa as the payment method and approve the payment.",
               "Wait for the bundle confirmation, and keep both messages as your receipt."
             ]}
          ]
        },
        %{
          id: "watch",
          heading: "What to Check",
          blocks: [
            {:ul,
             [
               "That the service actually carries Airtel — many bundle websites do, but not all.",
               "The number, because an Airtel bundle sent to the wrong line is not refunded.",
               "The total, in case the channel adds a fee on top of the bundle price."
             ]}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or read [buy Airtel data bundles](/blog/buy-airtel-data-bundles)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I pay for Airtel data with M-Pesa?",
          answer:
            "Yes, on services that sell Airtel bundles and accept M-Pesa. Inside Airtel's own channels, Airtel Money is the usual rail."
        },
        %{
          question: "Is M-Pesa the same as Airtel Money?",
          answer:
            "No. They are different mobile money services run by different networks. M-Pesa is Safaricom's; Airtel Money is Airtel's."
        },
        %{
          question: "Will M-Pesa pay for a bundle on any network?",
          answer:
            "M-Pesa can pay any service that accepts it, whatever network the bundle is for — so yes, it can buy Airtel data on a website that carries Airtel."
        }
      ]
    }
  end

  # -------------------------------------------------------- spoke: online

  defp online do
    %Post{
      slug: "buy-data-bundles-online-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Online",
      title: "Buy Data Bundles Online in Kenya",
      meta_title: "Buy Data Bundles Online in Kenya — Any Network",
      description:
        "How to buy data bundles online in Kenya for any network — the four steps, why it beats a network app for another number, and what to check.",
      keywords: [
        "buy data bundles online Kenya",
        "data bundles online Kenya",
        "buy internet bundles online Kenya",
        "online data top up Kenya",
        "buy bundles online"
      ],
      intro: [
        "Buying data bundles online means you are not tied to one network: you pick the network, the bundle and the number, and pay — usually with M-Pesa. It is the fastest route when the number belongs to someone else, or when you are buying for more than one line.",
        "This page is the general walkthrough, whichever network you are topping up."
      ],
      sections: [
        %{
          id: "steps",
          heading: "How to Buy Data Bundles Online",
          blocks: [
            {:p, "Buying a bundle online is the same four steps every time:"},
            {:ol,
             [
               "Choose the network — Safaricom, Airtel, Telkom or Faiba.",
               "Enter the number you are topping up.",
               "Choose the bundle: the size and the validity.",
               "Pay, usually with M-Pesa, and keep the receipt."
             ]},
            {:p,
             "A good service shows you the number, the bundle and the total back before the money moves, because a bundle sent to the wrong number cannot be recalled."}
          ]
        },
        %{
          id: "why",
          heading: "Why Buy Online Rather Than in a Network App",
          blocks: [
            {:ul,
             [
               "Another number: online services are built for recipient numbers, while a network app is built for your own line first.",
               "Several networks: one site can carry all four, so you are not juggling apps.",
               "One payment: pay for several numbers in one go rather than one at a time."
             ]}
          ]
        },
        %{
          id: "watch",
          heading: "What to Check",
          blocks: [
            {:ul,
             [
               "That the service carries the recipient's network before you pay.",
               "The validity, not just the data size — the same data over a day and over a month are different offers.",
               "The total, in case a fee is added on top of the bundle price.",
               "The number, read back before you confirm."
             ]}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya). If you are topping up someone else, see [buy data bundles for another number](/blog/buy-data-bundles-for-another-number). The same walkthrough for airtime is in [buy airtime online in Kenya](/blog/buy-airtime-online-kenya)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy data bundles online in Kenya for any network?",
          answer:
            "On a service that carries all four — Safaricom, Airtel, Telkom and Faiba — yes. You pick the network for each number."
        },
        %{
          question: "How do I pay for data bundles online?",
          answer:
            "Usually with M-Pesa: choose the bundle, confirm the total, and approve the M-Pesa payment."
        },
        %{
          question: "Is buying data bundles online instant?",
          answer:
            "On a good service, yes — the bundle is sent to the number within moments of the payment clearing."
        }
      ]
    }
  end

  # ---------------------------------------------- spoke: another number

  defp for_another_number do
    %Post{
      slug: "buy-data-bundles-for-another-number",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "For someone else",
      title: "Buy Data Bundles for Another Number in Kenya",
      meta_title: "Buy Data Bundles for Another Number in Kenya",
      description:
        "How to buy data bundles for someone else in Kenya — keeping a student, a worker or family online, and picking the right bundle for them.",
      keywords: [
        "buy data bundles for another number",
        "buy bundles for someone else Kenya",
        "send data bundles to another number Kenya",
        "top up data for another number",
        "buy bundles for someone Kenya"
      ],
      intro: [
        "Buying someone data is one of the ordinary ways Kenyans help each other: a student revising, a househelp, a boda rider who needs maps, a relative whose bundle just ran out. You pay in shillings; the data lands on their line.",
        "This page covers how to do it, and the one mistake that turns a kind gesture into wasted money: buying the wrong kind of bundle."
      ],
      sections: [
        %{
          id: "how",
          heading: "How to Buy Data for Another Number",
          blocks: [
            {:ol,
             [
               "Find out the recipient's network first, not just their number. A bundle is tied to the network it was bought for.",
               "Choose a channel that takes a recipient number — a bundle website, or the network app where it supports it.",
               "Enter their number, the bundle size and the validity.",
               "Pay and share the confirmation with them."
             ]},
            {:p,
             "Read the number back before you pay. A bundle delivered to a wrong number is not refunded, and it is easy to mistype a number you do not use every day."}
          ]
        },
        %{
          id: "right-bundle",
          heading: "Picking the Right Bundle for Them",
          blocks: [
            {:p,
             "The common mistake is buying a social or app-specific bundle for someone who needs general browsing, or a bundle that expires before they can use it. Ask what they actually do on their phone."},
            {:ul,
             [
               "A student who studies online needs general data, not a social bundle.",
               "Someone who mostly chats may genuinely be served by a cheaper social bundle.",
               "Someone who is offline for days at a time may waste a daily bundle; a weekly or monthly one fits better."
             ]}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or see [buy data bundles online in Kenya](/blog/buy-data-bundles-online-kenya). Sending airtime to someone instead is in [buy airtime for another number](/blog/buy-airtime-for-another-number)."},
            {:cta,
             %{
               text:
                 "Sending airtime instead? Tangi tops up any Kenyan line for someone else — face value, paid with M-Pesa, in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy data bundles for another number in Kenya?",
          answer:
            "Yes, on channels that accept a recipient number — a bundle website readily, and the network app where it supports it. Match the bundle to the recipient's network."
        },
        %{
          question: "What happens if I send a bundle to the wrong number?",
          answer:
            "It is not refunded. Read the number back before you confirm, exactly as you would for airtime."
        },
        %{
          question: "Should I buy a social bundle for someone else?",
          answer:
            "Only if that is what they use. A social bundle excludes general browsing, so for a student or someone who works online it is the wrong gift."
        }
      ]
    }
  end

  # --------------------------------------------------------- spoke: daily

  defp daily do
    %Post{
      slug: "daily-data-bundles-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Daily",
      title: "Daily Data Bundles in Kenya",
      meta_title: "Daily Data Bundles in Kenya — How and When to Buy Them",
      description:
        "What a daily data bundle is in Kenya, when buying data by the day beats a weekly or monthly bundle, and the trap that makes daily bundles expensive.",
      keywords: [
        "daily data bundles Kenya",
        "daily bundles Kenya",
        "buy daily data bundle",
        "one day data bundle Kenya",
        "24 hour data bundle Kenya"
      ],
      intro: [
        "A daily bundle gives you a set amount of data for a day and then expires, used or not. It is the smallest commitment you can make, and for the right person it is also the cheapest way to stay online.",
        "This page explains what daily bundles are good at, and the trap that turns them into the most expensive way to buy data."
      ],
      sections: [
        %{
          id: "what",
          heading: "What a Daily Bundle Is",
          blocks: [
            {:p,
             "A daily bundle pairs a data size with a one-day validity. At the end of the day the bundle expires, and whatever you did not use is gone — it is not added to tomorrow's bundle."},
            {:p,
             "That expiry is the whole design. You pay less up front than a weekly or monthly bundle of the same size, on the understanding that you will use it within the day."}
          ]
        },
        %{
          id: "when",
          heading: "When a Daily Bundle Makes Sense",
          blocks: [
            {:ul,
             [
               "Days of heavy use rather than steady use — you buy for the days you need and pay nothing on the days you do not.",
               "A short trip or a one-off task where a monthly bundle would be wasted.",
               "A second sim or a spare phone that is only used occasionally."
             ]}
          ]
        },
        %{
          id: "careful",
          heading: "The Daily Bundle Trap",
          blocks: [
            {:p,
             "The trap is buying a daily bundle on a day you cannot finish it. If you use it every single day, a week of daily bundles usually costs more than one weekly bundle for the same data — you are paying for the flexibility you are not using."},
            {:p,
             "The test is simple: if you find yourself buying a daily bundle every day, move up to a [weekly](/blog/weekly-data-bundles-kenya) or [monthly](/blog/monthly-data-bundles-kenya) bundle and keep the daily one for the exceptions."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or compare [weekly](/blog/weekly-data-bundles-kenya) and [monthly](/blog/monthly-data-bundles-kenya) bundles."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How long does a daily data bundle last in Kenya?",
          answer:
            "For a day — commonly 24 hours from purchase on most networks, though the exact clock varies, so check the offer you are buying."
        },
        %{
          question: "Does unused daily data carry over?",
          answer:
            "Usually not. A daily bundle expires at the end of its period and unused data is generally lost, which is why buying one you cannot finish is a waste."
        },
        %{
          question: "Are daily bundles cheaper than monthly bundles?",
          answer:
            "Cheaper up front, but not necessarily cheaper over a month. If you buy a daily bundle every day, a weekly or monthly bundle is usually better value for the same data."
        }
      ]
    }
  end

  # -------------------------------------------------------- spoke: weekly

  defp weekly do
    %Post{
      slug: "weekly-data-bundles-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Weekly",
      title: "Weekly Data Bundles in Kenya",
      meta_title: "Weekly Data Bundles in Kenya — How and When to Buy Them",
      description:
        "What a weekly data bundle is in Kenya, who it suits, and how it compares to daily and monthly bundles.",
      keywords: [
        "weekly data bundles Kenya",
        "weekly bundles Kenya",
        "buy weekly data bundle",
        "7 day data bundle Kenya",
        "one week data bundle Kenya"
      ],
      intro: [
        "A weekly bundle gives you a set amount of data for about a week. It sits between the daily bundle and the monthly one: more commitment than a day, less than a month.",
        "For a lot of people it is the sweet spot. This page explains why, and when a weekly bundle is the wrong size."
      ],
      sections: [
        %{
          id: "what",
          heading: "What a Weekly Bundle Is",
          blocks: [
            {:p,
             "A weekly bundle pairs a data size with a roughly seven-day validity. Like every bundle, it expires at the end of its period, and unused data does not move to the next one."},
            {:p,
             "It exists because most people do not use data in perfectly even amounts: a weekly bundle absorbs a couple of heavy days without the daily price of buying for each one."}
          ]
        },
        %{
          id: "when",
          heading: "When a Weekly Bundle Makes Sense",
          blocks: [
            {:ul,
             [
               "Fairly steady use through the week, without being online all day every day.",
               "A stretch when you know you will need data — a work week, an exam week, a visit away from home.",
               "Anyone currently buying a daily bundle almost every day, for whom a weekly bundle is usually better value."
             ]}
          ]
        },
        %{
          id: "careful",
          heading: "Where a Weekly Bundle Falls Short",
          blocks: [
            {:p,
             "A weekly bundle is a poor fit for lumpy use. If you need a lot of data on one day and almost none for the rest of the week, a [daily bundle](/blog/daily-data-bundles-kenya) for that day plus a smaller bundle for the rest is often cheaper."},
            {:p,
             "And if you are buying a weekly bundle every week, check a [monthly bundle](/blog/monthly-data-bundles-kenya): for steady use over a month it usually costs less for the same data."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or compare [daily](/blog/daily-data-bundles-kenya) and [monthly](/blog/monthly-data-bundles-kenya) bundles."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How long does a weekly data bundle last in Kenya?",
          answer:
            "About seven days, though the exact validity varies by offer and network, so check the bundle you are buying."
        },
        %{
          question: "Is a weekly bundle better than a daily bundle?",
          answer:
            "If you use data most days, usually yes — a week of daily bundles generally costs more than one weekly bundle for the same data."
        },
        %{
          question: "Is a weekly bundle better than a monthly bundle?",
          answer:
            "For steady month-long use, a monthly bundle is usually better value. A weekly bundle suits shorter, bounded stretches."
        }
      ]
    }
  end

  # ------------------------------------------------------- spoke: monthly

  defp monthly do
    %Post{
      slug: "monthly-data-bundles-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Monthly",
      title: "Monthly Data Bundles in Kenya",
      meta_title: "Monthly Data Bundles in Kenya — How and When to Buy Them",
      description:
        "What a monthly data bundle is in Kenya, who it suits, and how to size it so you neither run out early nor waste data at the end of the month.",
      keywords: [
        "monthly data bundles Kenya",
        "monthly bundles Kenya",
        "buy monthly data bundle",
        "30 day data bundle Kenya",
        "one month data bundle Kenya"
      ],
      intro: [
        "A monthly bundle gives you a set amount of data for about a month. It is the largest commitment and, for a phone that is used every day, usually the least fuss and the best value per gigabyte.",
        "This page covers who it suits and how to size it so you do not run out early or waste data at the end."
      ],
      sections: [
        %{
          id: "what",
          heading: "What a Monthly Bundle Is",
          blocks: [
            {:p,
             "A monthly bundle pairs a data size with a validity of roughly a month — often 30 days, though the exact period is set by the network and the offer. As with every bundle, unused data at the end of the period does not roll over."},
            {:p,
             "Because you are buying more data at once, the price per gigabyte is usually lower than the same data bought by the day or the week."}
          ]
        },
        %{
          id: "when",
          heading: "When a Monthly Bundle Makes Sense",
          blocks: [
            {:ul,
             [
               "A line used every day, where the data is steady rather than spiky.",
               "A main phone, where running out of data is a real inconvenience.",
               "Anyone buying a weekly bundle every week — a monthly bundle is usually cheaper for the same data."
             ]}
          ]
        },
        %{
          id: "sizing",
          heading: "How to Size a Monthly Bundle",
          blocks: [
            {:p,
             "Sizing is the whole game with a monthly bundle, because both errors cost money. Too small and you buy top-ups at daily prices in the last week; too large and you lose data at the end of the month."},
            {:ol,
             [
               "Start from what you actually used last month, if the network shows it.",
               "Add a margin for a heavy week, rather than a margin for the whole month.",
               "Watch the first month: if you run out in the last few days, a bigger bundle is cheaper than repeated top-ups; if you finish with data to spare, size down."
             ]},
            {:p,
             "If the month is too long a commitment for how you use data, a [weekly](/blog/weekly-data-bundles-kenya) or [daily](/blog/daily-data-bundles-kenya) bundle fits better."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or see [the cheapest data bundles in Kenya](/blog/cheapest-data-bundles-kenya) for how to compare them."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "How long does a monthly data bundle last in Kenya?",
          answer:
            "Roughly a month — often 30 days, though the exact period depends on the network and the offer, so confirm it when you buy."
        },
        %{
          question: "Does unused monthly data carry over?",
          answer:
            "Generally no. At the end of the validity period the bundle expires and any unused data is lost, unless the bundle was sold as no-expiry."
        },
        %{
          question: "Is a monthly bundle the cheapest option?",
          answer:
            "Per gigabyte it usually is, for a line used every day. But if you do not finish the data, a smaller weekly bundle can end up cheaper for what you actually use."
        }
      ]
    }
  end

  # ---------------------------------------------------------- spoke: best

  defp best do
    %Post{
      slug: "best-data-bundles-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Comparison",
      title: "The Best Data Bundles in Kenya",
      meta_title: "The Best Data Bundles in Kenya — How to Choose",
      description:
        "There is no single best data bundle in Kenya — there is the best one for how you use data. Here is how to choose, by validity, coverage and cost per gigabyte.",
      keywords: [
        "best data bundles in Kenya",
        "best data bundles Kenya",
        "which data bundle is best Kenya",
        "best internet bundle Kenya",
        "best bundle for data Kenya"
      ],
      intro: [
        "There is no single best data bundle in Kenya. A bundle is data plus a validity period, so the best one is simply the one that matches how you use data — and that is different for a student, a boda rider and someone who works from a phone.",
        "Here is how to choose, rather than a list of offers that will be out of date by the time you read it."
      ],
      sections: [
        %{
          id: "frameworks",
          heading: "How to Judge a Bundle",
          blocks: [
            {:ul,
             [
               "Cost per gigabyte: divide the price by the data. It is the fairest single number, and it exposes bundles that are cheap only in the headline.",
               "Validity: the same data over a day and over a month is not the same product. Match it to how steadily you use data.",
               "Coverage: a social or app-specific bundle is cheaper because it excludes general browsing — only good if that is all you do.",
               "All-network versus network-only: most bundles work only on the sim they were bought for.",
               "Auto-renew: convenient, but easy to keep paying for a bundle you have stopped watching."
             ]}
          ]
        },
        %{
          id: "match",
          heading: "Match the Bundle to How You Use Data",
          blocks: [
            {:table,
             %{
               head: ["How you use data", "Validity that fits", "Why"],
               rows: [
                 ["Heavy, but only some days", "Daily", "You pay only for the days you need"],
                 [
                   "Steady through a week",
                   "Weekly",
                   "Less waste than daily, less tied up than monthly"
                 ],
                 [
                   "Every day, all month",
                   "Monthly",
                   "Least fuss and usually the lowest cost per GB"
                 ],
                 [
                   "Mostly chat and social apps",
                   "Social or app bundle",
                   "Cheaper, but it excludes general browsing"
                 ],
                 [
                   "A spare phone used now and then",
                   "Daily or weekly",
                   "A monthly bundle would expire half-used"
                 ]
               ]
             }},
            {:p,
             "The table is a starting point, not a price list: prices and validity change, so confirm the current offer on the network before you buy."}
          ]
        },
        %{
          id: "avoid",
          heading: "What to Avoid",
          blocks: [
            {:p,
             "Two bundles look like good value and usually are not. A large bundle with a short validity is only good if you can genuinely use it in that time; and a bundle that auto-renews is only good if you meant to keep it running."},
            {:p,
             "For the value question in detail, see [the cheapest data bundles in Kenya](/blog/cheapest-data-bundles-kenya)."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or read [the cheapest data bundles in Kenya](/blog/cheapest-data-bundles-kenya). For the airtime comparison, see [the best way to buy airtime in Kenya](/blog/best-way-to-buy-airtime-kenya)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Which network has the best data bundles in Kenya?",
          answer:
            "It depends on the bundle you need and where you are. Compare the same data size and validity across networks, and check coverage for the places you use it."
        },
        %{
          question: "Are monthly bundles always the best value?",
          answer:
            "Per gigabyte they often are, but only if you use the data within the month. A bundle you do not finish is worse value than a smaller one you do."
        },
        %{
          question: "Are social bundles good value?",
          answer:
            "They are cheap for a reason: they cover specific apps only and exclude general browsing. Good value if that is all you use, poor value otherwise."
        }
      ]
    }
  end

  # ------------------------------------------------------ spoke: cheapest

  defp cheapest do
    %Post{
      slug: "cheapest-data-bundles-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Comparison",
      title: "The Cheapest Data Bundles in Kenya",
      meta_title: "The Cheapest Data Bundles in Kenya — How to Pay Less",
      description:
        "How to get the cheapest data bundles in Kenya — the cost-per-gigabyte test, the leaks that make bundles expensive, and the habits that cut the bill.",
      keywords: [
        "cheapest data bundles in Kenya",
        "cheapest data bundles Kenya",
        "cheap data bundles Kenya",
        "cheapest internet bundles Kenya",
        "how to save on data bundles Kenya"
      ],
      intro: [
        "The cheapest data bundle is not a bundle you can name in advance — bundle prices and validity change constantly. What is stable is the method: compare by cost per gigabyte, and stop paying for data you do not use.",
        "This page is that method, and the leaks that quietly make bundles expensive."
      ],
      sections: [
        %{
          id: "cost-per-gb",
          heading: "Compare by Cost per Gigabyte",
          blocks: [
            {:p,
             "A bundle has two prices: the shillings you hand over, and the shillings per gigabyte. Only the second lets you compare. A bundle that costs twice as much but gives three times the data is the cheaper one per gigabyte, even though it costs more today."},
            {:p,
             "So do the division before you decide, and compare bundles of the same validity — a daily and a monthly bundle are not comparable at the same price, because you are buying different amounts of time."}
          ]
        },
        %{
          id: "leaks",
          heading: "The Leaks That Make Bundles Expensive",
          blocks: [
            {:ul,
             [
               "Oversizing: a bundle bigger than you finish wastes the difference, every period.",
               "Expiry: a short-validity bundle you cannot use in time leaks data at the end.",
               "Auto-renew: a bundle that renews itself keeps charging after you stop needing it.",
               "Background data: apps updating and syncing eat a bundle you thought you had not touched.",
               "Airtime fallback: once a bundle ends, data on airtime is usually far more expensive per gigabyte."
             ]}
          ]
        },
        %{
          id: "habits",
          heading: "Habits That Cut the Bill",
          blocks: [
            {:ul,
             [
               "Size to your real usage, then check after a month and adjust",
               "Prefer the longer validity when you use data every day",
               "Turn off automatic updates over mobile data",
               "Keep a small bundle running rather than falling back to airtime",
               "Re-check offers occasionally, since networks change bundles often"
             ]},
            {:p,
             "To see which validity suits you, start with [daily](/blog/daily-data-bundles-kenya), [weekly](/blog/weekly-data-bundles-kenya) or [monthly](/blog/monthly-data-bundles-kenya) bundles."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Start with [the complete guide to buying data bundles in Kenya](/blog/buy-data-bundles-kenya), or read [the best data bundles in Kenya](/blog/best-data-bundles-kenya)."},
            {:cta,
             %{
               text:
                 "Tangi does not sell data bundles — but it does top up airtime for any Kenyan line, in seconds, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "What is the cheapest data bundle in Kenya?",
          answer:
            "There is no fixed answer, because bundle prices and validity change. The cheapest is whichever bundle gives you the most data for the shillings you spend, at a validity you will actually use."
        },
        %{
          question: "Is it cheaper to use airtime for data?",
          answer:
            "Almost never. Data bought as a bundle is usually far cheaper per gigabyte than the same data used from an airtime balance."
        },
        %{
          question: "How do I compare two data bundles fairly?",
          answer:
            "Divide each price by its gigabytes to get the cost per gigabyte, and only compare bundles with the same validity. Then check what the bundle covers."
        }
      ]
    }
  end
end
