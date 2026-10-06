# Part 09 — Sales & Checkout

**Status:** Source audit complete; one High financial contract finding remains deferred to Part 10, one High sale/inventory defect fixed with regression coverage.
**Baseline SHA:** 838634db9fbc7794e47aafa7d4105d2cb235346f
**Audit branch:** audit/deep-code-part-09-sales-checkout

## Scope

Audited draft carts, sale creation, sale items, payments and split payments, discounts, credit sales, local inventory effects, durable outbox creation, Fulus Cloud sale creation, idempotency, rejection/reconciliation, receipts, returns/voids, and offline/process-restart behavior.

## Structural inventory

Reviewed:
- Sale, SaleDraft, SalePayment domain entities and sale DTOs.
- CartCubit checkout validation and payment flow.
- DraftCartRepositoryImpl draft mutation and completeSale.
- SaleRepositoryImpl local sale transaction, payment persistence, stock projection, customer-credit projection, and sync enqueue.
- SaleSyncHandler dependency resolution, cloud submission, rejection reconciliation, and stale-completion handling.
- SaleCanonicalRepositoryImpl canonical sale/payment projection.
- Fulus Cloud sale RPCs including create_sale_atomic and fulus_api_create_sale_atomic_v2.
- Sale/return repositories and sync handlers.
- Sale, checkout, sync, and offline restart regression tests.

## Pass A — Structural inventory

The intended checkout path is:

Sell UI → CartCubit → DraftCartRepository.completeSale → SaleRepository.createSale → local Sales/SaleItems/SalePayments + local stock/credit projection → SyncQueue → SaleSyncHandler → fulus_api_create_sale_atomic_v2 → create_sale_atomic → Postgres sale + inventory + customer credit + payment/cash ledger → change feed → canonical local reconciliation.

The local sale write and durable outbox enqueue are performed inside one Drift transaction. The cloud mutation is idempotent by business + client reference.

## Pass B — Function/class audit

### Cart validation

The normal UI path validates:
- at least one item;
- positive quantities;
- positive prices;
- line discount not above line value;
- whole-cart discount not above subtotal;
- supported payment methods;
- positive payment amounts;
- credit requires a customer;
- non-cash payments cannot exceed the remaining balance;
- completion requires the remaining balance to be settled.

Cash is intentionally allowed to exceed the remaining balance so a cashier can receive a larger note and calculate change.

### Local persistence

DraftCartRepositoryImpl.completeSale reconstructs items/payments from durable draft rows, combines line + whole-cart discounts, derives cash-collected amountPaid, derives the aggregate payment method, and calls SaleRepositoryImpl.createSale.

SaleRepositoryImpl.createSale writes the sale, items, split-payment rows, local stock projection, customer credit projection, and durable sync task in one transaction.

### Cloud sale

fulus_api_create_sale_atomic_v2:
- requires at least one payment leg;
- rejects non-positive legs;
- separates credit from collected payment;
- derives the aggregate payment method;
- uses an idempotency key/request hash;
- calls the authoritative create_sale_atomic;
- requires payment legs to equal the server-calculated sale total;
- requires collected payment to equal the server amount_paid;
- requires the credit leg to equal server balance_due;
- records payment legs and non-credit cash-ledger entries idempotently.

create_sale_atomic validates business/location/customer/product membership, positive quantities, stock availability for tracks_stock products, credit permission, and customer requirement for unpaid sales.

### Retry/rejection behavior

SaleSyncHandler resolves product/customer/location dependencies before submission. Permanent cloud rejection triggers authoritative product/customer reconciliation before the queue item is parked. Operation identity is carried through markSynced so stale completion cannot settle a newer queued mutation.

### Returns/voids

Return creation uses transactional local persistence and an idempotent cloud return operation. Cloud return processing locks the sale, validates remaining returnable quantity, restores tracked stock, and performs customer-credit/cash refund accounting. Void/return UI is backed by the same repository/sync paths rather than an independent local-only financial mutation.

## Pass C — Line/branch audit

### Proven invariant: local-first durability

A completed checkout does not require a network round trip. The sale and its outbox item commit locally before sync. Offline restart coverage verifies the sale remains durable and queued after reopening the database.

### Proven invariant: local sale transaction atomicity

Sale rows, sale items, split-payment rows, optimistic stock change, customer-credit projection, and outbox enqueue are grouped in the local transaction. completeSale also wraps sale creation and draft clearing so a failure does not leave a committed sale while the draft still appears payable.

### Proven invariant: cloud retry safety

The V2 cloud sale command binds the request hash to the business-scoped client reference. Reusing an operation ID with a different request is rejected, while a completed identical request returns its stored response.

### Proven invariant: server inventory authority

The cloud sale transaction decrements stock only for products with tracks_stock=true and rejects insufficient stock atomically.

### Fixed defect: local non-stock-tracked inventory mutation

