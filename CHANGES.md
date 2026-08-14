# Fulus Gap-Closure — Change Manifest

Critical tier: 6/6 closed. Important tier: 9/10 closed, 1 deliberately not implemented (reasoning below — not an oversight). Nice-to-have tier: not started, by design — see final message in chat.

**Not run against a Flutter compiler at any point** — no toolchain in this environment. Every signature used was checked against the actual source file before being called (not written from memory), and every route name and brace/paren count was swept at the end (see below), but `flutter analyze` is still the first thing to run before trusting this.

## New files (10)

| File | Closes |
|---|---|
| `lib/features/sell/presentation/screens/refund_search_screen.dart` | Refund Search — was entirely missing |
| `lib/features/sell/presentation/screens/refund_confirm_screen.dart` | Refund Confirm — was entirely missing |
| `lib/features/sell/presentation/widgets/discount_sheet.dart` | Discount UI — engine existed, no caller |
| `lib/shared/screens/barcode_scan_screen.dart` | Barcode scanning UI — service existed, no caller |
| `lib/features/more/employees/presentation/screens/employee_detail_screen.dart` | Employee detail, access revocation, leave request review, login credential handoff |
| `lib/features/more/settings/presentation/screens/sync_detail_screen.dart` | Sync Detail screen — engine existed, no UI |
| `lib/features/more/settings/presentation/screens/printer_pairing_screen.dart` | Printer pairing — device services existed, no UI |
| `lib/features/more/settings/presentation/screens/settings_main_screen.dart` | Settings Main — business info, hub to Printers/Sync/Backup/Locations, PIN change |
| `lib/features/stock/presentation/screens/categories_screen.dart` | Category creation — nothing could create one before |
| `lib/features/more/presentation/screens/notifications_screen.dart` | Notification inbox — backend existed, no UI |

## Modified files (15)

| File | What changed |
|---|---|
| `lib/app/router.dart` | Routes for every new screen above; `_MoreScreen` rebuilt (Settings entry replaces "Not yet built" text, Notifications row with unread badge) |
| `lib/app/app_shell.dart` | Persistent sync indicator (tap → Sync Detail) and offline banner, both visible on every screen |
| `lib/app/providers.dart` | `dashboardRefreshSignalProvider` (Home ↔ Daily Closing fix) |
| `lib/features/home/presentation/screens/home_screen.dart` | Listens to the refresh signal (was stale after Open/Close Shop); hardcoded ₦ → real currency symbol |
| `lib/features/money/presentation/screens/daily_closing_count_screen.dart` | Bumps the refresh signal on close; hardcoded ₦ fixed |
| `lib/features/more/reports/presentation/screens/reports_screen.dart` | Hardcoded ₦ (~15 places) → real symbol; added error state + retry on all 5 tabs; added empty states; dark mode fix; surfaced cost-of-goods/gross-profit |
| `lib/features/more/employees/presentation/screens/employees_list_screen.dart` | Dark mode fix; rows now navigate to the new detail screen |
| `lib/features/more/settings/presentation/screens/backup_screen.dart` | Dark mode fix |
| `lib/features/sell/presentation/cubit/cart_cubit.dart` | Added `updateItemDiscount`/`setWholeCartDiscount` wrappers (repository methods existed, cubit never called them) |
| `lib/features/sell/presentation/screens/cart_screen.dart` | Discount row + per-line tap-to-discount, wired to the sheet |
| `lib/features/sell/presentation/screens/sell_screen.dart` | Refund and barcode-scan icons added to the app bar |
| `lib/features/sell/presentation/widgets/receipt_preview_sheet.dart` | Print button now actually prints (was a "coming soon" stub) |
| `lib/features/stock/presentation/screens/add_edit_product_screen.dart` | Scan-to-fill on the barcode field |
| `lib/features/stock/presentation/screens/product_detail_screen.dart` | Hardcoded ₦ (found during this pass, not in the original audit) → real symbol |
| `lib/features/stock/presentation/screens/stock_screen.dart` | Categories icon added to the app bar |

## Deliberately not implemented: delete/archive for Products/Customers/Suppliers

Investigated, not built. `updateProduct(isActive: false)` exists and would work, but `watchProducts` filters inactive rows out everywhere with no "Archived" view to see or restore them — a one-way trip into invisibility for what might be an owner's only unit of something. Customer/Supplier are worse: no update or delete method exists on either repository at all, and records like these can carry real owed money. A one-way hide with no way back is a worse outcome than the current "can't delete at all" — building it would trade an honest, known gap for a data-loss-shaped trap. The real fix is an "Archived" view with restore, which needs new repository methods this pass didn't add.

## Final consistency sweep (done, not just claimed)
- Brace/paren balance checked on all 24 touched files — all balanced.
- All 34 named routes in `router.dart` checked for duplicates — none.
- Every `pushNamed`/`goNamed` call anywhere in the app cross-checked against the actual route table — every one resolves.
