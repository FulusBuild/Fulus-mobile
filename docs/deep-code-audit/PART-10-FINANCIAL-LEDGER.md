# Part 10 — Financial & Ledger Integrity

**Status:** Source audit complete; one High drawer-reconciliation defect fixed with regression coverage. The coordinated integer-money migration remains an open High finding and must not be split into ad-hoc field conversions.
**Baseline SHA:** 24063ca8a4fe3235e1adb65e6b9b0258fddbdc5e
**Audit branch:** audit/deep-code-part-10-financial-ledger

## Scope

Audited monetary persistence, arithmetic, sales/payment totals, customer and supplier balances, income, expenses, tax remittances, cash drawer reconciliation, refunds/reversals, split payments, cloud/local numeric contracts, and financial sync/replay behavior.

## Financial data inventory

Historical Drift versions persisted monetary values as SQLite REAL in:
- Products.costPrice / sellingPrice
- Customers.outstandingBalance / creditLimit
- Sales.subtotal / wholeCartDiscount / discount / tax / total / amountPaid
- SaleItems.unitPrice / costPriceAtSale / lineDiscount
- SalePayments.amount
- Expenses.amount
- IncomeRecords.amount
- CustomerLedgerEntries.amount
- SupplierLedgerEntries.amount
- ReturnRequests.refundAmount
- DraftCarts.wholeCartDiscount / tax
- DraftCartItems.unitPrice / costPriceAtSale / lineDiscount
- DraftCartPayments.amount
- TaxRemittances.amountRemitted
- CashDrawerShifts.openingCash / closingCash / cashDifference
- BusinessSettings.vatRate is also REAL, but is a percentage rather than money.

Employee salary is separately stored as REAL in employee tables and should be included in the eventual monetary inventory if that feature becomes financially authoritative.

## Backend/production cross-check

Production Fulus Cloud currently uses NUMERIC(14,2) for the principal financial fields in sales, sale items, payments, customers, expenses, income, products, and returns. sale_payments.amount is numeric and the V2 sale function rounds payment legs to two decimal places.

A production check on the current project found:
- 438 sales, 442 sale items, 543 sale payments, 172 expenses, 210 income records, and 192 customers.
- No observed rows with values outside the two-decimal contract in those principal tables.
- 170 cash-drawer shifts; no observed opening/closing/difference value outside two decimals.
- No production sales with negative financial fields, formula mismatch, or amount_paid greater than total.

This is evidence about the current production dataset, not proof that the mobile REAL representation is safe.

## Arithmetic contract

The authoritative cloud sale transaction rounds the calculated subtotal/total and payment legs to two decimals. The mobile domain still uses Dart double throughout checkout, repositories, DTOs, reports, and drawer calculations.

The current UI also uses a floating-point tolerance (0.004) when comparing payment amounts with the remaining balance. This is a symptom of the representation mismatch, not a suitable long-term financial invariant.

The coordinated target should be:
- one integer minor-unit representation in the local financial domain;
- exact integer addition/subtraction/multiplication by quantity;
- explicit rounding only at defined boundaries;
- one canonical two-decimal wire contract to the existing cloud NUMERIC(14,2) schema;
- no use of display formatting as arithmetic normalization.

## Cash tender / change

Part 09 established the concrete contract gap:
- local checkout permits cash tender greater than the amount due;
- local SalePayment/Sale.amountPaid can therefore contain tendered cash;
- changeDue is derived from the excess;
- cloud V2 requires payment legs to equal the sale total and does not persist an overpayment;
- cash-drawer expected-cash calculation currently sums the stored cash payment amount.

The current implementation explicitly separates tendered cash, applied payment, change, and cash-ledger treatment. The remaining requirement is live Android/offline-to-sync proof.

This must be resolved as part of the integer-money migration, not by clamping amountPaid in one layer.

## Fixed defect: attention-needed cash expenses

CashDrawerShiftRepositoryImpl.computeExpectedCash previously included cash expenses only when their sync status was settled, pending, or syncing. A locally recorded cash expense whose cloud operation was parked as attentionNeeded was therefore omitted from expected cash even though the local financial mutation had already happened.

Impact: Daily Closing could report expected cash too high by the amount of a locally recorded cash expense requiring sync attention.

