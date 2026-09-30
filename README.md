# ViewNinjas

Social-media growth, priced in shillings, sold from a phone. A single Phoenix
1.8 / LiveView application — no separate frontend, no SPA, no Node in the
request path.

The design lives in [`docs/`](docs/):

- [`docs/scope.md`](docs/scope.md) — the architecture and the product.
- [`docs/build-plan.md`](docs/build-plan.md) — the milestone order (this repo is
  currently through **M12 — Hardening and launch readiness**).
- [`docs/runbooks/`](docs/runbooks/) — what to do when a payment is stuck, a panel
  is down, the float is low, a key must rotate, or a settlement will not reconcile.
- [`docs/environments.md`](docs/environments.md) — the environments, every
  environment variable, and what a super-admin sets in the back office instead.
- [`docs/malipo-connect.md`](docs/malipo-connect.md) — the M-Pesa integration
  notes used from M7.
- [`docs/brand.md`](docs/brand.md) — the Tangi palette, type and logo system.

## Requirements

- Elixir 1.18 / OTP 28
- PostgreSQL 16 (dev and test)

## Setup

```sh
mix setup          # deps, database, migrations, assets
```

`config/dev.exs` and `config/test.exs` connect as `postgres`/`postgres` on
`localhost`. Create that role once:

```sh
psql -d postgres -c "CREATE ROLE postgres WITH LOGIN CREATEDB PASSWORD 'postgres';"
```

or point the app elsewhere with `POSTGRES_USER`, `POSTGRES_PASSWORD` and
`POSTGRES_HOST`.

## Running

```sh
mix phx.server     # http://localhost:4000
```

`/health` returns `200 {"status":"ok"}` when the app and database are up, and
`503` otherwise. Structured (JSON) logs are enabled in production; development
and test keep the readable text formatter.

## Demo data

`mix ecto.setup` seeds the staff and customer accounts. To also put a real market
on the shop — three published offers, each with all three grades, and a customer
whose phone is verified and wallet is topped up — run:

```sh
mix run priv/repo/demo_market.exs
```

Idempotent, development only.

## Staff accounts

Public sign-up always creates a `:customer`. Admin and super-admin accounts
are created only from the command line:

```sh
mix viewninjas.create_admin \
  --email ops@example.com \
  --phone 0712345678 \
  --password "a long enough password" \
  --role admin        # or super_admin
```

The back office at `/admin` is role-gated: `admin` and `super_admin` get in, a
signed-in customer is bounced to the shop, and a signed-out visitor is sent to
log in.

## Checks

