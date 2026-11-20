# Part G — Returns, Refunds, and Voids

**Status:** Audit in progress; source and cloud fixes are prepared in this branch; Flutter regression suite passes; disposable Supabase CI and device/runtime evidence are pending<br>
**Audit date:** 2026-11-20<br>
**Repository:** FulusBuild/Fulus-mobile<br>
**Baseline:** `707b85e594d95c49bc56833e99e4833c71656ffc` (`main`, merged Part F)<br>
**Working branch:** `codex/part-g-returns-refunds-voids`<br>
**Runtime:** Flutter 3.44.9 / Dart and Supabase CLI 2.117.0 on Windows. Docker is unavailable, so SQL behavior is delegated to the repository's disposable GitHub Supabase workflow. No Android device was connected. Generated Dart sources were created locally for focused tests and removed afterward. `pubspec.lock` was restored after dependency resolution. Untracked Android paths discovered during setup are preserved and untouched.

## Scope and trace

Part G covers refund search, item eligibility, partial/full return, approval, void, refund method, stock and customer-credit reversals, local outbox, cloud idempotency, canonical reconciliation, and their report/finance projections.

The principal path is:

`RefundSearchScreen / RefundConfirmScreen / VoidSaleScreen → ReturnRepositoryImpl → local ReturnRequests/ReturnItems + stock/customer-credit projection + outbox transaction → ReturnSyncHandler → fulus-api return.create → location-authorized V2 RPC → return/item, stock movement, cash ledger, customer ledger and change-feed writes → canonical return/product/customer reconciliation → sales/report/finance views`

The public return RPC is location-authorized and delegates to a private implementation. The server is the authority for return amount allocation and ledger effects. Production Supabase was not queried or mutated for this Part G work.

## Findings and source changes

### G-001 — Local refund calculation disagreed with the server's net sale allocation

**Severity:** Medium<br>
**Status:** Fixed in source; automated SQL/cloud and Android verification pending

The server prorates each returned line by `sale.total / sale.subtotal`, which accounts for sale-level discount and tax. The app previously multiplied raw unit price by return quantity. For a discounted sale, the locally completed return could therefore submit an amount that the cloud RPC rejects after the app had already restored local stock and adjusted customer credit.

`Sale.refundAmountFor` now uses integer minor-unit arithmetic and rounds half up to match the cloud formula. Both the confirmation estimate and local return row use the same calculation. Return requests that repeat the same product now aggregate quantities before checking eligibility, preventing duplicate entries from bypassing the local quantity limit.

### G-002 — Void could submit a refund method the cloud API rejects

**Severity:** Medium<br>
**Status:** Fixed in source; focused repository regression passes

The void path previously forwarded `Sale.paymentMethod` unchanged. Split and legacy methods such as `split` or `transfer` are not accepted by the cloud return RPC, which only accepts `cash`, `card`, `mobile_money`, or `credit`. The void now preserves supported methods and falls back to cash for unsupported methods. A split-payment void regression verifies the behavior.

### G-003 — Duplicate product lines cannot be identified by the mobile return command

**Severity:** Medium<br>
**Status:** Fixed in this branch; disposable Supabase CI pending

The local UI groups eligible quantity by product and `ReturnSyncHandler` sends only `product_id` and `quantity`. The new RPC implementation aggregates product-only requests, locks matching sale lines in stable ID order, allocates available quantity across those lines, and splits the weighted product-level refund amount across the resulting `return_items`. This preserves the existing mobile product-level contract and produces the same rounded refund total as `Sale.refundAmountFor`. Explicit `sale_item_id` requests remain supported. SQL regression coverage checks stable line allocation and amount parity; isolated CI execution is pending.

### G-004 — Permanent cloud rejection leaves the local return marked completed

**Severity:** Medium<br>
**Status:** Fixed in source; sync-level regression and runtime verification pending

`ReturnSyncHandler` now first marks the local row `reconciliation_pending`, which is a local-only state that remains visible and continues to reserve the claimed quantity. It changes the row to `rejected`, clears `inventoryRestored`, and releases that quantity only after all required canonical product/customer projections are successfully applied. Failed fetches or newer queued mutations leave the row `reconciliation_pending` while preserving the original permanent error for the outbox. A repository regression verifies the state transition and eligibility behavior. A handler-level rejection test and device/offline lifecycle verification remain pending.

### G-005 — Local report reversal math still uses pre-discount product prices

**Severity:** Medium<br>
**Status:** Fixed in source; report projection regression passes

`SaleReversalAdjustments` now takes aggregate revenue reversals from `ReturnRequests.refundAmount`, allocates product-level refund value through the same net-total helper as the return repository, and subtracts customer-credit reversals before calculating cash returned. This aligns local net revenue, cash-flow, and product projections with the completed return and its customer-ledger effect.

### G-006 — Account-credit refunds could be accepted locally when the cloud must reject them

**Severity:** Medium<br>
**Status:** Fixed in source; focused repository regressions pass

The cloud permits a `credit` refund only when the original sale has a customer, an eligible credit leg, and enough outstanding customer balance for the full refund. The UI offers the method for every sale, while the repository previously accepted it without checking those prerequisites. Local return creation now mirrors those guards and provides a user-safe business-rule message before any return, stock, credit, or outbox effects are written. Completion also caps the local credit reversal to the current customer balance, matching the cloud's credit-reversal limit.

### G-007 — Cloud cash/card refunds can deduct from cash without reversing sale credit

**Severity:** High<br>
**Status:** Fixed in this branch; disposable Supabase CI pending

The final V2 RPC now posts the eligible credit reversal to both the customer balance and customer ledger for every refund method, then posts only a positive remaining amount to the cash ledger. A cash refund fully covered by eligible credit reversal is accepted without a zero-value cash-ledger entry. `financial_fidelity.sql` now exercises a duplicate-product split-credit sale, a product-only partial return, exact refund/credit/cash allocation, and idempotent replay. The disposable SQL workflow still needs to run on this branch.

## Automated evidence

Focused command:

```powershell
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\dart.bat' run build_runner build
& 'C:\Users\Sanni\Documents\Codex\tools\flutter-3.44.9\bin\flutter.bat' test test/repository/return_repository_test.dart test/sync/fulus_sale_return_canonical_reconciler_test.dart
```

Result after the current source changes: **38 tests passed, 0 failed, 0 skipped**. Regressions cover net-total and weighted duplicate-line allocation, report/cash-flow/product projections, duplicate requested quantities, account-credit eligibility and balance caps, rejection status/eligibility transitions, supported/unsupported original refund methods, and split-payment void fallback. Targeted Dart analysis of the changed repositories, sync handler, entities, refund screen, and repository tests reported **no issues**. Missing generated `*.g.dart` files were regenerated with build_runner for the run and will be removed before commit.

No Part G SQL behavior test, live sync, physical-device flow, app lifecycle case, concurrent-return case, or multi-device convergence case has been run yet. Supabase CLI 2.117.0 is available locally, but Docker is not installed; run the repository's disposable GitHub Supabase workflow for migration and SQL verification. The PR #231 CI result in the Part F report is prior-part evidence, not Part G verification.

## Next work

1. Run the disposable Supabase Migration Chain and `financial_fidelity.sql` on a Part G PR; correct any migration/test failures.
2. Add handler-level regression coverage for successful, partial, and deferred rejection compensation.
3. Review refund-method eligibility, approval semantics, concurrent returns, process restart, and multi-device convergence.
4. Request a physical-device walkthrough when an Android device is available.
5. Recheck the full diff and preserved user files before merging the Part G PR.

\n