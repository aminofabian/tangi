# Runbooks

What to do when something is wrong, and how to get the data back if it is worse.
Written for one operator, one BEAM node, managed Postgres (scope.md §16).

| Symptom | Runbook |
| --- | --- |
| A payment is stuck `pending`, or a customer says they paid and the order is not `paid` | [stuck-payment.md](stuck-payment.md) |
| A panel is down, slow, or rejecting calls | [supplier-outage.md](supplier-outage.md) |
| A panel's float is low and lanes are paused | [float-paused.md](float-paused.md) |
| The Malipo key is exposed or must be rotated | [malipo-key-rotation.md](malipo-key-rotation.md) |
| A settlement statement does not reconcile to a zero payout delta | [settlement-mismatch.md](settlement-mismatch.md) |
| Reviewing the money and identity paths before launch | [security-review.md](security-review.md) |

Alerts raised by `CheckAnomalies` name their kind — `settled_rate_drop`,
`failure_spike`, `otp_delivery_slip`, `supplier_error_rate`, `queue_backlog`,
`sms_spike`, `negative_margin`, `traffic_cliff` — and each maps to one of the
runbooks above.

## Backups and point-in-time recovery

The database is the business; the app is replaceable. Managed Postgres must run
with **daily automated backups and PITR enabled**, on a provider that keeps at
least **7 days** of WAL. Confirm in the provider console, not in a doc.

- **Verify the backup, do not trust it.** Once a week, restore the latest
  snapshot into a scratch database, run `mix ecto.migrate` against it, and open
  `/admin` to confirm the numbers load. An unverified backup is a rumour.
- **Know the two numbers:** recovery point objective (how much you can lose —
  with 7 days of WAL, minutes) and recovery time objective (how long a restore
  takes). Write the actual measured time here after the first rehearsal.
- **The wallet is the ledger.** If a restore loses the last minutes, the ledger
  is authoritative for what a customer is owed — reconcile any payment Malipo
  recorded that the restore lost by hand before telling a customer anything.

## Launch checklist

The exit criteria for the first real shilling (`scope.md` §17):

- [ ] **Brand and domain confirmed** (§16). The repo says ViewNinjas; the till
      name is what the customer sees on the M-Pesa prompt, so the two must match
      before the destination is confirmed in Connect.
- [ ] **Destination confirmed once in Connect** — till (Buy Goods), not paybill.
      Until it is confirmed, requests fail with `destination_inactive`.
- [ ] `SECRET_KEY_BASE`, `DATABASE_URL`, `CLOAK_KEY`, `MALIPO_SECRET_KEY` are set
      in the environment, never the repo. Set `MALIPO_WEBHOOK_SECRET` so callbacks
      are signed.
- [ ] `TEXTSMS_API_KEY` / partner / shortcode set, and the daily SMS cap is what
      you expect (`SMS_DAILY_CAP_MICROS`).
- [ ] `FX_SOURCE_URL` set, or the super-admin sets the rate by hand each morning.
- [ ] A super-admin account exists and holds the money knobs; a second admin
      exists for the review queue.
- [ ] `mix precommit` is green on the commit being deployed.
- [ ] **Rehearse key rotation** once (see [malipo-key-rotation.md](malipo-key-rotation.md))
      before you need it.
- [ ] One real end-to-end order at a small quantity: pay on a phone, watch it
      move `paid → placed → completed`, and confirm the SMS and the receipt email.
