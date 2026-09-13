# Phase 4 — Money Loop

The Money area is the shop owner's financial workspace. It must answer three questions quickly:

1. **What money do I have?** — all-time available balance.
2. **What happened during this period?** — money in, money out, net and transaction breakdown.
3. **What do I need to do next?** — record income/expense, manage customer or supplier balances, and close the cash drawer.

## Completed in Phase 4

### Cash flow
- Available balance is independent of the selected reporting period.
- Period changes update summary and recent transactions without leaving Money.
- Breakdown rows open the matching transaction list/filter.
- Transaction rows open a detail view and preserve the selected context when returning.

### Manual money movements
- Income requires a positive amount and a source.
- Expense requires a positive amount, category and payment method.
- Cash expenses affect expected drawer cash; non-cash expenses do not.
- Expense receipt photos are optional and can be attached locally.
- Save actions are disabled while submitting and failures keep the form recoverable.

### Customer and supplier money
- Customer profiles expose outstanding balance and repayment history.
- Supplier profiles expose outstanding balance and payment history.
- Money history distinguishes sales, repayments, supplier payments, income and expenses.
- Repayments and supplier payments update balances transactionally and surface overpayment instead of silently dropping it.

### Cash drawer
- Opening float starts a drawer session.
- Expected cash is calculated as opening float + cash sales - cash expenses.
- Closing requires an actual counted cash amount.
- Difference is shown live before the close is committed.
- Closing now requires an explicit confirmation that repeats expected, counted and difference figures.
- Difference and closing data are persisted locally before network reconciliation.
- Opening/closing are transactional and protected against concurrent duplicate operations.
- A closed shift cannot be closed again.
- Closing records `closingSummaryLocked` for downstream immutable-summary behavior.
- Opening and closing sync tasks use the financial-priority queue.
- Closing immediately refreshes Home/Money and produces a summary with payment-method totals and export.
- Cash-drawer calculations have regression tests covering normal, invalid and concurrent lifecycle paths.

### Offline-first behavior
- Income and expense repositories commit locally first and enqueue sync work.
- Sale/payment writes remain local-first and feed the Money totals immediately.
- Drawer open/close commits locally and queues reconciliation without waiting for the cloud.
- Customer repayment and supplier payment ledger rows are local-first. Their current backend model does not yet expose dedicated mutation endpoints, so these ledger entries are intentionally not placed into a queue that has no handler; this is a backend-sync boundary, not a UI retry loop.

## Exit criteria

Phase 4 is complete for the current client/backend contract. The remaining ledger-sync item is explicitly isolated as a backend capability gap rather than hidden behind a false “synced” state or an endless local retry queue. It belongs in the next cloud-ledger/API pass before production multi-device reconciliation of standalone repayments and supplier payments.
