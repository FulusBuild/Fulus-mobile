# Part F — Sales and Checkout

**Status:** Source audit and isolated CI complete; Android checkout/offline-to-sync and production deployment verification remain pending<br>
**Audit date:** 2026-11-20  
**Repository:** FulusBuild/Fulus-mobile  
**Baseline:** `origin/main` at `8029e09ee87f387dab8544dd54789ccf937e0b4e`; branch `codex/part-f-sales-checkout`  
**Runtime:** Flutter 3.44.9 / Dart on Windows; `flutter devices --machine` found Windows, Chrome, and Edge only. No Android phone, Supabase CLI, Docker, or `psql` was available in this environment.  
**Pre-existing worktree items:** `android/app/src/main/java/` and `android/local.properties` were present before Part F and were preserved.

## Scope and trace

Reviewed the Sell route and checkout surfaces: product and Quick Sale entry, cart and customer selection, whole-cart/line discount state, payment methods and split tender, successful sale/receipt presentation, sales history, local persistence, cloud submission, canonical reconciliation, and financial consumers of sale/payment rows. Returns/refunds/voids remain Part G, except for shared sale state at the boundary.

The principal path is:

`SellScreen / QuickSaleSheet → CartCubit → DraftCartRepositoryImpl.completeSale → SaleRepositoryImpl.createSale → local Sales/SaleItems/SalePayments + stock/customer-credit projections + outbox transaction → SaleSyncHandler → fulus_api_create_sale_atomic_v2 → create_sale_atomic → Postgres sale/inventory/customer-credit/payment/cash-ledger → canonical sale reconciliation → receipt/history/finance views`

The cloud RPC is called through a location-authorization wrapper. The prior V2 implementation is retained as `fulus_api_create_sale_atomic_v2_unchecked`; the public wrapper applies authorization before delegating.

## Source findings

### Proven local behavior

- Cart and payment state are durable draft rows. Checkout reconstructs items and payment legs from those rows instead of relying on transient screen state.
- `CartCubit` rejects empty carts, nonpositive item quantities/prices, discounts above line/cart subtotal, unsupported payment methods, payment without a customer for credit, and non-cash payment over the remaining amount. Cash tender is capped to the amount due while the excess is retained as tender/change.
- `completeSale` rejects an unpaid remainder. It guards duplicate completion while the request is active. `DraftCartRepositoryImpl.completeSale` groups sale creation and draft clearing in one transaction; `SaleRepositoryImpl.createSale` writes the sale, items, payment legs, tracked-stock projection, customer-credit projection, and durable outbox row transactionally.
- Sale submission is idempotent by client reference/request hash. Cloud rejection reconciliation refreshes product/customer canonical state while preserving newer queued mutations.
- Credit legs are excluded from `Sale.amountPaid` and added to the customer credit ledger. Cash over-tender remains separate from applied cash. Local stock decrement skips products whose `tracksStock` is false.
- Receipt/history/finance consumers read persisted sale/payment state. Split payment receipts read the payment-leg rows; cash drawer and finance inflow use the sale's applied `amountPaid` rather than tendered cash.

### F-001 — V2 cloud sale RPC accepted a one-cent payment mismatch

**Severity:** Medium  
**Status:** Fixed in source; isolated Supabase CI passed; production deployment and Android runtime verification pending<br>
**Area:** Cloud payment, sale total, and cash-ledger reconciliation

The existing V2 RPC rounds currency to two decimals but rejects mismatches only when the difference is greater than `0.01`. The authoritative `create_sale_atomic` clamps `amount_paid` to the sale total. For example, a `$10.00` sale submitted with `$10.01` in cash payment legs passes the old tolerance; the sale stores `$10.00` as paid while the payment/cash-ledger path can record `$10.01`. This can create a one-cent mismatch between sale and ledger for a request reaching the authenticated cloud mutation boundary.

**Fix:** Migration `supabase/migrations/20261120120000_enforce_exact_sale_payment_totals.sql` keeps the existing location authorization wrapper, calls the private implementation, and then checks exact two-decimal equality among payment legs, authoritative sale total, collected amount, credit balance, and the requested `amount_paid`. A failed postcondition raises inside the transaction, rolling back the sale and its related writes. `supabase/tests/financial_fidelity.sql` checks that the RPC definition contains the strict guards and exercises exact cash and cash+credit sales, one-cent overpayment rejection, and requested `amount_paid` mismatch. The failure cases assert that no sale, cash-ledger, inventory, change-feed, or idempotency effects remain.

**Database/CI verification:** GitHub Actions Supabase Migration Chain run `44704256962` and Fulus Mobile CI run `44704256904` both completed successfully for PR #231 head `8e0380589cf285fd104c7628a23835d402b7c1f0`. The Supabase workflow applied the migrations to its disposable local database and passed `financial_fidelity.sql` plus the repository SQL suites. Flutter CI dependency resolution, code generation, static analysis, and tests passed. The workflow skipped device convergence and APK-build jobs. No production mutation or migration was run.

## Automated evidence

Focused Flutter tests passed after generating the missing sources absent from this checkout required by this checkout. Exact command:

```powershell
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\dart.bat' run build_runner build --delete-conflicting-outputs
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\flutter.bat' test test/features/sell/cart_cubit_test.dart test/features/sell/cart_state_test.dart test/repository/draft_cart_repository_test.dart test/repository/sale_repository_test.dart test/sync/sale_sync_handler_test.dart test/sync/offline_sale_local_flow_test.dart
```

Result: **72 tests passed, 0 failed, 0 skipped**. The first test attempt failed at compile time because generated `*.g.dart` part files were absent; build_runner then wrote 34 outputs and the focused rerun passed. GitHub CI additionally passed the SQL migration chain and financial-fidelity SQL regressions on an isolated disposable database.

## Device/backend evidence and remaining gaps

- No Android device was visible. Quick sale, scanning, checkout, receipt presentation, background/resume, and offline→reconnect behavior were not manually exercised on a phone.
- GitHub's disposable Supabase CI verified migration application and SQL behavior. No production Supabase project was queried or mutated.
- Production Supabase was not queried or mutated for Part F.
- No live multi-device sale convergence, session-expiry retry, contention, or process-death scenario was run.
- This report does not establish release readiness. The migration is prepared in source but not applied or deployed.

## Documentation disposition

- Retained `docs/deep-code-audit/PART-09-SALES-CHECKOUT.md`, `CROSS-CUTTING.md`, and the older ledger entries as historical evidence; their statements were revalidated selectively against this baseline.
- Added this current Part F report and a current campaign entry to `docs/QA_MASTER_PLAN.md` and `docs/deep-code-audit/FINDINGS.md`.
- Updated `docs/DOCUMENTATION_STATUS.md` to link this report and describe the pending database/device evidence.

## Handoff

Part F source review, focused mobile tests, and isolated SQL/CI verification are complete. The remaining direct evidence is checkout and offline-to-sync on an Android QA device/business, plus the normal reviewed production deployment path. Keep Part G return/refund behavior in its own audit.

