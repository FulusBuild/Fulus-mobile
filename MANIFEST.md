# Nice-to-Have Round — File Manifest

Everything in this tar is the CURRENT, final state of the file — not diffs/patches. 33 files total: 32 touched `.dart` files (relative to your original `Fulus-1.zip`) + this session's `PROGRESS.md`.

Included the full set, not just this round's new files, because 6 files you already have (from the two earlier tars) got further changes this round to actually wire up App Lock and Bulk Import — a partial delta would leave those half-connected on your end.

## Brand new this round (7)
- `lib/app/app_lock_gate.dart`
- `lib/core/security/app_lock_config.dart`
- `lib/features/auth/presentation/screens/app_lock_screen.dart`
- `lib/features/stock/presentation/screens/bulk_import_screen.dart`
- `lib/features/stock/presentation/screens/bulk_import_review_screen.dart`
- `lib/shared/screens/photo_capture_screen.dart`
- `lib/app/app.dart` (not touched before this round — now wraps the router in `AppLockGate`)

## Already delivered, further modified this round (6)
- `lib/app/router.dart` — bulk-import routes added
- `lib/app/providers.dart` — `appLockConfigProvider` added
- `lib/features/more/settings/presentation/screens/settings_main_screen.dart` — App Lock section added
- `lib/features/stock/presentation/screens/stock_screen.dart` — bulk-import icon added
- `lib/features/stock/presentation/screens/add_edit_product_screen.dart` — photo capture wired in
- `lib/features/stock/presentation/screens/product_detail_screen.dart` — photo display added

## Already delivered, unchanged this round (19)
Included for completeness/safety only — identical to what you already have from the prior two tars. Safe to skip if you're confident your tree already matches: `app_shell.dart`, `home_screen.dart`, `daily_closing_count_screen.dart`, `employee_detail_screen.dart`, `employees_list_screen.dart`, `notifications_screen.dart`, `reports_screen.dart`, `backup_screen.dart`, `printer_pairing_screen.dart`, `sync_detail_screen.dart`, `cart_cubit.dart`, `cart_screen.dart`, `refund_confirm_screen.dart`, `refund_search_screen.dart`, `sell_screen.dart`, `discount_sheet.dart`, `receipt_preview_sheet.dart`, `categories_screen.dart`, `barcode_scan_screen.dart`.

## Nice-to-have items completed this round (3 of 11 remaining)
1. **CSV bulk import** — paste-based (no file-picker package available in this project; documented in the code comments why)
2. **App Lock** — local PIN, hashed via the same Argon2 hasher ApprovalPin already uses, locks on backgrounding and cold start
3. **Product photo capture** — wired into Add/Edit Product and shown on Product Detail

Declined, with reasoning (not silently skipped):
- **Employee QR invite** — per your explicit instruction
- **Receipt photo on expenses** — `Expense` entity has no photo field; would need a real Drift schema migration + `build_runner` codegen this environment can't safely run without a compiler

Stopped mid-investigation on **Loyalty UI** (read-only so far — `Customer.loyaltyThreshold`/`purchaseCount` fields confirmed to exist, no code written). Remaining: Loyalty UI, Variants editor, Reports drill-down/export/custom range, Restore Detected/Progress, business-type tax defaults, password recovery, Stock Transfer.

**Not run against a Flutter compiler.** Brace/paren balance and full relative-import resolution (all `.dart` files under `lib/`) were swept clean after every file in this round — see `PROGRESS.md` — but that's not a substitute for `flutter analyze`.
