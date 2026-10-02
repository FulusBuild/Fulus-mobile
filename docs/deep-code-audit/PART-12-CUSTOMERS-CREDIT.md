# Fulus Deep Code Audit — Part 12: Customers & Credit

**Status:** Active audit complete for the local customer/credit boundary; P12-001 fixed and verified by CI. P12-002 is deferred to the coordinated financial/API audit because it crosses the sale-payment and customer-ledger contracts.

## Scope
Customers, customer identity, outstanding balances, credit sales, customer payments/repayments, credit history, archive/restore, canonical customer synchronization, customer-ledger synchronization, return credit reversals, and authorization/scope.

## Production evidence
Live production checks on 2026-10-02:
- 197 customers.
- 449 customer-ledger entries.
- 0 ledger entries with missing operation IDs.
- 0 non-positive ledger amounts.
- 0 negative customer balances.
- RLS enabled on both customers and customer_ledger_entries.
- Authenticated clients have SELECT only on those two tables; mutation privileges are not granted directly.
- 0 duplicate cloud credit-sale groups by business/customer/sale/amount.

The balance-vs-ledger reconstruction check reported 160 mismatches. Investigation showed this is not evidence that the stored customer balance is necessarily wrong: the server also has a sale-payment mutation that reduces customers.outstanding_balance without creating a corresponding customer_ledger_entries repayment row. That is a history/audit completeness gap, not a reason to overwrite balances from an incomplete ledger.

## P12-001 — Canonical credit-sale echo duplication

**Severity:** High
**Status:** Fixed; CI green

Offline credit sales immediately create a local creditSale ledger echo so the customer profile is correct before cloud sync. Canonical ledger reconciliation already deduplicated locally-created refund adjustments, but it did not perform the same identity match for creditSale. A later authoritative cloud credit_sale event could therefore insert a second local history row.

Fix: reconcile unsynced local creditSale rows by customer, sale, amount and entry type before inserting the canonical row.

Regression: create the local echo, reconcile the authoritative event, and assert exactly one row remains with the server ledger ID.

CI run 3513 / 37057551978 completed successfully, including static analysis, Flutter tests, live sync contract, and multi-device convergence.

## P12-002 — Customer balance changes are not fully represented in customer ledger

**Severity:** Medium / cross-cutting
**Status:** Open; owned jointly by Parts 10 and 13

The authoritative record_sale_payment mutation can reduce a customer's outstanding balance as part of a sale-payment transaction, but that mutation does not currently append a corresponding customer_ledger_entries repayment event.

Consequences: the customer balance remains authoritative and synchronized through the customer change feed, purchase history can show the sale/payment, but the dedicated credit-history list cannot reconstruct every balance decrease from customer_ledger_entries alone.

This should be fixed only as part of the coordinated financial/payment contract so sale payments, customer repayments, cash/payment ledgers, idempotency, and canonical sync agree on one event model.

## Carry-forward
- Part 10: integer money and complete financial event/ledger semantics.
- Part 13: cloud API mutation contracts and privileged wrapper verification.
- Part 14: canonical pull ordering and customer-ledger dependency handling.
- Part 16: concurrent customer repayments and cross-device convergence.