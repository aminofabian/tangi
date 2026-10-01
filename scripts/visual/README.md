# Visual checks

Dev-only scripts that render the running app in a real Chrome so the shell can
be reviewed and measured, rather than guessed at from the markup.

Nothing here ships: no build step depends on it, and `node_modules` is ignored.

## Setup

```sh
cd scripts/visual
npm install
mix phx.server      # in another shell
```

They use `puppeteer-core` against a Chrome you already have (it looks in
`CHROME_PATH`, then the usual macOS and Linux locations, then the puppeteer
cache). If it cannot find one:

```sh
CHROME_PATH='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome' node shot.js …
```

## `shot.js` — one screen

```sh
node shot.js http://localhost:4000/ out.png            # 390×844 @2x
node shot.js http://localhost:4000/ out.png --full     # whole page
node shot.js http://localhost:4000/ card.png --at ".vn-card"
node shot.js http://localhost:4000/ out.png --measure  # computed layout + overflow
node shot.js http://localhost:4000/wallet out.png \
  --login customer@example.com:password
```

`--measure` is the useful one: it prints the viewport, any element wider than it
(real horizontal-overflow bugs), and the computed box/type of the interesting
selectors. Measure before you "fix" a screenshot.

## `journey.js` — the money path

```sh
mix run priv/repo/demo_market.exs    # demo offers + a customer who can pay
node journey.js ../../.shots
```

Walks market → filtered market → offer → below-minimum validation → checkout →
orders → wallet → account, writing a screenshot per step. It logs in through the
real password form, so it exercises the authenticated screens too.

## `tour.js` — every back-office screen

```sh
node tour.js                                  # http://localhost:4000 → ../../.shots/tour-*
node tour.js http://localhost:4010 ops@example.com:pw ../../.shots/x
```

Logs in **once** and then walks all nine `/admin` sections at a desk viewport,
then the same shell at 390×844, then one screen scrolled to its foot. Use it
instead of a run of `shot.js --login` calls: the app rate-limits the password
form per IP, and after a few tries `shot.js` starts quietly capturing the login
page. The tour avoids that by reusing one session.

## `stylebook.js` — every component

```sh
node stylebook.js http://localhost:4000/ stylebook.png
node stylebook.js http://localhost:4000/ sheet.png --at ".vn-sheet"
```

Injects a sample of every shell component into a live page and screenshots it, so
the whole stylesheet — including states that need real data or a live socket —
can be reviewed in one pass.

## `og.js` — the social share card

```sh
cd scripts/visual
node og.js                             # → ../../priv/static/images/og-image.png
node og.js /tmp/card.png               # somewhere else
```

Renders `og.html` to the 1200×630 PNG that Facebook, X/Twitter, LinkedIn and
WhatsApp crop to, and that every page points at through `ViewNinjasWeb.SEO`.
This one does **not** need the dev server: it screenshots a local file. Re-run it
after a brand or copy change and commit the result — nothing in the build depends
on it.

## Why the page needs settling

Two things will bite you when scripting this app:

1. **LiveView re-renders on mount.** Typing into a form before the socket has
   connected loses the edit. `lib/browser.js` types, checks the value stuck, and
   retries.
2. **The error flash always renders headlessly**, because the scripted browser
   never holds a LiveView socket. `settle()` removes `#flash-group` so it does
   not cover the design. That also means a screenshot will never show you a
   validation error — capture those deliberately, before `settle()`.
