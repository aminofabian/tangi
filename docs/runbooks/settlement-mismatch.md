# Settlement mismatch

**Symptom.** `/admin/settlements` shows lines in `amount_mismatch`, `provider_only`
or `local_only`, or the **payout delta** is not zero (scope.md §10;
docs/malipo-connect.md §10).

**How it reconciles.** The statement is landed raw, matched inside its own window,
and the fee is written only on a `matched` line. Nothing else moves automatically —
`provider_only` and `local_only` are flags for a person.

## Check

1. Open `/admin/settlements`, paste the statement for the settlement day, enter
   the amount the till or bank actually received, and read the four buckets and
   the delta.
2. **A non-zero delta is the number that cannot be argued with.** It is
   `sum(net_cents)` on the statement minus what arrived.

## Act, by bucket

- **`amount_mismatch`.** The gross on the statement differs from our
  `payments.amount_cents`. Nearly always a partial or a top-up counted twice.
  Compare the receipt on our payment with the statement's; the truth is the
  receipt. No fee is written until it matches by hand — investigate, do not force.
- **`provider_only`.** The statement has a settled payment we have no row for.
  Usually a payment whose callback was missed **and** whose sweep gave up. Confirm
  it in Malipo; if a customer is owed an order, treat it as a new order paid from
  a credit — the ledger gets a new row, never an edit to an old one.
- **`local_only`.** We think it settled and the statement has no line. Nine times
  in ten it is the cut-off (M-Pesa settles next business day, so a Friday payment
  lands on Monday — the window plus margin usually catches it) or a refund already
  reversed. It is a queue, not an accusation. Only escalate if it is old.
- **Never un-settle a payment to make the numbers agree.** If a statement
  contradicts a `settled` payment, a person resolves it; the ledger only ever gets
  a new, opposite entry (scope.md §6).

## After

A clean day reconciles to a **zero payout delta**. If it does not, the delta is
the first thing to chase, ahead of any bucket — a missing bank credit outranks a
mis-booked fee.
