defmodule ViewNinjas.Blog.Clusters.BuyAirtimeKenya do
  @moduledoc """
  The "buy airtime in Kenya" cluster: one pillar and eleven spokes, for the airtime
  product (`docs/instalipa-airtime.md`).

  The pillar carries the broad intent ("buy airtime in Kenya") and the spokes
  answer the narrower questions — one per network, one per payment method, the
  "where do I top up someone else" cases, and one walkthrough of the product
  itself, screens and all. Every spoke links back up to the pillar and down to
  the buy screen, and the pillar links to every spoke, so a crawler that lands
  anywhere can reach the whole set.

  ## The cluster

      pillar  buy-airtime-kenya
        │
        ├── networks:  buy-safaricom-airtime · buy-airtel-airtime
        │              buy-telkom-airtime · buy-faiba-airtime · buy-equitel-airtime
        ├── methods:   buy-airtime-with-mpesa · buy-airtime-online-kenya
        │              buy-airtime-without-going-to-shop
        ├── audience:  buy-airtime-for-another-number
        ├── compare:   best-way-to-buy-airtime-kenya
        └── product:   how-to-buy-airtime-with-tangi

  ## Keywords

  Pillar: *buy airtime in Kenya*. Each spoke owns one primary term — *buy
  Safaricom airtime*, *buy airtime with M-Pesa*, *buy airtime for another
  number*, and so on — and lists its secondary terms in `keywords`.

  The copy matches the rail: airtime is sold at **face value**, delivered in
  **seconds**, paid with **M-Pesa** (wallet-first), needs an **account with a
  verified phone**, and is **irreversible** — a wrong number is not refunded.
  """

  alias ViewNinjas.Blog.{Cluster, Post}

  @cluster "buy-airtime-kenya"
  @updated ~D[2026-10-01]

  @doc "The cluster's own metadata."
  @spec cluster() :: Cluster.t()
  def cluster do
    %Cluster{
      slug: @cluster,
      eyebrow: "Airtime in Kenya",
      title: "Buy Airtime in Kenya",
      keyword: "buy airtime in Kenya",
      description:
        "How to buy airtime in Kenya online — Safaricom, Airtel, Telkom, Faiba and Equitel, with M-Pesa, by USSD, or for another number."
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
      equitel(),
      mpesa(),
      online(),
      for_another_number(),
      without_a_shop(),
      best_way(),
      tangi()
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
      title: "Buy Airtime in Kenya Online: Safaricom, Airtel, Telkom, Faiba & Equitel",
      meta_title: "Buy Airtime in Kenya Online — Safaricom, Airtel, Telkom, Faiba & Equitel",
      description:
        "How to buy airtime in Kenya for any network — Safaricom, Airtel, Telkom, Faiba or Equitel — with M-Pesa, by USSD or for another number, and what it costs.",
      keywords: [
        "buy airtime in Kenya",
        "buy airtime Kenya",
        "buy airtime online Kenya",
        "airtime Kenya",
        "airtime top up Kenya",
        "buy airtime with M-Pesa",
        "buy airtime for another number",
        "instant airtime Kenya",
        "cheap airtime Kenya",
        "airtime top up online"
      ],
      intro: [
        "Buying airtime in Kenya no longer means a scratch card from a kiosk. From your phone you can top up any Kenyan line — Safaricom, Airtel, Telkom, Faiba or Equitel — in seconds, for yourself or for someone else, and pay with M-Pesa.",
        "This guide covers every network and every common way to buy airtime: with M-Pesa, on an airtime website, by USSD, over WhatsApp, or in a network app. It also explains how to buy airtime for another number, and what airtime prices and limits really mean."
      ],
      sections: pillar_sections(),
      faqs: pillar_faqs()
    }
  end

  defp pillar_sections do
    [
      %{
        id: "ways-to-buy",
        heading: "The Ways to Buy Airtime in Kenya",
        blocks: [
          {:p,
           "There are five routes to a topped-up line in Kenya, and they differ in one thing: whether you need data, and whether you can top up a number that is not your own."},
          {:table,
           %{
             head: [
               "Method",
               "Your own number",
               "Another number",
               "Needs data",
               "Pay with M-Pesa"
             ],
             rows: [
               ["M-Pesa menu or app", "Yes", "Yes", "No", "Yes"],
               ["Network app (mySafaricom, Airtel, etc.)", "Yes", "Often", "Yes", "Yes"],
               ["Airtime website or app", "Yes", "Yes", "Yes", "Yes"],
               ["USSD", "Yes", "Sometimes", "No", "Yes"]
             ]
           }},
          {:p,
           "The route you pick mostly comes down to whether the number belongs to you, and whether you have a data bundle at the time. Everything below is one of these five."}
        ]
      },
      %{
        id: "safaricom",
        heading: "Buy Safaricom Airtime",
        blocks: [
          {:p,
           "Safaricom is Kenya's largest network, so most searches for buy airtime online in Kenya start here. You can top up a Safaricom line from the M-Pesa menu, the M-Pesa app, the mySafaricom app, a USSD string, or a third-party airtime website — and the airtime usually lands within seconds."},
          {:p,
           "The one thing to know: a top-up cannot be recalled. If you send it to the wrong number, it is gone, so read the number back before you confirm. The full walkthrough, including topping up a Safaricom number that is not yours, is in [Buy Safaricom airtime in Kenya](/blog/buy-safaricom-airtime)."}
        ]
      },
      %{
        id: "airtel",
        heading: "Buy Airtel Airtime",
        blocks: [
          {:p,
           "Buying Airtel airtime works the same way, with Airtel Money and M-Pesa both in the mix alongside the Airtel app. You can top up your own Airtel line or an Airtel number belonging to someone else; the network, not the method, decides how fast it arrives."},
          {:p,
           "For the step-by-step, including the payment options Airtel accepts, see [Buy Airtel airtime in Kenya](/blog/buy-airtel-airtime)."}
        ]
      },
      %{
        id: "telkom",
        heading: "Buy Telkom Airtime",
        blocks: [
          {:p,
           "Telkom airtime can be bought through Telkom's own channels — including T-Kash, which lets you top up your line or another Telkom number — and through third-party airtime services. If you are buying for a different network's number, make sure the service you use supports that network before you pay."},
          {:p,
           "Everything Telkom-specific is in [Buy Telkom airtime in Kenya](/blog/buy-telkom-airtime)."}
        ]
      },
      %{
        id: "faiba",
        heading: "Buy Faiba Airtime",
        blocks: [
          {:p,
           "Faiba, run by JTL, has its own app, and it supports buying airtime for your own line or for another Faiba number. Faiba numbers are less common than Safaricom's, so if you are using a general airtime service, double-check that it carries Faiba before you pay."},
          {:p, "See [Buy Faiba airtime in Kenya](/blog/buy-faiba-airtime) for the options."}
        ]
      },
      %{
        id: "equitel",
        heading: "Buy Equitel Airtime",
        blocks: [
          {:p,
           "Equitel is the mobile virtual network operated out of Equity, so its airtime is bought through Equity's own channels and through airtime services that carry it. You can top up your own Equitel line or another Equitel number."},
          {:p, "Details are in [Buy Equitel airtime in Kenya](/blog/buy-equitel-airtime)."}
        ]
      },
      %{
        id: "mpesa",
        heading: "Buy Airtime With M-Pesa",
        blocks: [
          {:p,
           "M-Pesa is the most common way to buy airtime in Kenya, and it is built for it: the M-Pesa menu has a Buy Airtime option, and the M-Pesa app does the same thing on a screen. You choose the number and the amount, confirm, and the airtime is sent."},
          {:p,
           "M-Pesa is also how most airtime websites are paid — you pay in shillings with M-Pesa, and the airtime goes to the number you entered. There is no card, no bank, and no scratch card involved."},
          {:p,
           "More on the M-Pesa routes, including buying from the app, is in [Buy airtime with M-Pesa in Kenya](/blog/buy-airtime-with-mpesa)."}
        ]
      },
      %{
        id: "online",
        heading: "Buy Airtime Online",
        blocks: [
          {:p,
           "Buying airtime online usually means you are not tied to one network — you just want to top up a number without leaving your seat. An airtime website or app lets you pick the network, type the number, choose the amount and pay, all in one place, and it works for numbers that are not on your own network."},
          {:p,
           "This is the fastest route when you are topping up several people, or when the number belongs to someone else. For the general walkthrough, see [Buy airtime online in Kenya](/blog/buy-airtime-online-kenya)."}
        ]
      },
      %{
        id: "for-someone",
        heading: "Buy Airtime for Someone Else",
        blocks: [
          {:p,
           "Top-up is a normal way to help family, a househelp, a boda rider or a student: you pay in shillings, and the airtime lands on their number. Every channel above supports it — M-Pesa, the network apps, and airtime websites all let you enter a recipient number rather than only your own."},
          {:p,
           "Two rules keep it safe. First, the number must be right: airtime is delivered, not verified, and a wrong number cannot be recalled. Second, not every channel carries every network, so match the number's network to the service you use."},
          {:p,
           "The full guide is [Buy airtime for another number](/blog/buy-airtime-for-another-number)."}
        ]
      },
      %{
        id: "website",
        heading: "Buy Airtime Using a Website",
        blocks: [
          {:p, "Buying airtime on a website is the same four steps every time:"},
          {:ol,
           [
             "Choose the network — Safaricom, Airtel, Telkom, Faiba or Equitel.",
             "Enter the number you are topping up.",
             "Choose the amount in shillings.",
             "Pay, usually with M-Pesa, and keep the receipt."
           ]},
          {:p,
           "A good website shows you the number and the amount back before the money moves — because airtime is irreversible — and gives you a receipt code when it is done. It also lets you top up more than one number at a time, which is the reason to use a website instead of your network's own app."},
          {:p,
           "If avoiding the trip to a shop is the point, see [Buy airtime without going to a shop](/blog/buy-airtime-without-going-to-shop)."}
        ]
      },
      %{
        id: "ussd",
        heading: "Buy Airtime Using USSD",
        blocks: [
          {:p,
           "USSD is the fallback that always works — no data, no app, no internet. You dial the operator's menu on your phone and follow the prompts. M-Pesa, for example, is reached on *334#, and its menu includes buying airtime; the network's own menu can top up your line too."},
          {:p,
           "USSD is the slowest way to buy airtime, and the least friendly if you are topping up several numbers, but it is the one that works on a feature phone, with no data bundle, in the middle of nowhere."}
        ]
      },
      %{
        id: "whatsapp",
        heading: "Buy Airtime Using WhatsApp",
        blocks: [
          {:p,
           "A growing number of airtime services sell over WhatsApp: you message the number, send the recipient and the amount, and pay with M-Pesa from the chat. It is convenient when WhatsApp is already open — but treat it like any other payment channel: use a service you trust, and check the number before you send."}
        ]
      },
      %{
        id: "tangi",
        heading: "Buy Airtime on Tangi",
        blocks: [
          {:p,
           "Tangi is one place to do everything above: pick the network — Safaricom, Airtel, Telkom or Faiba — enter one or more numbers, and pay at face value. The airtime lands in seconds, and there is no scratch card and no markup on the value."},
          {:p,
           "You pay from your Tangi wallet, or straight from M-Pesa when the wallet is short, and one buy can top up several numbers at once. For the step-by-step walkthrough, with the real screens, see [how to buy airtime with Tangi](/blog/how-to-buy-airtime-with-tangi)."},
          {:cta,
           %{
             text:
               "Buy airtime for any Kenyan network on Tangi — priced in shillings, paid with M-Pesa, delivered in seconds.",
             href: "/airtime",
             label: "Buy airtime"
           }}
        ]
      },
      %{
        id: "prices-limits",
        heading: "Airtime Prices and Limits",
        blocks: [
          {:p,
           "Airtime is sold at face value: KSh 100 buys KSh 100 of airtime. There is no markup on top of the value — a channel makes its money differently, so the thing to check is whether a service adds a fee, not whether the price varies."},
          {:ul,
           [
             "Denominations: airtime is commonly sold from about KSh 5 up to KSh 1,000, and you can usually type any whole-shilling amount in between.",
             "Fees: operator channels (M-Pesa, the network apps) sell at face value. Some third-party airtime platforms add a small fee — check before you pay.",
             "Limits: everyday limits are set by the networks and by M-Pesa, and they change. Your own M-Pesa daily limit caps how much you can spend in a day; operators may also cap airtime per transaction.",
             "Delivery: on operator channels and good airtime services, the airtime arrives within seconds.",
             "Irreversibility: a delivered top-up cannot be recalled. Read the number back before you confirm — this is the rule that matters more than any other."
           ]}
        ]
      },
      %{
        id: "next",
        heading: "Where to Start",
        toc: false,
        blocks: [
          {:p,
           "Pick the network you are topping up, or the method you want to pay with, from the guides above. If you are not sure which route is best, [the best way to buy airtime in Kenya](/blog/best-way-to-buy-airtime-kenya) compares them side by side. To do it on Tangi, screens and all, start with [how to buy airtime with Tangi](/blog/how-to-buy-airtime-with-tangi). If you are weighing a data bundle instead of airtime, [buy data bundles in Kenya](/blog/buy-data-bundles-kenya) covers that side of the market."},
          {:cta,
           %{
             text:
               "Buy airtime for Safaricom, Airtel, Telkom, Faiba and Equitel — priced in shillings, paid with M-Pesa, delivered in seconds.",
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
        question: "Can I buy airtime for another number in Kenya?",
        answer:
          "Yes. M-Pesa, the network apps and airtime websites all let you enter a recipient's number, so you can top up a friend, a family member or a worker. Make sure the number is correct — a delivered top-up cannot be reversed."
      },
      %{
        question: "Can I buy airtime with M-Pesa?",
        answer:
          "Yes. The M-Pesa menu has a Buy Airtime option, and the M-Pesa app does the same on a screen. M-Pesa is also the usual way to pay on an airtime website."
      },
      %{
        question: "Is online airtime instant?",
        answer:
          "On operator channels and reputable airtime services, yes — the airtime lands within seconds of the payment."
      },
      %{
        question: "Do I need a scratch card to buy airtime?",
        answer:
          "No. Scratch cards are one way, not the way. You can buy airtime with M-Pesa, in a network app, on a website, by USSD or over WhatsApp."
      },
      %{
        question: "Is there a fee to buy airtime online?",
        answer:
          "Operator channels sell at face value. Some third-party platforms add a small convenience fee, so check the total before you confirm the payment."
      },
      %{
        question: "What is the cheapest way to buy airtime in Kenya?",
        answer:
          "Airtime is face value, so the cheapest route is the one that adds no fee. That is usually the network's own channels or M-Pesa — but it is worth comparing, because some services run promotions."
      },
      %{
        question:
          "Can I buy airtime for Safaricom, Airtel, Telkom, Faiba and Equitel in one place?",
        answer:
          "On a general airtime website, yes — you pick the network per number. Operator apps usually only serve their own network."
      },
      %{
        question: "Can I buy airtime without internet?",
        answer: "Yes. USSD works with no data bundle, and so does the M-Pesa menu on your phone."
      }
    ]
  end

  # ------------------------------------------------------ spoke: Safaricom

  defp safaricom do
    %Post{
      slug: "buy-safaricom-airtime",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Safaricom",
      title: "Buy Safaricom Airtime in Kenya",
      meta_title: "Buy Safaricom Airtime in Kenya — Online, With M-Pesa",
      description:
        "How to buy Safaricom airtime in Kenya — with M-Pesa, the mySafaricom app, USSD or a website — and how to top up a Safaricom number that is not yours.",
      keywords: [
        "buy Safaricom airtime",
        "buy Safaricom airtime online",
        "Safaricom airtime Kenya",
        "Safaricom top up",
        "buy Safaricom credit",
        "buy Safaricom airtime with M-Pesa",
        "Safaricom airtime online"
      ],
      intro: [
        "Safaricom is Kenya's biggest network, and topping up a Safaricom line is the most common airtime purchase in the country. You can do it with M-Pesa, in the mySafaricom app, by USSD, or on an airtime website — and the airtime normally lands within seconds.",
        "This page walks through each route, and the one that matters most when the number is not yours: topping up someone else's Safaricom line."
      ],
      sections: [
        %{
          id: "ways",
          heading: "Ways to Buy Safaricom Airtime",
          blocks: [
            {:p, "There are four practical routes to a topped-up Safaricom line:"},
            {:ul,
             [
               "The M-Pesa menu: Buy Airtime, then the number and the amount.",
               "The M-Pesa app or the mySafaricom app: the same thing with buttons instead of a USSD menu.",
               "A USSD string: works with no data bundle.",
               "An airtime website or app: the best route when the number is not yours, or when you are topping up more than one line."
             ]},
            {:p,
             "All four deliver the same airtime at the same face value. The difference is convenience — and whether you can enter a recipient number."}
          ]
        },
        %{
          id: "mpesa",
          heading: "Buying Safaricom Airtime With M-Pesa",
          blocks: [
            {:p,
             "M-Pesa is Safaricom's own service, so buying Safaricom airtime with M-Pesa is the most direct route there is. The M-Pesa menu has a Buy Airtime option; you choose the number and the amount, enter your PIN, and the airtime is sent."},
            {:p,
             "You pay face value — KSh 100 buys KSh 100 of airtime. If you are using a third-party airtime service instead, you pay it with M-Pesa the same way, and the service sends the airtime on your behalf."}
          ]
        },
        %{
          id: "another",
          heading: "Topping Up Another Safaricom Number",
          blocks: [
            {:p,
             "You do not need the other person's phone to top up their Safaricom line. Every channel above lets you type the recipient's number, so you can send airtime to family, a worker or a client from your own phone."},
            {:p,
             "The rule to remember is that a delivered top-up cannot be recalled. Check the number before you confirm — a digit out, and the airtime belongs to a stranger."},
            {:callout,
             "Sending airtime is a common way to help someone without sending cash. The trade-off is the same as cash: once it lands, it is theirs."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "If the number is on a different network, see [Buy Airtel airtime in Kenya](/blog/buy-airtel-airtime), or read [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya) for every route side by side."},
            {:cta,
             %{
               text:
                 "Buy Safaricom airtime online — priced in shillings, paid with M-Pesa, delivered in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy Safaricom airtime for another number?",
          answer:
            "Yes. Enter the recipient's Safaricom number when you buy — M-Pesa, the apps and airtime websites all accept a number that is not your own."
        },
        %{
          question: "How fast does Safaricom airtime arrive?",
          answer:
            "Usually within seconds on M-Pesa, the apps and reputable airtime websites. USSD is a little slower because you work through the menu first."
        },
        %{
          question: "Do I need the other person's phone to top them up?",
          answer:
            "No. You only need their number. The airtime is delivered to the line, not to a handset you have to hold."
        }
      ]
    }
  end

  # --------------------------------------------------------- spoke: Airtel

  defp airtel do
    %Post{
      slug: "buy-airtel-airtime",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Airtel",
      title: "Buy Airtel Airtime in Kenya",
      meta_title: "Buy Airtel Airtime in Kenya — Online, With M-Pesa",
      description:
        "How to buy Airtel airtime in Kenya for your own line or another Airtel number — with Airtel Money, M-Pesa, the Airtel app or a website.",
      keywords: [
        "buy Airtel airtime",
        "buy Airtel airtime online",
        "Airtel airtime Kenya",
        "Airtel top up Kenya",
        "buy Airtel credit",
        "buy Airtel airtime with M-Pesa",
        "Airtel airtime online"
      ],
      intro: [
        "Airtel airtime is bought the same way as any other line in Kenya — the network decides how the top-up is delivered, and you are free to choose how you pay. You can use Airtel Money, M-Pesa, the Airtel app, or an airtime website.",
        "This page covers buying for your own Airtel number and for someone else's, and the payment options each route accepts."
      ],
      sections: [
        %{
          id: "ways",
          heading: "Ways to Buy Airtel Airtime",
          blocks: [
            {:p, "Airtel airtime comes from four places, and they all sell at face value:"},
            {:ul,
             [
               "Airtel Money: Airtel's own mobile money, which lets you buy airtime for a line.",
               "The Airtel app: the same purchase with buttons, for your own number or another Airtel number.",
               "M-Pesa: if you do not use Airtel Money, M-Pesa is how most airtime websites take payment.",
               "USSD: the network menu, which works without a data bundle."
             ]}
          ]
        },
        %{
          id: "mpesa",
          heading: "Buying Airtel Airtime With M-Pesa",
          blocks: [
            {:p,
             "You do not need Airtel Money to buy Airtel airtime. Airtime websites that carry Airtel accept M-Pesa, so you pay in shillings with the wallet you already have and the airtime goes to the Airtel number you entered."},
            {:p,
             "This is the route to use when you are topping up an Airtel number from a Safaricom line, or when you simply prefer to keep your payments in one place."}
          ]
        },
        %{
          id: "another",
          heading: "Your Own Airtel Number or Someone Else's",
          blocks: [
            {:p,
             "Airtel supports topping up your own line and, on most channels, another Airtel number. Enter the recipient's number instead of your own and the airtime goes there."},
            {:p,
             "As always with airtime, the delivery cannot be undone. Read the number back before you confirm."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "For a Safaricom line, see [Buy Safaricom airtime in Kenya](/blog/buy-safaricom-airtime). For the full picture, read [the guide to buying airtime in Kenya](/blog/buy-airtime-kenya)."},
            {:cta,
             %{
               text:
                 "Buy Airtel airtime online — pay with M-Pesa, and the airtime lands in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy Airtel airtime with M-Pesa?",
          answer:
            "Yes — through an airtime website that carries Airtel, you pay with M-Pesa and the airtime goes to the Airtel number you enter. Airtel Money is the network's own alternative."
        },
        %{
          question: "Can I top up another Airtel number?",
          answer:
            "Yes. Enter the recipient's Airtel number and the top-up is delivered to their line, whether you pay with Airtel Money, M-Pesa or the app."
        },
        %{
          question: "Is Airtel airtime the same price as Safaricom airtime?",
          answer:
            "Airtime is face value on every network — KSh 100 buys KSh 100. What differs is any fee a third-party service might add, not the value of the airtime."
        }
      ]
    }
  end

  # --------------------------------------------------------- spoke: Telkom

  defp telkom do
    %Post{
      slug: "buy-telkom-airtime",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Telkom",
      title: "Buy Telkom Airtime in Kenya",
      meta_title: "Buy Telkom Airtime in Kenya — Online and With M-Pesa",
      description:
        "How to buy Telkom airtime in Kenya — through T-Kash, the Telkom app, USSD or an airtime website — for your own line or another Telkom number.",
      keywords: [
        "buy Telkom airtime",
        "buy Telkom airtime online",
        "Telkom airtime Kenya",
        "Telkom top up Kenya",
        "buy Telkom credit",
        "Telkom airtime with M-Pesa"
      ],
      intro: [
        "Telkom is Kenya's third network, and its airtime is bought through Telkom's own channels or through a third-party airtime service. Telkom's mobile money, T-Kash, is the network's own route — and it lets you top up your line or another Telkom number.",
        "This page covers the Telkom routes and what to check when you buy from a service rather than the network."
      ],
      sections: [
        %{
          id: "ways",
          heading: "Ways to Buy Telkom Airtime",
          blocks: [
            {:p, "Telkom airtime comes through:"},
            {:ul,
             [
               "T-Kash, Telkom's mobile money: buy airtime for your line or another Telkom number.",
               "The Telkom app: the same purchase on a screen.",
               "USSD: the network menu, with no data bundle needed.",
               "A third-party airtime website, if it carries Telkom and you pay with M-Pesa."
             ]}
          ]
        },
        %{
          id: "tkash",
          heading: "Buying Telkom Airtime With T-Kash",
          blocks: [
            {:p,
             "T-Kash is Telkom's own mobile money, so it is the most direct way to buy Telkom airtime. From the T-Kash menu you can buy airtime for the line you are on, or enter another Telkom number to top that up instead."},
            {:p,
             "If you do not use T-Kash, an airtime website that carries Telkom will take M-Pesa and send the airtime for you."}
          ]
        },
        %{
          id: "another",
          heading: "Topping Up Another Telkom Number",
          blocks: [
            {:p,
             "T-Kash and most Telkom channels allow a recipient number, so you can top up a family member's or a worker's Telkom line from your own phone. The number is the only thing you need."},
            {:p,
             "Check the network first if you are using a general airtime service: not every service carries Telkom, and paying for a number a service cannot reach wastes a prompt."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Telkom is one of five networks in Kenya — see the [complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya) for the others, or [buy airtime online in Kenya](/blog/buy-airtime-online-kenya) for a network-agnostic route."},
            {:cta,
             %{
               text:
                 "Buy Telkom airtime online — priced in shillings, paid with M-Pesa, delivered in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "What is T-Kash?",
          answer:
            "T-Kash is Telkom's mobile money service. Alongside sending money, it lets you buy airtime for your Telkom line or another Telkom number."
        },
        %{
          question: "Can I buy Telkom airtime with M-Pesa?",
          answer:
            "Through an airtime website that carries Telkom, yes — you pay in shillings with M-Pesa and the airtime goes to the Telkom number you entered. T-Kash is the network's own alternative."
        },
        %{
          question: "Does every airtime service carry Telkom?",
          answer:
            "No. Telkom has fewer subscribers than Safaricom and Airtel, so check that the service you use supports Telkom before you pay."
        }
      ]
    }
  end

  # ---------------------------------------------------------- spoke: Faiba

  defp faiba do
    %Post{
      slug: "buy-faiba-airtime",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Faiba",
      title: "Buy Faiba Airtime in Kenya",
      meta_title: "Buy Faiba Airtime in Kenya — Online and With M-Pesa",
      description:
        "How to buy Faiba airtime in Kenya — through the Faiba app, JTL's channels or an airtime website — for your own line or another Faiba number.",
      keywords: [
        "buy Faiba airtime",
        "buy Faiba airtime online",
        "Faiba airtime Kenya",
        "Faiba top up",
        "buy Faiba credit",
        "Faiba airtime with M-Pesa",
        "JTL Faiba airtime"
      ],
      intro: [
        "Faiba is the consumer brand of JTL, and its airtime is bought through Faiba's own app and JTL's channels, or through a third-party airtime service. The Faiba app supports buying airtime for your own line or for another Faiba number.",
        "Because Faiba numbers are less common than Safaricom's, the thing to check here is whether the service you are using actually carries Faiba."
      ],
      sections: [
        %{
          id: "ways",
          heading: "Ways to Buy Faiba Airtime",
          blocks: [
            {:p, "Faiba airtime is available through:"},
            {:ul,
             [
               "The Faiba app, which supports airtime for your own line or another Faiba number.",
               "JTL's own channels, including Faiba's customer service and outlets.",
               "A third-party airtime website, if it carries Faiba, paid with M-Pesa."
             ]}
          ]
        },
        %{
          id: "app",
          heading: "Buying Faiba Airtime in the Faiba App",
          blocks: [
            {:p,
             "The Faiba app is the most direct route: sign in, choose airtime, pick your own number or enter another Faiba number, and pay. Because it is Faiba's own app, the top-up is immediate and there is no third party in the middle."}
          ]
        },
        %{
          id: "mpesa",
          heading: "Buying Faiba Airtime With M-Pesa",
          blocks: [
            {:p,
             "M-Pesa is how most third-party airtime services take payment, so a Faiba top-up bought online is usually an M-Pesa payment in shillings. The airtime then goes to the Faiba number you entered."},
            {:p,
             "Confirm the service carries Faiba before you pay — Faiba is the one network most general airtime services are least likely to support."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Faiba sits alongside four other networks — see [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya), or [buy airtime online in Kenya](/blog/buy-airtime-online-kenya) for a route that works across networks."},
            {:cta,
             %{
               text: "Buy Faiba airtime online — pay with M-Pesa, and it lands in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy airtime for another Faiba number?",
          answer:
            "Yes. The Faiba app supports buying airtime for your own line or another Faiba number, and some airtime websites carry Faiba too."
        },
        %{
          question: "Who runs Faiba?",
          answer:
            "Faiba is the consumer brand of JTL, a Kenyan telecommunications operator. That is why you will also see it called JTL Faiba."
        },
        %{
          question: "Why can some airtime services not top up Faiba?",
          answer:
            "Faiba has fewer subscribers than the big two networks, so not every aggregator carries it. Check before you pay."
        }
      ]
    }
  end

  # -------------------------------------------------------- spoke: Equitel

  defp equitel do
    %Post{
      slug: "buy-equitel-airtime",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Equitel",
      title: "Buy Equitel Airtime in Kenya",
      meta_title: "Buy Equitel Airtime in Kenya — Online and With M-Pesa",
      description:
        "How to buy Equitel airtime in Kenya — through Equity's own channels or an airtime website — for your own Equitel line or another Equitel number.",
      keywords: [
        "buy Equitel airtime",
        "buy Equitel airtime online",
        "Equitel airtime Kenya",
        "Equitel top up",
        "buy Equitel credit",
        "Equitel airtime with M-Pesa"
      ],
      intro: [
        "Equitel is the mobile virtual network operated out of Equity, which means it runs on another network's towers but is bought and topped up through Equity's own channels. You can top up your own Equitel line or another Equitel number.",
        "This page covers where Equitel airtime comes from, and how to buy it when you are not inside the Equity app."
      ],
      sections: [
        %{
          id: "ways",
          heading: "Ways to Buy Equitel Airtime",
          blocks: [
            {:p, "Equitel airtime is bought through:"},
            {:ul,
             [
               "Equity's own channels, including the Equity app and Equitel's menu.",
               "USSD, for buying without a data bundle.",
               "A third-party airtime website that carries Equitel, paid with M-Pesa."
             ]},
            {:p,
             "Because Equitel is tied to Equity, its airtime is naturally bought from inside the Equity ecosystem. If you are not an Equity customer, a third-party airtime service is the usual route."}
          ]
        },
        %{
          id: "another",
          heading: "Topping Up Another Equitel Number",
          blocks: [
            {:p,
             "Equitel supports topping up your own line and another Equitel number, so you can send airtime to someone else's Equitel phone from yours. The recipient's number is all you need."},
            {:p,
             "As with every network, the top-up is irreversible once delivered — check the number first."}
          ]
        },
        %{
          id: "mpesa",
          heading: "Buying Equitel Airtime With M-Pesa",
          blocks: [
            {:p,
             "M-Pesa is the payment method almost every third-party airtime service uses, so an Equitel airtime purchase bought online is usually an M-Pesa payment in shillings. Confirm the service carries Equitel before you pay."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Equitel is one of five Kenyan networks — see [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya), or [buy airtime for another number](/blog/buy-airtime-for-another-number) if that is what you are doing."},
            {:cta,
             %{
               text: "Buy Equitel airtime online — priced in shillings, paid with M-Pesa.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "What is Equitel?",
          answer:
            "Equitel is the mobile virtual network operated out of Equity. It uses another network's infrastructure but is sold and topped up through Equity's own channels."
        },
        %{
          question: "Can I buy Equitel airtime without an Equity account?",
          answer:
            "Yes — through a third-party airtime service that carries Equitel, paid with M-Pesa. Equity's own channels are the alternative if you bank with Equity."
        },
        %{
          question: "Can I top up another Equitel number?",
          answer:
            "Yes. Enter the recipient's Equitel number and the airtime is delivered to their line, the same as topping up your own."
        }
      ]
    }
  end

  # --------------------------------------------------------- spoke: M-Pesa

  defp mpesa do
    %Post{
      slug: "buy-airtime-with-mpesa",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "M-Pesa",
      title: "Buy Airtime With M-Pesa in Kenya",
      meta_title: "Buy Airtime With M-Pesa in Kenya — Menu, App and Online",
      description:
        "How to buy airtime with M-Pesa in Kenya — from the M-Pesa menu, the app, or a website paid with M-Pesa — for any network, including another number.",
      keywords: [
        "buy airtime with M-Pesa",
        "buy airtime from M-Pesa",
        "airtime via M-Pesa",
        "buy airtime using M-Pesa",
        "airtime M-Pesa Kenya"
      ],
      intro: [
        "M-Pesa is the default way to move money in Kenya, and buying airtime is one of its oldest features. Whether you use the USSD menu or the app, the airtime is sent to the number you choose, and you pay face value.",
        "This page covers the three ways to use M-Pesa for airtime — the menu, the app, and a website paid with M-Pesa — and what each one is best at."
      ],
      sections: [
        %{
          id: "menu",
          heading: "Buying Airtime From the M-Pesa Menu",
          blocks: [
            {:p,
             "The M-Pesa menu is reached on *334# and includes a Buy Airtime option. You select it, enter the number (yours or someone else's) and the amount, then confirm with your PIN. It works with no data bundle, which makes it the reliable fallback."},
            {:p,
             "This is the route to use on a feature phone, or when you have no data and no app."}
          ]
        },
        %{
          id: "app",
          heading: "Buying Airtime in the M-Pesa App",
          blocks: [
            {:p,
             "The M-Pesa app does the same job on a screen: choose Buy Airtime, pick the number and the amount, and confirm. It is faster than the menu when you already have the app open, and it keeps a record you can look back at."}
          ]
        },
        %{
          id: "online",
          heading: "Paying an Airtime Website With M-Pesa",
          blocks: [
            {:p,
             "When you buy airtime on a website rather than in M-Pesa itself, M-Pesa is how you pay. You enter the recipient's number and the amount on the site, then pay the total with M-Pesa; the site sends the airtime."},
            {:p,
             "This is the flexible route: it works across all the networks in one place, and it is the only one built for topping up several numbers at once."}
          ]
        },
        %{
          id: "fees",
          heading: "What It Costs",
          blocks: [
            {:p,
             "Airtime is face value with M-Pesa — KSh 100 buys KSh 100 of airtime — so the only thing to watch is whether the channel you use adds a fee. The M-Pesa menu and app do not; some third-party sites might."},
            {:p,
             "Your M-Pesa daily limit, which Safaricom sets and can change, caps how much you can spend in a day."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "For the full picture across networks and methods, read [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya). If you are topping up someone else, see [buy airtime for another number](/blog/buy-airtime-for-another-number). Paying for data with M-Pesa works the same way — see [buy Safaricom data with M-Pesa](/blog/buy-safaricom-data-with-mpesa)."},
            {:cta,
             %{
               text:
                 "Buy airtime for any Kenyan network online — pay with M-Pesa and it lands in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy airtime with M-Pesa for another number?",
          answer:
            "Yes. The M-Pesa menu and app both let you enter a number that is not your own, and airtime websites paid with M-Pesa do the same."
        },
        %{
          question: "Do I need data to buy airtime with M-Pesa?",
          answer:
            "No. The M-Pesa menu on *334# works with no data bundle. The app and websites need a connection."
        },
        %{
          question: "Is buying airtime with M-Pesa free?",
          answer:
            "The M-Pesa menu and app sell airtime at face value, with no added fee. Some third-party platforms charge a small convenience fee."
        }
      ]
    }
  end

  # -------------------------------------------------------- spoke: online

  defp online do
    %Post{
      slug: "buy-airtime-online-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Online",
      title: "Buy Airtime Online in Kenya",
      meta_title: "Buy Airtime Online in Kenya — Instant Top Up, Any Network",
      description:
        "How to buy airtime online in Kenya for any network — Safaricom, Airtel, Telkom, Faiba or Equitel — paid with M-Pesa and delivered in seconds.",
      keywords: [
        "buy airtime online Kenya",
        "airtime online Kenya",
        "online airtime top up",
        "instant airtime Kenya",
        "airtime top up online"
      ],
      intro: [
        "Buying airtime online means topping up a number from your phone or laptop without a scratch card, a shop or a queue — and without being tied to one network. You choose the network, enter the number, pick the amount and pay.",
        "This page covers what makes the online route different, and when it is the better choice than M-Pesa or a network app."
      ],
      sections: [
        %{
          id: "why",
          heading: "Why Buy Airtime Online",
          blocks: [
            {:p,
             "A shop or agent sells you airtime for the network they carry. An online airtime service carries all of them, which changes what you can do:"},
            {:ul,
             [
               "Top up any network from one place — Safaricom, Airtel, Telkom, Faiba or Equitel.",
               "Top up a number that is not yours, without needing that person's phone.",
               "Top up several numbers in one go, instead of one purchase each.",
               "Keep a receipt for every top-up instead of a paper slip."
             ]}
          ]
        },
        %{
          id: "steps",
          heading: "How It Works",
          blocks: [
            {:p, "The four steps are the same wherever you buy:"},
            {:ol,
             [
               "Choose the network.",
               "Enter the number you are topping up.",
               "Choose the amount in shillings.",
               "Pay with M-Pesa and keep the receipt."
             ]},
            {:p,
             "Airtime is delivered in seconds on a good service, and it is sold at face value — KSh 100 buys KSh 100, before any fee the service might add."}
          ]
        },
        %{
          id: "any-network",
          heading: "Any Network, One Place",
          blocks: [
            {:p,
             "The network is chosen per top-up, not per service. That is what makes the online route useful if your household is on three different networks, or if you are topping up a client on a network you do not use yourself."},
            {:p,
             "The one rule is irreversibility: airtime cannot be recalled, so read the number back before you confirm the payment."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "For the full picture, read [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya). If you are topping up someone else, see [buy airtime for another number](/blog/buy-airtime-for-another-number). The same walkthrough for data is in [buy data bundles online in Kenya](/blog/buy-data-bundles-online-kenya)."},
            {:cta,
             %{
               text:
                 "Buy airtime online for any Kenyan network — priced in shillings, paid with M-Pesa, delivered in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Is online airtime instant?",
          answer:
            "On a good airtime service, yes — the airtime is delivered within seconds of the payment."
        },
        %{
          question: "Can I buy airtime online for any network?",
          answer:
            "On a general airtime service, yes. You pick the network for each number, so Safaricom, Airtel, Telkom, Faiba and Equitel are all reachable from one place."
        },
        %{
          question: "Do I need an account to buy airtime online?",
          answer:
            "At our shop, yes — a Tangi account with a verified phone, the same gate checkout uses. It keeps the receipt and the buyer tied to a real number."
        }
      ]
    }
  end

  # ---------------------------------------------- spoke: another number

  defp for_another_number do
    %Post{
      slug: "buy-airtime-for-another-number",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "For someone else",
      title: "Buy Airtime for Another Number in Kenya",
      meta_title: "Buy Airtime for Another Number in Kenya — Send Top Up",
      description:
        "How to buy airtime for someone else in Kenya — send airtime to another number on any network, paid with M-Pesa, from your own phone.",
      keywords: [
        "buy airtime for another number",
        "buy airtime for someone else",
        "send airtime to another number",
        "buy airtime for another phone",
        "top up another number Kenya",
        "buy airtime for someone Kenya"
      ],
      intro: [
        "Sending airtime is one of the simplest ways to help someone in Kenya: you pay in shillings, and the top-up lands on their number. You do not need their phone, their PIN or their permission — you need their number.",
        "This page covers how it works across the networks, and how to avoid the one mistake that cannot be undone."
      ],
      sections: [
        %{
          id: "how",
          heading: "How to Buy Airtime for Another Number",
          blocks: [
            {:p, "Every channel in this cluster supports a recipient number:"},
            {:ol,
             [
               "Enter the recipient's number where the form asks for the number you are topping up.",
               "Choose the amount in shillings.",
               "Read the number back on the confirmation screen before the money moves.",
               "Pay — usually with M-Pesa — and keep the receipt."
             ]},
            {:p,
             "The confirmation step is not decoration. Airtime is irreversible, so naming the number back is the only protection there is."}
          ]
        },
        %{
          id: "who",
          heading: "When People Send Airtime",
          blocks: [
            {:p, "The reasons repeat across almost every order we see:"},
            {:ul,
             [
               "Family: keeping a parent, a sibling or a child's line topped up from a distance.",
               "Workers: a househelp, a watchman or a boda rider who needs airtime for calls, not cash.",
               "Students: a child at school on a line you manage.",
               "Clients and suppliers: topping up a number you deal with, without sending cash.",
               "Small favours: someone has no bundle and no way to buy one right then."
             ]},
            {:p,
             "Sending airtime rather than cash keeps the help specific — it does not disappear into other spending."}
          ]
        },
        %{
          id: "mistakes",
          heading: "The One Mistake You Cannot Undo",
          blocks: [
            {:p,
             "A wrong digit sends the airtime to a stranger, and no network or service can pull it back. There is no reversal, no refund and no way to trace it to you."},
            {:callout,
             "Read the number back, digit by digit, on the confirmation screen. It takes five seconds and it is the only safeguard that exists."},
            {:p,
             "If you buy the same numbers often, save them. A saved recipient removes the typo risk entirely, because you pick a name instead of re-typing digits."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "To see this in context, read [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya), or [buy airtime online in Kenya](/blog/buy-airtime-online-kenya) for the route that handles several numbers at once. Topping up someone's data instead is in [buy data bundles for another number](/blog/buy-data-bundles-for-another-number)."},
            {:cta,
             %{
               text:
                 "Buy airtime for another number — any network, paid with M-Pesa, with the number named back before you pay.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy airtime for another number in Kenya?",
          answer:
            "Yes. Enter the recipient's number instead of your own, on any of the networks, and the airtime is delivered to their line."
        },
        %{
          question: "Do I need the other person's permission?",
          answer:
            "No. A top-up needs only the number — the airtime lands on the line whether or not they ask for it."
        },
        %{
          question: "What happens if I send airtime to the wrong number?",
          answer:
            "It cannot be recalled or refunded. That is why the confirmation screen names the number back before any money moves."
        }
      ]
    }
  end

  # ------------------------------------------- spoke: without a shop

  defp without_a_shop do
    %Post{
      slug: "buy-airtime-without-going-to-shop",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "No shop needed",
      title: "Buy Airtime Without Going to a Shop in Kenya",
      meta_title: "Buy Airtime Without Going to a Shop — No Scratch Card",
      description:
        "How to buy airtime in Kenya without a scratch card, a shop or a queue — from your phone, with M-Pesa or USSD, on any network.",
      keywords: [
        "buy airtime without scratch card",
        "buy airtime from phone",
        "buy airtime without visiting shop",
        "electronic airtime Kenya",
        "airtime online without scratch card"
      ],
      intro: [
        "The scratch card is the oldest way to buy airtime and now the slowest: you have to find a shop that sells them, buy the card, then read the code in. Electronic airtime removes every one of those steps.",
        "This page is about buying airtime from where you are — no shop, no card, no queue."
      ],
      sections: [
        %{
          id: "no-scratch-card",
          heading: "Airtime Without a Scratch Card",
          blocks: [
            {:p,
             "Electronic airtime is airtime sent straight to a number, with no physical card involved. You buy it with M-Pesa, in a network app, by USSD or on an airtime website, and it appears on the line within seconds."},
            {:p,
             "Because there is no card, there is nothing to lose, scratch or mis-read — and nothing to carry. It is also the same price: airtime is face value either way."}
          ]
        },
        %{
          id: "no-queue",
          heading: "No Shop, No Queue",
          blocks: [
            {:p,
             "Buying from a shop means a trip, and the trip is the expensive part: the shop may be closed, may be out of the card you want, or may only sell one network. Buying from your phone removes all three problems at once."},
            {:ul,
             [
               "You can buy at any hour, not only when a shop is open.",
               "You are not limited to the networks one shop carries.",
               "You can top up someone else without going anywhere near their phone."
             ]}
          ]
        },
        %{
          id: "offline",
          heading: "When You Have No Data",
          blocks: [
            {:p,
             "If you have no data bundle, you are not stuck. USSD works over the network signal alone — the M-Pesa menu on *334# includes Buy Airtime, and the network's own menu can top up your line. No app, no data, no shop."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "See [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya) for every route, or [the best way to buy airtime in Kenya](/blog/best-way-to-buy-airtime-kenya) to compare them."},
            {:cta,
             %{
               text:
                 "Buy airtime from your phone — no scratch card, no shop, delivered in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Can I buy airtime without a scratch card?",
          answer:
            "Yes. Buy it with M-Pesa, in a network app, by USSD or on an airtime website — electronic airtime needs no card at all."
        },
        %{
          question: "Can I buy airtime with no data bundle?",
          answer:
            "Yes, by USSD. The M-Pesa menu on *334# and the network's own menu both work over the signal alone."
        },
        %{
          question: "Is electronic airtime more expensive?",
          answer:
            "No. Airtime is face value either way — KSh 100 buys KSh 100 whether it comes from a card or from your phone."
        }
      ]
    }
  end

  # ----------------------------------------------------- spoke: best way

  defp best_way do
    %Post{
      slug: "best-way-to-buy-airtime-kenya",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Comparison",
      title: "The Best Way to Buy Airtime in Kenya",
      meta_title: "The Best Way to Buy Airtime in Kenya — Compared",
      description:
        "The best way to buy airtime in Kenya depends on one thing: whether the number is yours. Compare M-Pesa, network apps, airtime platforms and shops.",
      keywords: [
        "best way to buy airtime Kenya",
        "easiest way to buy airtime Kenya",
        "cheapest way to buy airtime Kenya",
        "where to buy airtime Kenya",
        "best airtime app Kenya"
      ],
      intro: [
        "There is no single best way to buy airtime in Kenya — there is a best way for what you are doing. Topping up your own line is a different job from topping up three other people's, and the right tool changes with it.",
        "Here is the comparison, and the short version of which route to reach for."
      ],
      sections: [
        %{
          id: "compare",
          heading: "The Methods, Compared",
          blocks: [
            {:p,
             "Four routes cover almost every purchase. The columns that decide it are whether you can top up another number, and whether you need data."},
            {:table,
             %{
               head: ["Method", "Own number", "Other number", "Online", "M-Pesa", "USSD"],
               rows: [
                 ["M-Pesa menu or app", "Yes", "Yes", "No", "Yes", "Yes"],
                 ["Network app", "Yes", "Often", "Yes", "Varies", "No"],
                 ["Airtime platform", "Yes", "Yes", "Yes", "Yes", "Varies"],
                 ["Shop or agent", "Yes", "Yes", "No", "Varies", "No"]
               ]
             }}
          ]
        },
        %{
          id: "pick",
          heading: "Which One to Use",
          blocks: [
            {:ul,
             [
               "For your own line, fast: the M-Pesa app, or Buy Airtime in the M-Pesa menu.",
               "For your own line, with no data: USSD on *334#.",
               "For someone else's number: an airtime platform, which takes any network and a recipient number in one place.",
               "For several numbers at once: an airtime platform — one confirmation, one payment, many lines.",
               "For an emergency with no signal to spare: the M-Pesa menu, which needs the least."
             ]}
          ]
        },
        %{
          id: "cheapest",
          heading: "The Cheapest Way",
          blocks: [
            {:p,
             "Airtime is face value everywhere, so the cheapest route is simply the one that adds no fee. The M-Pesa menu and app add none, and so do good airtime platforms; some third-party services add a small convenience fee, which is the only thing that makes one route cost more than another."},
            {:callout,
             "Do not pay above face value for airtime. If a service charges a fee, that is fine — just know it is the fee, not the airtime, that you are paying for."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "Each route has its own guide — start with [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya), or jump to [buy airtime with M-Pesa](/blog/buy-airtime-with-mpesa) or [buy airtime for another number](/blog/buy-airtime-for-another-number). For the data side of the same decision, see [the best data bundles in Kenya](/blog/best-data-bundles-kenya)."},
            {:cta,
             %{
               text:
                 "Buy airtime for any Kenyan network — one confirmation, one M-Pesa payment, delivered in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "What is the easiest way to buy airtime in Kenya?",
          answer:
            "For your own line, Buy Airtime in the M-Pesa app or menu. For another number or several numbers, an airtime platform is easiest."
        },
        %{
          question: "What is the cheapest way to buy airtime in Kenya?",
          answer:
            "Whichever route adds no fee. Airtime is face value, so the M-Pesa menu and app — and platforms that do not charge — are the cheapest."
        },
        %{
          question: "Where can I buy airtime for any network in one place?",
          answer:
            "An airtime platform that carries Safaricom, Airtel, Telkom, Faiba and Equitel. You pick the network for each number."
        }
      ]
    }
  end

  # -------------------------------------------- spoke: buying on Tangi

  defp tangi do
    %Post{
      slug: "how-to-buy-airtime-with-tangi",
      cluster: @cluster,
      kind: :spoke,
      updated_on: @updated,
      eyebrow: "Step by step",
      title: "How to Buy Airtime With Tangi: Step by Step",
      meta_title: "How to Buy Airtime With Tangi in Kenya — Step by Step",
      description:
        "How to buy airtime on Tangi, step by step: pick a network, add one or more Kenyan numbers, and pay from your wallet or with M-Pesa.",
      keywords: [
        "how to buy airtime with Tangi",
        "buy airtime with Tangi",
        "Tangi airtime",
        "buy airtime app Kenya",
        "top up airtime with Tangi"
      ],
      intro: [
        "Tangi tops up any Kenyan line — Safaricom, Airtel, Telkom or Faiba — from a single screen. You choose the amount, add one or more numbers, and pay. Airtime is face value, so KSh 100 of airtime costs KSh 100, and it lands in seconds.",
        "You can pay from your Tangi wallet when it is funded, or straight from M-Pesa when it is not — you do not have to top up the wallet first. This is the whole walkthrough, with the real screens."
      ],
      sections: [
        %{
          id: "before-you-start",
          heading: "Before You Start",
          blocks: [
            {:p,
             "You need one thing: a Tangi account with a verified phone number. The person receiving the airtime does not need Tangi, and the phone being topped up does not need a data bundle."},
            {:p,
             "Airtime is sold at face value, so there is no markup to work around — KSh 100 buys KSh 100 of airtime, whether you pay from the wallet or from M-Pesa. The wallet balance sits at the top of the airtime screen, so you always know what you can spend before you decide."},
            {:image,
             %{
               src: "/images/airtime/wallet.png",
               alt: "The Tangi wallet card showing a balance of KSh 2,500",
               width: 716,
               height: 174,
               caption: "Your wallet balance, shown above the buy screen."
             }}
          ]
        },
        %{
          id: "step-by-step",
          heading: "Buying Airtime on Tangi, Step by Step",
          blocks: [
            {:p,
             "Open the airtime screen — from the Tangi app, or in a browser at [tangi.co.ke/airtime](/airtime). Everything below happens on that one screen."},
            {:image,
             %{
               src: "/images/airtime/pick.png",
               alt:
                 "The Tangi buy airtime screen with network badges, an amount field and a numbers field",
               width: 716,
               height: 1378,
               caption:
                 "The buy screen. Any network, one amount, and one or more numbers to top up."
             }},
            {:h3, "1. Choose the amount"},
            {:p,
             "Type the amount per number, or tap a quick chip — KSh 50, 100, 200 or 500. The amount applies to every number in the buy, so a mixed top-up is two separate buys."},
            {:h3, "2. Add the numbers"},
            {:p,
             "Type one number per line under \"Who's getting it?\" — your own, someone else's, or a list of both. Tangi recognises the network for each line automatically. Numbers you have used before appear under \"Recent numbers\"; tap one to add it back, or the × to forget it."},
            {:h3, "3. Read it back before you buy"},
            {:p,
             "As you type, Tangi lists every number it will top up, the network it has matched, and the running total. This is the last check before the money moves, and it is there for a reason: a top-up cannot be recalled."},
            {:image,
             %{
               src: "/images/airtime/review.png",
               alt:
                 "The Tangi buy screen filled in with two numbers at KSh 100 each and a KSh 200 total",
               width: 716,
               height: 1670,
               caption:
                 "Two numbers, KSh 100 each. Tangi shows the network for each line and the KSh 200 total before you confirm."
             }},
            {:callout,
             "A top-up cannot be recalled. Once the buy goes through, a wrong number means the airtime is gone — so read each number back on this step before you tap Buy airtime."}
          ]
        },
        %{
          id: "wallet-or-mpesa",
          heading: "Paying From Your Wallet, or With M-Pesa",
          blocks: [
            {:p,
             "If the wallet covers the total, tap Buy airtime and you are done — the airtime goes out without leaving the screen."},
            {:p,
             "If it does not, Tangi does not dead-end. It tells you the difference and offers to raise just that amount with M-Pesa, so you still buy in one go. Or you deposit more than the difference and keep the rest in the wallet for next time."},
            {:image,
             %{
               src: "/images/airtime/short.png",
               alt:
                 "The Tangi shortfall options: pay KSh 1,500 with M-Pesa, or deposit KSh 2,000 and keep KSh 500",
               width: 648,
               height: 604,
               caption:
                 "Wallet short? Pay only the difference with M-Pesa — or deposit a round amount, like KSh 2,000, and keep KSh 500 in the wallet."
             }},
            {:ul,
             [
               "Pay the difference — M-Pesa is charged only the shortfall, and the airtime goes out as soon as it clears.",
               "Deposit a round amount — against a KSh 1,500 difference, deposit KSh 2,000 and KSh 500 stays in your wallet.",
               "Fund first — top up the wallet up front and every later buy is a single tap."
             ]}
          ]
        },
        %{
          id: "after",
          heading: "What Happens After You Tap Buy",
          blocks: [
            {:p,
             "The airtime goes out straight away — each number receives its amount within seconds. The buy appears on the screen under \"On its way\", and the numbers you used are saved to \"Recent numbers\" so the next buy is quicker."},
            {:p,
             "A bulk buy tops up every number you added, so a long list can take a moment — but there is nothing else to do: no agent, no scratch card, and no code to read out."}
          ]
        },
        %{
          id: "another-number",
          heading: "Buying for Someone Else",
          blocks: [
            {:p,
             "Everything above works the same whether the number is yours or not — you simply type theirs. Airtime is a common way to help family, a househelp, a boda rider or a student, and on Tangi it is one screen rather than a trip to a shop."},
            {:p,
             "The full picture, including the rules that keep it safe, is in [buy airtime for another number](/blog/buy-airtime-for-another-number)."}
          ]
        },
        %{
          id: "next",
          heading: "Where to Go Next",
          toc: false,
          blocks: [
            {:p,
             "For the wider picture — every network and every way to pay — read [the complete guide to buying airtime in Kenya](/blog/buy-airtime-kenya). If you would rather pay with M-Pesa end to end, see [buy airtime with M-Pesa](/blog/buy-airtime-with-mpesa)."},
            {:cta,
             %{
               text:
                 "Buy airtime for any Kenyan network with Tangi — face value, paid from your wallet or with M-Pesa, delivered in seconds.",
               href: "/airtime",
               label: "Buy airtime"
             }}
          ]
        }
      ],
      faqs: [
        %{
          question: "Is buying airtime on Tangi instant?",
          answer:
            "Yes. Once you confirm, the airtime is sent to each number and usually arrives within seconds."
        },
        %{
          question: "Can I buy airtime for another number on Tangi?",
          answer:
            "Yes. Enter any Kenyan number, not just your own — you can add several in one buy, on any network."
        },
        %{
          question: "Do I have to top up my wallet before buying airtime on Tangi?",
          answer:
            "No. If the wallet cannot cover the total, Tangi lets you pay just the difference with M-Pesa, or deposit more and keep the change in the wallet."
        },
        %{
          question: "Does Tangi add a fee to airtime?",
          answer:
            "Airtime is face value — KSh 100 buys KSh 100 of airtime. There is no markup on the airtime itself."
        },
        %{
          question: "What happens if I enter the wrong number?",
          answer:
            "Airtime cannot be recalled. Read the number back on the review step before you confirm — once it is sent, a wrong number is not refunded."
        },
        %{
          question: "Can I buy airtime for several numbers at once?",
          answer:
            "Yes. Add one number per line and Tangi tops them all up in a single buy, with one total to confirm."
        }
      ]
    }
  end
end