Fix:
- include attentionNeeded expense rows in cash-drawer expected-cash calculation;
- retain the existing non-deleted/location/payment-method/time filters.

Regression:
- test/repository/cash_drawer_shift_repository_test.dart now inserts an attention-needed cash expense and proves expected cash includes it.

## Ledger/reversal cross-check

Customer repayment is locally transactional: balance update, ledger row, and durable outbox enqueue commit together. The customer ledger sync handler has an authoritative cloud operation and reconciles rejected repayments against the canonical customer state.

Return/refund processing is cloud-authoritative and uses explicit credit-reversal and cash-refund amounts. The Part 09 cash/change contract remains the key unresolved interaction between sale payment records and drawer accounting.

Supplier ledger and tax-remittance ledgers are intentionally local-only today. They therefore require clear product semantics that distinguish local bookkeeping from cloud-authoritative financial state; they must not be silently treated as multi-device accounting truth.

## Findings

### P10-001

**Severity:** High
**Status:** Closed in source; runtime upgrade/convergence evidence pending
**Area:** Monetary representation

Historical local financial persistence used IEEE-754 Dart/SQLite floating-point values while the cloud financial schema uses NUMERIC(14,2). The current local domain and SQLite schema use integer minor units.

Affected paths include catalog prices, sales, payments, customer balances, expenses, income, supplier/customer ledgers, returns, tax remittance, cash drawer state, and draft checkout.

Impact:
- exact equality is representation-sensitive;
- repeated arithmetic can accumulate binary floating-point error;
- ad-hoc tolerances become part of financial correctness;
- local/cloud serialization can normalize the same logical amount differently.

Completed source work:
1. Integer minor-unit representation is defined.
2. Decimal-string conversion boundaries are explicit.
3. Migration v17 converts historical REAL columns.
4. Entities, repositories, DTOs, sync handlers, reports, receipts, drawer calculations, and tests use the canonical representation.
5. Exact arithmetic and wire fitness regressions exist.

### P10-002

**Severity:** High
**Status:** Fixed in source; runtime verification pending
**Area:** Cash tender/change and cash ledger

The current source gives tendered cash, applied payment, change, Sale.amountPaid, SalePayments.amount, and cash-drawer expected cash one canonical semantic contract.

The historical cloud mismatch is closed in source; live cash-change evidence remains.

Completed source alignment: tendered cash, applied payment, change, cash-ledger entries, checkout, receipt, drawer, cloud RPC, canonical reconciliation, and integer money are aligned.

### P10-003

**Severity:** High
**Status:** Closed in source; runtime verification pending
**Area:** Daily Closing cash projection

Observed behavior: cash expenses with attentionNeeded sync status were excluded from expected cash.

Fix: include attention-needed expenses because the local financial mutation has already occurred and remains part of the drawer's local truth.

Regression: added repository-level coverage.

## Cross-cutting handoff

- X-005: integer money is implemented; runtime evidence remains.
- X-007 / X-008: sale arithmetic and tender/change semantics are implemented; runtime evidence remains.
- P05-002/P05-003: persistence cardinality races remain separate migration work; P05-003 can affect drawer integrity and should be reconciled with this part.
- Part 11: inventory valuation and stock-event accounting must consume the same integer-money contract for product cost and sale cost.
- Part 12: customer-credit repayment/reversal must use the same integer unit and cash/change semantics.
- Part 13: cloud financial RPCs remain authoritative for server-side rounding and idempotency.

## Definition of done for the financial migration

- No financial domain value uses double.
- No financial SQLite column remains REAL where the value is monetary.
- Money arithmetic is exact integer arithmetic.
- Two-decimal cloud NUMERIC conversion is explicit and tested.
- Existing production/local values round-trip without value changes.
- Cash tender/change is represented without overloading applied payment.
- Drawer reconciliation includes all locally committed cash effects, including attention-needed work.
- Sale, return, repayment, expense, income, supplier payment, tax, and drawer tests cover offline/retry/restart paths.
- Live sync and multi-device convergence pass after the migration.

## Handoff

Next audit part remains Part 11 — Inventory & Stock Events, with the new drawer fix cross-checked against stock/sale event semantics. The financial migration itself should remain a dedicated implementation stream rather than being partially applied in Part 11.
