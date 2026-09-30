# Security review — the money and identity paths

The `scope.md` §13 checklist, read against the code before the first real shilling.
Each line names where it is enforced and the test that holds it.

## Supplier keys

- `suppliers.encrypted_api_key` is a Cloak field, exposed as `api_key` and marked
  `redact: true`, so it never renders in an inspect or a log.
  `ViewNinjas.Suppliers.Supplier`; the vault key is `CLOAK_KEY` at runtime.
- Keys are read only inside the panel client, which runs only from Oban workers.

## Outbound HTTP

- The supplier client (`Suppliers.V2`) and the Malipo client are called from
  workers — `PlaceOrder`, `RefillOrder`, `SyncOrderStatuses`, `SyncRefillStatuses`,
  `CheckSupplierBalance`, `SyncSupplierServices`, `CreatePayment`, `ConfirmPayment`,
  `NotifyOrder` — never from a LiveView render.
- **No customer link is ever fetched.** `ViewNinjas.Links` only decides whether we
  are willing to store and forward it: `https` only, length-limited to 300, and a
  URL that parses. There is therefore no SSRF surface to forge; the test is in
  `links_test.exs`.

## Malipo callbacks

- The callback handler (`MalipoCallbackController`) answers `2xx` fast and does the
  real work in Oban. The body is a **hint**: it only names a payment to confirm.
- A replayed or forged POST cannot settle anything, because only a confirming
  `GET` that says `settled` moves money (`ConfirmPayment`).
- `X-Malipo-Signature` is verified against the raw body when
  `MALIPO_WEBHOOK_SECRET` is set, using `Plug.Crypto.secure_compare`.
- **The amount — and the phone, when the rail reports one — must match the
  attempt** (`Payments.verify_attempt/2`), or the settlement is refused, the
  payment is failed and an alert is raised. This was a gap found in M12 and fixed;
  `payment_workers_test.exs` covers it.

## Secrets

- `MALIPO_SECRET_KEY`, `MALIPO_WEBHOOK_SECRET`, `CLOAK_KEY`, `SECRET_KEY_BASE`,
  `DATABASE_URL`, `TEXTSMS_*` are read from the environment in `config/runtime.exs`
  and are absent from the repo. The development Cloak key in `config/config.exs`
  is labelled dev-only.

## Pricing and money knobs

- Super-admin only (`live_session :super_admin`), append-only rows with an actor
  and a reason, and an order keeps the settings it was priced with.

## Abuse

- Rate limits on sign-up, login, OTP and payment creation
  (`ViewNinjas.RateLimit`). **M12 fix:** the payment limits had no default and
  raised a `KeyError` outside test, where the per-environment map is empty — a
  missing limit would have crashed checkout. Defaults now exist and an unknown
  name raises loudly (`rate_limit_test.exs`).
- The daily SMS cap refuses sending past a budget and alerts.

## Staff and customer visibility

- Staff actions write an `OrderEvent` or a ledger reason; there is no silent edit,
  and no "edit the wallet column".
- Customers see only their own orders (`Orders.get_order_for_user/2`), and
  supplier ids and panel names are kept off customer screens — the order timeline
  reasons are neutral, and `customer_privacy_test.exs` walks every customer page
  asserting no panel name and no supplier order id appears.

## Analytics

- First-party only: a daily-rotating `visitor_hash`, no cookie, no stored IP, no
  third-party script (scope.md §6, §13). Aggregates cannot name a person.
