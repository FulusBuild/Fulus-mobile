# Fulus Gap-Closure — Status

Critical: 6/6 closed. Important: 9/10 closed (1 deliberately skipped, reasoned below). Nice-to-have: not started — next phase.

Legend: ✅ Done · 🟡 Deliberately partial · ⬜ Not started

## Critical
- ✅ Home ↔ Daily Closing sync
- ✅ Sync indicator + Sync Detail screen
- ✅ Hardcoded ₦ in Home + Reports
- ✅ Refund Search/Confirm (screens + routes + entry point on Sell)
- ✅ Reports error state + retry
- ✅ Employee deactivation (+ detail screen + leave review + login credential handoff, bundled)

## Important
- ✅ Discount sheet (whole-cart + per-item)
- ✅ Barcode scanning (Sell + Add Product)
- ✅ Printer pairing screen (+ wired the real Print button, was a "coming soon" stub)
- ✅ Settings Main (Business info editable, Printers/Sync/Backup/Locations hub, approval PIN change)
- ✅ Employee credential handoff + detail screen (done earlier, bundled with Critical employee work)
- ✅ Categories management screen (list + create; repository has no update/delete method to wire — noted, not a UI gap)
- ✅ Notifications surfaced (badge/list — bell entry in More with unread count, full notifications screen)
- ✅ Dark mode fixes (Employees/Backup/Reports — all three)
- 🟡 Delete/archive Products/Customers/Suppliers — deliberately NOT implemented; see reasoning below
- ✅ Global offline banner

## Nice-to-have
- ⬜ Onboarding polish (Get Started, first-product/quick-sale prompts, celebration, permission primers)
- ⬜ Employee cross-device invite/QR join
- ⬜ Loyalty UI at checkout
- ⬜ Product photo capture
- ⬜ Variants editor
- ⬜ CSV bulk import UI
- ⬜ Receipt photo attachment on expenses
- ⬜ Reports drill-down / export / custom range
- ⬜ App Lock + Restore Detected/Progress
- ⬜ Real business-type tax defaults
- ⬜ Password recovery flow
- ⬜ Stock Transfer between locations

## Notes
- **Delete/archive for Products/Customers/Suppliers**: investigated, deliberately not built. `updateProduct(isActive: false)` exists and would work for Product, but `watchProducts` filters out inactive rows with no way to see or restore them anywhere in the UI — archiving would be a one-way trip into invisibility for what might be an owner's only unit of that item. Customer/Supplier are worse: no update/delete method exists on either repository at all (confirmed by reading both interfaces in full), and even a new soft-delete method would hit the same no-restore-path problem, on records that can carry real owed money. A one-way hide with no way back is worse than the current "can't delete at all" for records like these — building it would trade a known, honest gap for a data-loss-shaped trap. The right fix is an "Archived" view with restore, which needs new repository methods this pass didn't add. Flagging clearly rather than shipping the unsafe half.