Before this part, SaleRepositoryImpl._decrementLocalStock looked up a stock row and decremented it for every catalog product. Product stock rows exist independently of the tracksStock flag, while the cloud transaction deliberately skips inventory effects for non-stock-tracked products.

Impact: selling a non-stock-tracked product could reduce its local stock projection or throw a local insufficient-stock error even though the product is intentionally unlimited and the cloud sale would not decrement stock.

Fix: local sale checkout now reads the product tracksStock flag and skips the local stock mutation when it is false.

Regression: test/repository/sale_repository_test.dart proves a non-stock-tracked sale leaves the stock row unchanged.

### Known High finding: cash tender/change versus applied payment

The current UI permits cash tender larger than the remaining balance, but local checkout now stores only the applied amount in SalePayment while preserving the physical tendered amount separately, so change does not inflate amountPaid.

The cloud V2 sale command now receives the applied payment legs, persists cash tender/change separately, and validates payment_total against the authoritative sale total. The historical mismatch is therefore closed in source.

This is the concrete local/cloud contract mismatch already identified as P07-001/X-007. It requires a coordinated definition of:
1. tendered cash;
2. applied payment;
3. change;
4. cash-ledger amount;
5. split-payment semantics;
6. integer-money representation.

It is not safe to patch this by simply clamping one field locally, because that would risk losing tender/change information and could disagree with receipts, cash drawer accounting, and Part 10's integer-money migration.

## Pass D — Cross-system audit

### Sale creation

CartCubit → DraftCartRepository.completeSale → SaleRepositoryImpl.createSale → Drift sale/payment/stock/credit/outbox transaction → SaleSyncHandler → fulus_api_create_sale_atomic_v2 → create_sale_atomic.

The local and cloud paths agree on positive quantities, customer/location/business ownership, idempotency, and tracked-stock behavior after the Part 09 fix.

The remaining disagreement is payment/tender semantics for cash overpayment.

### Offline/process restart

offline_sale_local_flow_test.dart verifies a locally-created sale survives database close/reopen, remains pending, and does not attempt legacy API delivery when Fulus Cloud dependencies are unavailable.

### Returns

The return path was cross-checked for transaction boundaries, quantity eligibility, stock restoration, customer-credit reversal, cash refund, and cloud idempotency. No new Part 09 standalone defect was proven.

## Findings

### P09-001

**Severity:** High
**Status:** Deferred to Part 10
**Area:** Sale payment/tender contract

Observed behavior: Cash overpayment is allowed locally to represent change. Local payment rows and Sale.amountPaid retain the tendered cash, while the cloud V2 command requires payment legs to equal the sale total and server amount_paid is capped at the total.

Expected invariant: A valid cash sale with change must remain syncable without losing tender/change information, and local/cloud cash-ledger semantics must agree.

Impact: A legitimate cash checkout can succeed locally while becoming a permanently rejected sync item.

Evidence: CartCubit.addPayment, Sale.changeDue, DraftCartRepositoryImpl.completeSale, fulus_api_create_sale_atomic_v2, and create_sale_atomic were traced end-to-end.

Fix ownership: Part 10, together with X-005/X-007, before changing persisted monetary semantics.

### P09-002

**Severity:** High
**Status:** Closed in Part 09; runtime verification pending
**Area:** Local sale inventory projection

Observed behavior: Local sale checkout decremented every product's stock row without checking tracksStock, while the cloud sale transaction only decrements tracked products.

Fix: SaleRepositoryImpl._decrementLocalStock now skips non-stock-tracked products.

Regression: Added a repository test proving the stock row is unchanged for a non-stock-tracked sale.

Cross-check: Product creation establishes a local stock-level row, so the previous omission was reachable for non-stock-tracked products.

## Cross-cutting handoff

- X-005: integer-safe money remains owned by Part 10.
- X-007: local/cloud sale arithmetic and payment semantics remain open; Part 09 supplies the concrete cash-change reproduction.
- Part 11: stock event semantics should cross-check the tracksStock contract and the new local sale guard.
- Part 12: customer-credit allocation/reversal should cross-check split credit payment semantics.
- Part 13: cloud sale validation/idempotency contract is authoritative for retry safety.

## Tests reviewed

- test/repository/sale_repository_test.dart
- test/repository/draft_cart_repository_test.dart
- test/features/sell/cart_cubit_test.dart
- test/sync/sale_sync_handler_test.dart
- test/sync/offline_sale_local_flow_test.dart
- return repository/sync tests
- relevant canonical sale reconciliation tests

## Remaining uncertainty

- Exact Android/device evidence for cash-tender/change during an offline-to-online transition remains pending.
- Part 10 must define the canonical integer unit and persisted representation before P09-001 can be closed.
- Part 11 should independently verify sale/return stock-event semantics after this local guard.

## Handoff

Next: Part 10 — Financial & Ledger Integrity. P09-001/P07-001/X-007 is the primary dependency entering that part.
