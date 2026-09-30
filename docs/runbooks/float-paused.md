# Float paused (a panel is short)

**Symptom.** An alert `supplier_paused: <slug> paused: balance <n> USD is under
the float`. Lanes pinned to that panel show **This grade is paused** on the offer
page, and new orders on them are refused before payment (scope.md §10).

**Why it works this way.** Running out of float mid-order is how a paid customer
gets failed after the fact. Pausing **before** payment turns that into one grade
being unavailable, which is honest and cheap.

## Check

1. `/admin/suppliers` → the paused panel's balance and when it was last probed.
2. The float floor is `low_balance_micros` in `config/config.exs` (default USD
   5.00). Confirm it is what you intend.

## Act

- **Top the panel up.** Pay the supplier. The next `CheckSupplierBalance` (from
  the five-minute float pass) sees a balance above the floor and resumes the panel
  automatically; the lanes come back on sale.
- **It will not be topped up.** Leave it paused. Re-pin any grade that only
  existed on that panel to a lane on a healthy one in `/admin/catalog`.
- **In-flight orders keep syncing** while a panel is paused — pausing stops new
  placement, not the status poll. Do not cancel anything by hand; a paid order
  still gets finished or refunded by the normal path.
- The floor is a config change, not a code change: update `low_balance_micros`,
  redeploy, and the next probe uses it.
