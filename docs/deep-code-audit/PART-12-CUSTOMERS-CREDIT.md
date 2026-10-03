# Part 12 — Customers & Credit

## Scope

Deep audit of customer records, credit balances, customer ledger entries, repayments, refunds/credit reversals, offline mutations, canonical reconciliation, idempotency, and local/cloud contract alignment.

## Finding P12-001 — Customer repayment overpayment contract mismatch

**Severity:** High  
**Status:** Fixed in source; CI/runtime verification pending  

### Evidence

The local customer-credit engine explicitly defines the business rule: a repayment larger than the outstanding balance is recorded, the balance is capped at zero, and the excess is returned for user-visible feedback. The repository and repayment UI have regression coverage for this behavior.

The authoritative Supabase record_customer_repayment function instead rejected target_amount > old_balance. That meant a valid offline repayment could be committed locally, then rejected during synchronization, temporarily producing a different business outcome across devices and requiring rejection reconciliation.

### Fix

The new migration 20261003090000_allow_customer_repayment_overpayment.sql aligns the cloud mutation with the existing local contract:

- positive repayments remain required;
- the customer balance becomes greatest(old_balance - target_amount, 0);
- the full tendered repayment remains the ledger amount;
- the excess is calculated and returned as excess_amount;
- the canonical ledger change carries the authoritative zero-capped balance;
- existing operation-id idempotency is preserved;
- authentication, permission, customer-business, and active-device checks remain unchanged.

No client-side weakening of validation was needed because the existing local behavior was already the intended product rule.

### Required verification

1. Migration-chain CI must pass.
2. Production function definition must match the migration after deployment.
3. Offline repayment larger than balance must converge to a settled ledger entry with zero customer balance and no duplicate canonical ledger row.
4. Retry of the same operation ID must remain idempotent.
5. Part 14–17 sync/process-death audits must retain the rejection/convergence tests around customer mutations.

## Additional Part 12 review

The customer ledger sync handler already contains a newer-mutation fence when reconciling a rejected repayment and restores the customer projection from the canonical customer endpoint. This is retained; the primary contract defect was upstream in the authoritative mutation itself.

Customer ledger canonical reconciliation also reuses local credit-sale/refund-adjustment echoes by matching their stable business attributes before inserting a new row, preventing duplicate visible history lines when canonical events arrive.
