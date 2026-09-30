# Supplier outage

**Symptom.** An alert `supplier_error_rate`, or a panel slow or rejecting calls.
Placed orders stop moving; new placements land in `needs_review` or refund.

**How it is contained.** `add` is sent once and never retried (scope.md §5). A
definite rejection fails the order and refunds the wallet in one transaction; a
timeout or a garbled body goes to `needs_review` for a person. A read failure in
the status job only means the next minute tries again.

## Check

1. `/admin` → Health → **Placements succeeded**, and `/admin/suppliers` → each
   panel's last sync and balance.
2. `/admin/orders` → filter **Needs review**: these are orders the panel may or
   may not have accepted.
3. In the supplier's own dashboard, look for one of the `needs_review` orders by
   the id you would have sent.

## Act

- **A panel is rejecting everything (a bad key).** `CheckSupplierBalance` will
  report `Incorrect API key`. Rotate the key in `/admin/suppliers` → the
  panel's card → type the new key → Save, then press "Check balance", or pause
  the panel.
- **A panel is down or timing out.** Pause it: `/admin` → Suppliers, or let the
  next balance probe under the float do it. Paused lanes show "this grade is
  paused" before a customer pays, so the blast radius is new orders, not in-flight
  ones.
- **A batch of `needs_review`.** Open each in `/admin/orders`: if the panel has
  the order, **Attach** its id (the order becomes `placed` and keeps syncing); if
  it does not, **Refund** it. The customer is texted either way.
- **Repin lanes.** If a panel is out for good, an admin re-pins each grade to a
  lane on another panel in `/admin/catalog`. Stale lanes already came off sale on
  the last sync.
