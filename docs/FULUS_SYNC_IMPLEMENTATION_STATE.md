# Fulus Sync Implementation State

Last audited: 2026-09-22
Repository: FulusBuild/Fulus-mobile
Main HEAD: 41ded8faf08d8d4b407eb95afc1310b8ad86ff05
Cloud Sync audit PR: #59
Supabase project: bejcuvoxemwomcatgyxz

## Current truth

An independent second-pass audit was performed against the actual client source, tests, Supabase production schema/functions/migrations, CI, and the live sync contract.

The audit found and fixed three material issues that the previous completion claim had missed:

1. Customer repayment could commit local balance/ledger state before its durable outbox entry. The enqueue is now inside the same Drift transaction, with a regression test proving local state rolls back when enqueue fails.
2. Initial cloud seeding skipped pre-cloud archived products/categories/suppliers/customers. Those rows are now seeded so their create-then-archive lifecycle can complete remotely.
3. A pre-sync archived product reused its stale pre-create cursor for the follow-up delete. The delete now omits that stale cursor, with a regression test covering the create -> delete lifecycle.

A stale conflict-resolution comment was also corrected.

## Phase status

### Phase 1 — Sync Correctness: COMPLETE

Verified:
- local mutation + outbox atomicity for supported mutations;
- stable queue operation IDs and duplicate suppression;
- retry/attention classification and backoff;
- single active queue drain with rerun protection;
- work arriving during a drain is followed up before completion;
- dependency ordering and handler dependency checks;
- startup/initial seeding;
- pre-cloud archived lifecycle seeding;
- pull pagination and cursor acknowledgement;
- cursor advancement only after successful reconciliation;
- canonical reconciliation without creating outbound work;
- safe replay after partial application.

Regression coverage includes:
- queue drain race;
- outbox transaction atomicity;
- archived pre-cloud seed lifecycle;
- pre-sync product create -> archive;
- cursor/reconciliation behavior.

### Phase 2 — Contract Completeness: COMPLETE

The supported V1 mutation inventory was independently traced through local repositories/outbox, handlers, Fulus API commands, production RPC/database mutations, change feed, and canonical reconciliation.

Supported surface:
- products;
- categories;
- suppliers;
- customers;
- customer repayments;
- expenses;
- expense categories;
- income;
- locations;
- sales and sale children;
- returns;
- cash drawer shifts;
- stock movements;
- absolute stock adjustments.

Explicitly outside V1 user-facing writes:
- stock transfers: no mobile write path constructs them;
- sale stock movements: server-derived from sale.create;
- sale payment legs: children of sale.create, not independent cloud commands.

Legacy overloaded server wrappers remain revoked from client roles where retained for compatibility; the Edge Function is the externally reachable write path.

### Phase 3 — Concurrency & Conflict Correctness: COMPLETE

Verified:
- stale/current optimistic-concurrency behavior;
- durable local conflict records and resolution;
- idempotency request-hash conflict behavior;
- cash-drawer serialization;
- product/catalog row locking where required;
- absolute inventory targets serialized by product/stock row locks;
- server-side delta calculation from authoritative stock;
- final absolute target written inside the same transaction;
- unique inventory operation IDs;
- change-feed append in the authoritative transaction.

Production definitions verified for:
- set_inventory_quantity(uuid,uuid,uuid,integer,text,text,uuid)
- apply_inventory_adjustment(uuid,uuid,uuid,integer,text,text,uuid)

### Phase 4 — Recovery, Restore & Scale: COMPLETE at the software/test proof level

Verified lifecycle:

SYNC_CURSOR_TOO_OLD
-> recovery starts / Sync Ready cleared
-> pending-outbox and unresolved-conflict safety gate
-> authoritative restore snapshot
-> atomic local bootstrap/import
-> authoritative boundary persisted
-> delta pull
-> canonical reconciliation
-> Sync Ready

Also verified:
- transaction rollback semantics;
- local-only table preservation;
- business-bound recovery;
- multi-business isolation and failed-switch rollback;
- pagination/bounded canonical reads;
- sync-change indexes;
- 90-day retention;
- active pg_cron retention job;
- durable readiness/recovery state.

A literal physical device-kill test is not claimed. Crash safety is established through transaction semantics, durable-boundary ordering, readiness gates, failure propagation, and automated tests.

### Phase 5 — Production Verification & Final Integration: COMPLETE

Production checks performed against project bejcuvoxemwomcatgyxz:
- migration history;
- Edge Function deployment versions;
- RPC/function definitions and privileges;
- RLS policies;
- indexes;
- change-feed triggers;
- retention job;
- inventory functions;
- restore snapshot function;
- idempotency constraints;
- business/device authorization.

Production Edge Functions:
- fulus-api: v44 ACTIVE
- fulus-sync-state: v4 ACTIVE
- fulus-restore: v7 ACTIVE
- fulus-provision-business: v7 ACTIVE

Production migration history now includes the repository's final absolute-stock atomic-target migration name 202609221410_fix_absolute_stock_adjustment_atomic_target.

## CI / live E2E evidence

Final audit PR CI:
- Run #1480 / 35711931991
- Resolve dependencies: PASS
- Generate Dart code: PASS
- Static analysis: PASS
- Flutter tests: PASS
- Fulus live sync contract E2E: PASS
- APK jobs: SKIPPED

The live E2E exercised:
- authenticated access;
- stale cursor rejection;
- authoritative restore boundary;
- device registration;
- product create;
- stale catalog mutation conflict;
- valid current catalog mutation;
- concurrent absolute stock targets 101/202;
- idempotent replay;
- conflicting idempotent replay;
- cleanup/change-feed behavior.

## Final invariants

Every supported cloud mutation has a durable local intent and a verified server contract. Replay with the same operation identity is safe; altered idempotency input is rejected. Stale mutable writes become explicit conflicts. Pull cursors advance only after successful local application. Stale-cursor recovery bootstraps before incremental pull. Restore cannot replace local cloud-owned state while outbound work or unresolved conflicts are present. Sync Ready is gated on successful post-recovery reconciliation. Absolute stock adjustment is an authoritative server target, not a client-invented delta.

## Audit conclusion

The previous "complete" claim was not sufficient: the second-pass audit found real gaps and fixed them. After the fixes, CI and the live sync contract are green, production state was re-verified, and the final main merge is 41ded8faf08d8d4b407eb95afc1310b8ad86ff05.

APK release/build remains intentionally skipped.
