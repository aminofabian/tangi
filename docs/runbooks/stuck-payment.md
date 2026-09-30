# Stuck payment

**Symptom.** A payment sits `pending`, or a customer says they paid and their
order is still `awaiting_payment`.

**How money moves here.** Only a confirming `GET /v1/payments/{id}` that says
`settled` moves money (scope.md §8). A callback is a hint; the sweep is the
backstop. So a stuck payment is almost always a missed or slow confirmation, not
a lost payment.

## Check

1. `/admin` → Health → **Payments settled**. If the settled rate has dropped,
   the rail is the problem: open Malipo and check status.
2. `psql` → `select id, status, malipo_payment_id, receipt, inserted_at from
   payments order by inserted_at desc limit 20;`
3. For the payment in question, `GET` its status from Malipo with the same key the
   app uses. Three outcomes:
   - **settled** — the confirmation was missed. Re-run `ConfirmPayment` for that
     payment id: `Oban` → insert a job, or wait for `SweepPendingPayments`, which
     runs every minute over the last hour.
   - **failed** — record it; the order stays retryable and the customer can try
     again. Do **not** mark it paid.
   - **still pending** — the customer has not entered their PIN. Leave it; the
     prompt closes and the sweep decides with the rail.

## Act

- Never hand-edit `payments.status` or `orders.state`. If the rail says settled
  and the confirming `GET` will not settle it, that is a Malipo incident, not a
  database edit.
- If the payment is older than an hour and the rail says settled but our rows
  disagree, the sweep has given up on purpose — a person decides. Record a ledger
  `:adjustment` only if you are crediting a customer you are certain paid; say why
  in the reason.
- The customer sees the truth on `/orders/:id`; the M-Pesa receipt is on the
  payment the moment it settles.
