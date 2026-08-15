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

---

# Pass 2 — Onboarding polish (Nice-to-have)

Closes PROGRESS.md's "Onboarding polish (Get Started, first-product/quick-sale prompts, celebration, permission primers)." Receipt visual formatting (raw total, no line items) is a known, separate gap — deliberately not touched this pass, including inside the new celebration screen, which embeds that same widget unmodified.

**Not run against a Flutter compiler** — same caveat as Pass 1. `pubspec.yaml` now declares `assets/branding/` for the first time; double-check `flutter pub get` picks it up.

## New files (5)

| File | Closes |
|---|---|
| `lib/core/onboarding/onboarding_state.dart` | Persisted `hasSeenFirstRunPrompt`/`hasCelebratedFirstSale` flags (SharedPreferences, same shape as `SyncConfig`) — both default `true`, armed `false` only at real business creation, so no pre-existing business ever sees onboarding retroactively |
| `lib/features/auth/presentation/screens/get_started_screen.dart` | Volume 3's "Install & Launch" — single unambiguous "Get started" action in front of `OwnerSetupScreen`, using the real `assets/branding/fulus_mark_transparent.png` |
| `lib/features/onboarding/presentation/screens/first_run_setup_screen.dart` | Post-business-creation, one-time, skippable: add first product / Quick Sale now / pair a printer |
| `test/core/onboarding/onboarding_state_test.dart` | Coverage for the new persisted-flag class |

## Modified files (12)

| File | What changed |
|---|---|
| `lib/app/router.dart` | `_ShellGate` inserts `FirstRunSetupScreen` between business creation and the shell, gated on `firstRunPromptSeenProvider` |
| `lib/app/providers.dart` | `onboardingStateProvider` + reactive `firstRunPromptSeenProvider` mirror (same shape as `sessionProvider`) |
| `lib/app/bootstrap.dart` | Loads `OnboardingState`, wires the override |
| `lib/features/auth/presentation/screens/auth_gate_screen.dart` | Fresh installs now show `GetStartedScreen` instead of `OwnerSetupScreen` directly; also fixed a stale doc comment claiming the interrupted-setup resume case was unsolved — `_ShellGate` already handles it |
| `lib/features/auth/presentation/screens/owner_setup_screen.dart` | Arms both onboarding flags (`OnboardingState.armFirstRun`) the moment `createBusiness` succeeds |
| `lib/features/sell/presentation/screens/sale_success_screen.dart` | First-sale celebration variant — converted to `ConsumerStatefulWidget`; embeds `ReceiptPreviewSheet` inline instead of behind "View Receipt"; primes + requests the notifications permission on "Continue" |
| `lib/device_services/device_permissions.dart` | `hasCameraPermission`/`hasBluetoothPermission` — pure status checks, no OS dialog, so a primer only shows when a dialog is actually about to follow |
| `lib/device_services/scanning/barcode_scanner_service.dart` | `hasPermission` passthrough |
| `lib/device_services/printing/printer_discovery_service.dart` | `hasBluetoothPermission` passthrough |
| `lib/core/notifications/notification_service.dart` | Public `ensurePermission()` — same two private steps the existing methods already run lazily, no notification shown, no third "situation" added |
| `lib/shared/widgets/fulus_dialogs.dart` | `showFulusPermissionPrimer` — Decision 8's "one plain-language line before the system dialog" |
| `lib/shared/screens/barcode_scan_screen.dart` | Shows the primer before requesting camera permission (covers both Sell's scan icon and Add Product's scan-to-fill, same shared screen) |
| `lib/features/more/settings/presentation/screens/printer_pairing_screen.dart` | Shows the primer before the Bluetooth branch of "Find a printer" |
| `pubspec.yaml` | Declares `assets/branding/` — first real use of a bundled asset in the app |

## Deliberately not built this pass

- **Employee "I have a code" entry on Get Started** — Volume 3 names it, but it depends on the employee cross-device invite/QR flow, which PROGRESS.md already tracks as its own separate, not-yet-started nice-to-have. `AuthGateScreen`'s own doc comment explains why that flow isn't buildable yet (`AuthRepository` has no method for it). Offering a button with nothing behind it would violate Volume 12's "never a dead end" rule.
- **First Customer step** — Volume 3 lists it alongside First Product/Printer. Skipped as its own onboarding screen: it only matters "if a sale is made on credit," and the existing on-demand Add Customer flow from Sell/Stock already covers that moment without a dedicated detour here.
- **"Link to re-enable later from Settings" after a permission denial** (Volume 3's Failure Scenarios) — the manual-entry/share-only fallbacks already exist with a one-line explanation; the Settings deep link itself (`permission_handler`'s `openAppSettings()`) is not wired up. Small, contained, honestly flagged rather than rushed in.
- **Receipt visual formatting** — explicitly out of scope for this pass per instructions; the celebration screen embeds the existing widget as-is.

## Consistency sweep (Pass 2)
- Brace/paren/bracket balance checked on all 17 touched files — all balanced.
- Cross-checked every new route name (`stockAddProduct`, `sell`, `moreSettingsPrinters`) against the actual route table — all three exist, no path params required.
- Checked for duplicate route names after this pass's additions — none (no new routes were added; `FirstRunSetupScreen` is inserted inline by `_ShellGate`, not routed).
- Caught and fixed my own doc-comment misplacement in `fulus_dialogs.dart` mid-pass (an edit briefly left `showFulusConfirmDialog`'s doc comment documenting the wrong function) before finalizing.