```sh
mix precommit      # compile (warnings as errors), format, test
mix credo --strict # lint
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs `mix format
--check-formatted`, `mix credo --strict`, `mix compile --warnings-as-errors`
and `mix test` against a Postgres service.

For the shell itself, [`scripts/visual/`](scripts/visual/README.md) renders the
running app and measures it — screenshots, the market → offer → checkout walk,
and a stylebook of every component. Dev-only; not part of CI.

## Configuration and secrets

No secrets in the repo — configuration comes from environment variables:

| Variable | Used by |
| --- | --- |
| `DATABASE_URL` | production database |
| `SECRET_KEY_BASE` | production cookie/session signing |
| `PHX_HOST` | production host |
| `SENTRY_DSN` | error reporting (disabled when unset) |
| `SENTRY_ENVIRONMENT` | error reporting environment label |
| `MAILGUN_API_KEY` / `MAILGUN_DOMAIN` | production transactional email |
| `MAILER_FROM` | From address on transactional email |
| `TEXTSMS_API_KEY` / `TEXTSMS_PARTNER_ID` | SMS (TextSMS) |
| `TEXTSMS_SHORTCODE` | SMS sender id, when provisioned |
| `SMS_DAILY_CAP_MICROS` | daily SMS spend cap (default 20 KES) |
| `CLOAK_KEY` | encrypts supplier API keys at rest (required in production) |
| `SECSERS_API_KEY` / `JAP_API_KEY` / `SMMFOLLOWS_API_KEY` | supplier panel keys |
| `<SLUG>_BASE_URL` | override a panel's base URL |
| `FX_SOURCE_URL` / `FX_SOURCE_PATH` | daily USD→KES rate (unset = job no-ops) |
| `MALIPO_SECRET_KEY` | Malipo Connect key (unset = payments refuse, `:not_configured`) |
| `MALIPO_BASE_URL` | Malipo base URL (defaults to `https://api.kiosk.ke`) |
| `MALIPO_WEBHOOK_SECRET` | verify the callback signature (optional) |
| `INSIGHT_HASH_SALT` | salt for the daily-rotating analytics visitor hash |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_HOST` | dev/test database |

Error reporting goes through the shared `ViewNinjas.Finch` pool
(`ViewNinjas.SentryFinchClient`) rather than bundling a second HTTP client.

## Deploying

A release and Dockerfile are generated (`rel/overlays`, `Dockerfile`), and
[`fly.toml`](fly.toml) targets Fly.io staging. Migrations run via the
`/app/bin/migrate` release command before the new version boots.

## What has shipped

**M0 — Foundation**

- Phoenix 1.8 + LiveView, Ecto/Postgres, Oban, Finch, per-environment config.
- `/health`, structured production logs, optional Sentry error reporting.
- The mobile app shell: one centred column, a fixed bottom tab bar
  (Shop, Orders, Wallet, Account), safe-area insets, the dynamic viewport unit,
  and a web app manifest with maskable icons — installable as a PWA.
- CI: formatting, Credo, and tests.

**M1 — Authentication and identity**

- Email + password registration with a **required phone**, plus login, account
  settings (email, phone, password) and password reset by email.
- `ViewNinjas.Accounts.Phone` — one phone normalizer, shared forever: every
  spelling collapses to `254…`.
- A `role` on every user (`customer` | `admin` | `super_admin`), enforced in the
  router through role-gated `live_session` hooks; staff roles exist only via the
  mix task above.
- Rate limiting per IP and per phone/identifier on sign-up and login
  (`ViewNinjas.RateLimit`, Hammer/ETS).

**M2 — SMS and phone verification**

- A verify screen at `/users/verify-phone`: texts a 6-digit code, takes it back
  with `autocomplete="one-time-code"`, shows a visible resend countdown, and
  says plainly when a number is locked out.
- The code is 5 minutes old at most, good for 3 attempts, single use, with a
  60-second resend throttle and per-number and per-IP caps.
- The plaintext code is never stored: the challenge keeps an HMAC, and the
  `DeliverOtp` Oban worker generates and sends it.
- `sms_messages` records every send, provider reference, status and cost; a
  daily spend cap refuses to send and raises an alert when the day's budget is
  gone, and delivery reports arrive at
  `POST /webhooks/textsms/sms`.

In development SMS is written to the log (so you can read the OTP locally); set
`TEXTSMS_API_KEY` and `TEXTSMS_PARTNER_ID` to send real messages. Production
always uses TextSMS, so an OTP can never end up in a production log.

**M3 — Supplier boundary**

- Panel rows (`secsers`, `jap`, `smmfollows`) with the API key **encrypted at
  rest** (`Cloak`, `CLOAK_KEY`) and capabilities as data, not branches.
- `ViewNinjas.Suppliers.Panel` — the one behaviour — and a single
  `ViewNinjas.Suppliers.V2` client that speaks the shared dialect (form body,
  `action` + `key`, JSON back). Errors normalize to a few clear terms, so a
  wrong key becomes one sentence, not a stack trace.
- `balance` and `services` run as Oban workers; nothing calls out from a page.
- Ingestion is **wholesale and unfiltered**: every service a panel sells lands in
  `supplier_services`, upserted by `(supplier, external_id)`, and anything
  missing from a pull goes inactive rather than being deleted.
- Back office at `/admin/suppliers`: each panel's float and sync state, the raw
  ingested catalog, and the manual "prove the keys work" triggers. A panel's base
  URL, key, `active` flag and capabilities are edited on the same screen (the key
  is never shown back), and a fourth panel can be added as a row plus a key.

Set the panel keys up from the environment (the bootstrap) with:

```sh
SECSERS_API_KEY=... JAP_API_KEY=... SMMFOLLOWS_API_KEY=... \
  mix viewninjas.suppliers.setup --activate
