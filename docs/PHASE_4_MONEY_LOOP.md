# Phase 4 — Money Loop

The Money area is the shop owner's financial workspace. It must answer three questions quickly:

1. **What money do I have?** — all-time available balance.
2. **What happened during this period?** — money in, money out, net and transaction breakdown.
3. **What do I need to do next?** — record income/expense, manage customer or supplier balances, and close the cash drawer.

## Acceptance criteria

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
- Money history can distinguish sales, repayments, supplier payments, income and expenses.

### Cash drawer
- Opening float starts a drawer session.
- Expected cash is calculated as opening float + cash sales - cash expenses.
- Closing requires an actual counted cash amount.
- Difference is shown before the close is committed.
- Closing refreshes Home/Money immediately and produces a closing summary.
- Cash-drawer calculations are covered by unit tests so later UI/repository changes cannot silently alter the accounting rule.

### Offline-first behavior
- Every mutation is written locally first.
- UI never blocks on cloud availability to record a legitimate local money movement.
- Refresh/re-entry shows the same locally committed result immediately.
- Sync failures are recoverable without asking the user to re-enter the transaction.

## Current pass

This pass adds regression coverage around the drawer calculation contract and records the Money acceptance criteria as a durable implementation target. The next implementation increment should prioritize the irreversible-action UX around day closing and then complete end-to-end offline mutation/sync verification for income, expense, repayment and supplier payment.
