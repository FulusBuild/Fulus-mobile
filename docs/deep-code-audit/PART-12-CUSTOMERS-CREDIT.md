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


## Finding P12-002 — Credit-method return double reversal

**Severity:** High  
**Status:** Fixed in source; CI/runtime verification pending

### Evidence

The deployed authoritative `fulus_api_create_return_atomic_v2` function contained two `customer_ledger_entries` inserts for `refund_method='credit'`, using the same operation ID `target_client_reference||':credit-reversal'`. The first branch inserted the reversal, then the later credit settlement branch attempted the same insert again.

The customer ledger table has a unique `(business_id, operation_id)` constraint. Therefore a credit-method return reaches the second insert and violates the uniqueness constraint; because the RPC is one transaction, the return is rolled back rather than successfully completing. This was confirmed against the live production function definition and the repository schema.

### Fix

Migration `20261003100000_fix_credit_return_double_reversal.sql` makes the first credit branch validation/calculation-only. The single authoritative ledger insertion remains in the common credit settlement branch.

A financial-fidelity SQL regression now asserts that the authoritative return RPC contains exactly one credit-reversal operation ID occurrence.

### Required verification

1. Migration-chain CI must pass.
2. Production function definition must contain exactly one credit-reversal ledger insertion.
3. A credit-method return must complete with one ledger reversal and one balance reduction.
4. Retry of the same operation ID must remain idempotent.
5. Split-payment credit-reversal behavior must remain unchanged.


## Finding P12-003 — Canonical repayment echo race

**Severity:** High  
**Status:** Fixed in source; CI/runtime verification pending

### Evidence

The repayment RPC commits the authoritative `customer_ledger_entries` row before returning. The sync handler only assigns that row's `serverId` after the RPC response returns. A concurrent canonical pull can therefore observe the committed server row while the local repayment ledger row still has no `serverId`.

The canonical wire row includes the durable `operation_id`, but the customer-ledger reconciler previously discarded it. For repayments, the local durable outbox row uses that same operation ID as its queue-row ID. Without matching those identities, the canonical pull created a second local repayment ledger row; the subsequent push completion then settled the original row, leaving duplicate visible history.

### Fix

Pass the canonical `operation_id` through the ledger reconciler and, for repayment events, resolve that operation through the local durable outbox. When it points to a matching unsynced repayment row, update that existing row with the canonical server ID instead of inserting another row.

### Regression coverage

Repository coverage now simulates the exact race window: a local pending repayment has an outbox operation, then canonical server state for the same operation arrives before the push handler assigns `serverId`. The invariant is one local ledger row after reconciliation.
