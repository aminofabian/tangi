# Malipo key rotation

**When.** The secret key is exposed (a screenshot, a log, a machine you no longer
trust), the account is being handed over, or as the rehearsal before launch
(scope.md §17).

**What rotates.** Two secrets and one destination:

| Secret | Env var | Where it is read |
| --- | --- | --- |
| Payment API key | `MALIPO_SECRET_KEY` | `config/runtime.exs` → `ViewNinjas.Payments.Malipo` |
| Callback signing secret | `MALIPO_WEBHOOK_SECRET` | `ViewNinjasWeb.MalipoCallbackController` |
| Destination (till) | set once in Connect | the rail, not our config |

Nothing else changes: supplier keys are a separate axis (Cloak), and rotating a
Malipo key does not touch them.

## Rehearse it (dry run, no traffic)

1. Generate/fetch the new key in Malipo; do **not** revoke the old one yet.
2. Set `MALIPO_SECRET_KEY` to the new value and restart the node.
3. `CheckSupplierBalance` is unrelated; instead start one **small real order** and
   confirm the prompt is created (`payments.malipo_payment_id` is set, status
   `pending`). This proves the new key authenticates.
4. If the webhook secret changed too, set `MALIPO_WEBHOOK_SECRET` and confirm a
   test callback with a matching `X-Malipo-Signature` is accepted and a bad one is
   rejected with `400`.
5. Only then revoke the old key at Malipo.

## If the key was exposed

1. **Revoke first, then think.** A leaked live key can create payments against
   your till. Revoke it in Malipo, then set the new one and restart.
2. Sweep anything between the exposure and the revoke: `select * from payments
   where inserted_at > <when exposed>;` Look for payments we did not create and
   for prompts to numbers that are not customers. Those are a Malipo support
   matter; if money actually moved, it is a ledger decision — never a silent
   edit.
3. Rotate `MALIPO_WEBHOOK_SECRET` too: if the key leaked, the signing secret may
   have leaked with it.
4. Note what happened and when. The customer-facing record is the ledger, not a
   chat message.