```

Then check `/admin/suppliers` as an admin: edit a panel, press "Check balance"
and "Sync services".

**M4 — Catalog and curation**

- The catalog workspace at `/admin/catalog`: the whole ingested inventory, with
  search and filters for panel, category, refill, cancel, shortlist and a
  computed KES ceiling — the ceiling filter runs the same integer arithmetic as
  the pricer, and a test holds the two to the cent.
- The three-tier selection model — **ingested → shortlisted → published** — and
  only the third is visible to a buyer. Shortlisting is a reading aid that
  changes nothing a buyer sees.
- `Offer` (a platform + outcome, unique) and `Lane` (an offer + grade, backed by
  one pinned service, unique on `(offer, grade)`). Pin a service as Cheap,
  Moderate or Quality, price it, publish it — one sitting, no re-sync.
- Suggestions (cheapest refillable, cheapest of any kind, closest name) rank
  candidates without ever publishing them.
- A lane whose pinned row changed price, bounds or active flag is flagged stale
  by the next sync; re-pinning acknowledges it.

`ViewNinjas.Pricing` is the integer quote engine (`scope.md` §7): one flat
margin over landed cost, no floats, and the §7 worked example — `0.90` USD/1,000
at FX `129.40` for 1,000 units → **KSh 276** — is a test.

**M5 — Pricing engine and settings**

- `pricing_settings` as **append-only versions** — margin, buffer, an optional FX
  override, rounding, actor, reason, effective at. The pricer reads the newest
  version; nothing is edited in place, and every change is audited.
- `fx_rates` as an append-only series: a daily job's rows and a super-admin's
  manual override, each recording its source. The pricer's effective FX is the
  settings override, else the newest rate, else the §7 default.
- A super-admin screen at `/admin/pricing` (the `:super_admin` role, held apart
  from ordinary admins) changes the knobs and records the rate. A change
  broadcasts over PubSub, so an open catalog screen re-quotes itself.
- The **guardrail**: a lane whose price sits at or under landed-plus-buffer
  cannot be published. Pinning still saves it, unpublished, and says why.
- The daily `FetchFxRate` job reads a configured source; with no `FX_SOURCE_URL`
  it no-ops, so the app prices from the last rate or the §7 default.

The knobs live in the database now, not config. `ViewNinjas.Pricing` takes a
`Pricing.Params` value object, so a quote is reproducible from a snapshot and the
catalog's SQL ceiling filter runs the same arithmetic as the Elixir pricer (a
test holds them to the cent, under raised knobs too).

**M6 — The market and the app shell**

- The **market** at `/` (public) and `/shop`: the pitch, the three grades in
  plain language, platform chips, and offers with a real from-price pulled from a
  published lane. An offer with no published lane is not shown at all.
- The **offer page** at `/offers/:id`: three grade cards with their bounds and
  refill, a link field, a quantity, and a live total in whole shillings. The
  total is a promise, not a charge — no `add`, no money until M7.
- The link is untrusted input (`ViewNinjas.Links`): trimmed, length-limited and
  `https`-only. We never fetch it, so there is no SSRF surface.
- **The shell, for real:** the four tabs — Home, Shop, Orders, Account — with
  Wallet folded into Home and Account; skeleton states instead of spinners; and a
  push/pop slide on live navigation. (LiveView 1.2 ships no View Transitions hook
  of its own, so `app.js` animates the incoming view in the direction of travel;
  the keyframes are in `app.css`.)
- **The buyer dashboard, stubbed:** signed in, Home shows the wallet card, the
  six-stat strip and the orders list — each a skeleton rather than a fake zero,
  until M7–M9 fill them in.
- **First-party page views, collect-only:** `page_views` rows for the market,
  the offer page and "checkout started", with a daily-rotating `visitor_hash`
  and no stored IP, cookie or third party. Nothing reads them until M10 — but the
  history starts now.

**M7 — Money in**

- The **ledger** (`ledger_entries`) is append-only and signed; the wallet balance
  is the **sum**, never a column. A correction is a new, opposite entry.
- `Order`, `OrderEvent` and `Payment` are created **fully shaped**. An order
  snapshots the retail, USD cost, margin, buffer and FX row it was priced with, so
  a later change to the knobs (or to the pinned service) never moves a price a
  customer already paid — there is a test for exactly that.
- The **Malipo client** (`ViewNinjas.Payments.Malipo`) is a thin Req-over-Finch
  module with normalized errors; with no key it returns `:not_configured` rather
  than prompting. Tests drive an in-memory rail, so nothing reaches the network.
- **One rule, enforced everywhere: money moves only when a confirming
  `GET /v1/payments/{id}` says `settled`.** The callback controller answers `2xx`
  fast, treats the body as a hint (it only asks for a confirmation, and acks an id
  it does not know so Malipo stops retrying), and optionally verifies the
  `X-Malipo-Signature` against the raw body. `ConfirmPayment` polls with `unique`
  on the payment id and snoozes until the prompt window closes, then cancels
  without deciding — only the rail knows the outcome. `SweepPendingPayments` runs
  every minute as the backstop, bounded at both ends.
- **Two flows:** pay-this-order with M-Pesa, and pay-from-wallet (a debit and the
  `paid` state in one transaction, with a row lock so two taps cannot both pass).
  A retry is a **new** attempt with a new idempotency key. Every settlement is
  idempotent: a replayed callback cannot double-credit, and a partial unique index
  on the ledger says so in the database.
- `/checkout/:order_id` with the **full-screen M-Pesa sheet** (§12): one calm
  instruction, the amount, a waiting state fed by PubSub, and a retry that never
  sends a second prompt. `/wallet` shows the derived balance, the ledger and a
  top-up. The phone must be verified first, because that is where the prompt goes,
  and payment creation is rate-limited per customer and per phone.

**M8 — Fulfilment**

- **The one `add`.** A paid order becomes a `PlaceOrder` job, with `max_attempts:
  1` and an Oban `unique` window on the order id, so a retry, a redeploy or a
  second tap cannot send a second order to the supplier. The job runs the whole
  way on `:paid` only, and never once the order has left it.
- **The supplier's words are translated, not trusted.** `SupplierStatus` maps the
  panel's status strings onto our own states (`Pending` → `placed`, `In progress`
  → `in_progress`, `Completed` → `completed`, and so on); an unknown word keeps
  the state we already had and is stored raw in `orders.supplier_status`.
- **A definite rejection refunds in the same transaction.** If `add` answers with
  a rejection (`{:api_error, _}` or a `4xx`), the order goes `failed` and the
  wallet is credited back together — a single `Repo.transact`, so the refund can
  never happen without the failure, nor twice.
- **Anything ambiguous waits for a person.** A transport error, a `5xx`, an
  unparseable body, or a pinned service that no longer resolves leaves the order
  `needs_review` — visible in the list, never re-`add`ed.
- **Status comes back on a schedule.** `SyncOrderStatuses` runs every minute, asks
  each supplier about its open orders in one batch (chunked to the panel's
  `multi_status_limit`), and writes `start_count`, `remains` and the charge back
  onto the order. A charge reported in anything but USD is kept raw and **never
  converted on a guess**; it is logged loudly instead.
- **The customer sees it move.** `/orders` lists everything bought, newest first,
  and `/orders/:id` shows the details, the M-Pesa receipt and a timeline built
  from the order's `OrderEvent` rows. A status change is broadcast over PubSub
  **carrying the fresh row**, so a page renders the new state without a second
  read, and the pill changes in place.

**M9 — After the sale**

- **A partial refunds itself.** When a panel reports `Partial`, the order moves to
  `partial` and the undelivered share goes back to the wallet in the same
  transaction, at the KES-per-unit captured on the order — so a later change to
  the knobs cannot move the refund (scope.md §6). A unique index on
  `ledger_entries (order_id, reason)` makes it impossible to credit an order
  twice; the code checks first, because a violation would abort the transaction.
- **Refills, the promise on the tin.** A completed order whose lane was sold with
  `refill: true` shows one button. The one `refill` call runs from a job, `unique`
  on the refill id, and a minute-by-minute `SyncRefillStatuses` poll reads it to
  `Completed` or `Rejected`. Rejected is terminal: the unique index on `refills`
  means an order is never refilled twice.
- **A supplier float that fails no one.** The balance probe pauses a panel under
  its configured USD floor (`suppliers.paused_at`) and raises an alert, so a lane
  pinned to it shows **"this grade is paused"** before a customer pays rather
  than failing after — and `Orders.create_order/1` refuses a paused lane server
  side too. A panel back above the floor resumes.
- **Stale lanes come off sale.** A price or bounds change flags the lanes pinned
  to the moved row *and* unpublishes them, with an alert — an admin re-pins (which
  clears the stale flag) to put it back (scope.md §9, §10).
- **An admin review queue** at `/admin/orders` filters `needs_review` and
  `partial`. A `needs_review` order is reconciled by hand: attach the supplier's
  order id when it did exist, or refund it when it never did. A `partial` shows
  what was credited back automatically.
- **A first overview** on `/admin`: the order funnel paid → completed, payments
  settled/failed/pending, the money still at risk, the real margin per ISO week
  (retail against the panel's charge at each order's own snapshot FX), and any
  alert raised while the screen is open. Profit trends, targets and traffic are
  M10's job.

**M10 — Insight**

- **The P&L** (`ViewNinjas.Profit`): revenue recognised once per captured order —
  whether it was paid by prompt or from the wallet — net of refunds, against cost
  of goods at **each order's own snapshot FX** (the panel's real `charge`, or the
  priced estimate until it lands), the reconciled Malipo fee, SMS, and the fixed
  costs. Reported for today, this week and this month, with the break-even line.
- **Settlement reconciliation** (`ViewNinjas.Settlement`) at `/admin/settlements`:
  paste a Malipo statement, land it raw, and read the four buckets — matched,
  amount mismatch, provider only, local only — and the payout delta. A matched
  line writes the reconciled `payments.fee_cents`; every other bucket is a flag
  for a person, never an automatic ledger write.
- **Progress** (`ViewNinjas.Progress`): targets for revenue, orders, new customers
  and margin against the actual, with the delta and the days left, plus the
  settled-order streak and the 30-day repeat rate. **Super-admin only**, with
  costs, at `/admin/costs`.
- **First-party traffic** (`ViewNinjas.Traffic`) over the `page_views` accrued
  since M6: visits and uniques, the funnel home → offer → checkout → settled →
  placed with the biggest leak called out, sources from `utm_*`/referrer, device
  class, and the viewed-against-bought gap per offer. No cookie, no third party,
  no stored IP.
- **`analytics_daily`**, a rebuildable daily rollup written by `RollupDaily`.
- **The Sunday message** (`ViewNinjas.Digest`): the week's profit, orders, new
  customers, conversion, the best lane and the anomalies, emailed to every
  super-admin — the same content the insight screen previews, so the two cannot
  drift. **Anomaly alerts** (`CheckAnomalies`) watch the settled rate, failure
  spikes, OTP delivery, a lane gone negative and a traffic cliff.
- **The insight screen** at `/admin/insight`, super-admin only: profit, progress
  and traffic on one page, and the digest previewed at the foot of it.

**M11 — Notifications and receipts**

- **The customer is told, and is not left refreshing.** A transactional SMS goes
  out when an order is `paid`, `completed`, `refunded`, or partly delivered, and
  **an email receipt** carries the M-Pesa code. `ViewNinjas.Notifications`
  composes the message and `NotifyOrder` sends it, so no rendered page ever makes
  the call (scope.md §13).
- **Preferences, whole.** `/account` carries the switches: text me about my
  orders, email me a receipt, and quiet hours (`21:00-07:00`, blank for any time)
  — one `notification_preferences` row per channel, with both channels on until a
  customer says otherwise.
- **Opt-out honoured, quiet hours snoozed.** A silenced channel is skipped; a
  quiet-hours SMS is **snoozed**, not dropped, and arrives when the window
  closes. Quiet hours are read in the customer's clock (Africa/Nairobi), not the
  server's.
- **SMS volume on the dashboard**, and `CheckAnomalies` raises an `:sms_spike`
  when a day's volume runs far ahead of the week.

**M12 — Hardening and launch readiness**

- **The security pass, with two fixes.** Reviewing the money and identity paths
  against scope.md §13 turned up two real bugs. **A settled `GET` no longer moves
  money unless the amount — and the phone, where the rail reports one — matches the
  attempt** (`Payments.verify_attempt/2`; a mismatch fails the payment and raises
  an alert). And the **payment rate limits had no default**, so checkout would have
  raised a `KeyError` outside test; they exist now and an unknown limit name fails
  loudly. The full audit is [`docs/runbooks/security-review.md`](docs/runbooks/security-review.md).
- **The customer's timeline names no supplier.** `OrderEvent` reasons are neutral,
  so no panel name and no supplier order id can reach a customer screen — and
  `customer_privacy_test.exs` walks every customer page asserting exactly that
  (scope.md §17).
- **Observability** (`ViewNinjas.Observability`): the settled rate, the OTP delivery
  rate, the placement error rate and the Oban queue lag, on the admin dashboard and
  read by `CheckAnomalies` to alert on. `supplier_error_rate` and `queue_backlog`
  joined the checks.
- **Runbooks** for the five ways this breaks — a stuck payment, a supplier outage,
  a paused float, a Malipo key rotation, a settlement mismatch — plus backups and
  PITR, and the launch checklist ([`docs/runbooks/`](docs/runbooks/)).
- **The promise in the open** at `/refunds`: undelivered quantity comes back as a
  wallet credit, no M-Pesa reversal in v1, and the platform risk stated plainly —
  no claim of a network partnership, no claim that every unit is a person. Linked
  from the offer page and Account.
- **Settings in the back office**, at `/admin/settings` (super-admin only): the
  rail key, the SMS credentials, the FX source, the visitor-hash salt and the
  mailer From are stored **encrypted** and set there, with the environment as the
  fallback and the default behind that. A secret is never shown back. The
  bootstrap values — `DATABASE_URL` and Postgres, `SECRET_KEY_BASE`, `CLOAK_KEY`,
  `PORT`, `PHX_HOST` — stay in the environment, because they are needed before the
  database is reachable. See [`docs/environments.md`](docs/environments.md).

The launcher: **M13 — Later, only if phase 2 is earning** (drip, Astro marketing
pages, Swahili, a customer API) — see
[`docs/build-plan.md`](docs/build-plan.md).
# tangi
