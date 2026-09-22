# Fulus Sync Implementation State

Last audited: 2026-09-22
Repository: FulusBuild/Fulus-mobile
Supabase project: bejcuvoxemwomcatgyxz

## Current truth

The Cloud Sync V1 implementation has undergone an independent second-pass audit after the earlier completion claim. The audit deliberately traced local mutation -> durable outbox -> handler -> Edge Function/RPC -> authoritative database mutation -> change feed -> pull -> canonical reconciliation, and separately checked recovery, concurrency, production state, and CI/live E2E evidence.

The audit found and fixed additional material gaps rather than treating the previous completion claim as authoritative:

1. Customer repayment local balance/ledger mutation and durable outbox enqueue are now atomic in one Drift transaction, with regression coverage.
2. Initial cloud seeding now includes pre-cloud archived products/categories/suppliers/customers so create-then-archive lifecycle state is preserved remotely.
3. Pre-sync archived product create-then-archive no longer reuses the stale pre-create cursor for its follow-up delete.
4. Customer ledger initial seeding now uploads only locally-owned `repayment` entries; server-derived `credit_sale` and `refundAdjustment` rows are excluded.
5. Inventory absolute/relative command RPCs now use business-scoped idempotency request hashes and reject same-operation conflicting payloads with `IDEMPOTENCY_CONFLICT`.
6. The service-role action wrappers for sale creation, returns, customer repayments, expenses, sale payments, cash drawer open/close, income, and location creation now also persist request hashes in the same database transaction as the underlying command. This closes the remaining same-operation/different-payload replay gap across the supported command surface.
7. The `fulus-api` generic command error mapper now exposes `P0009` as HTTP 409 `IDEMPOTENCY_CONFLICT`, allowing mobile/live contract consumers to distinguish replay conflicts from ordinary command failures.

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
- server-derived ledger rows are not independently seeded;
- pull pagination and cursor acknowledgement;
- cursor advancement only after successful reconciliation;
- canonical reconciliation without creating outbound work;
- safe replay after partial application.

Regression coverage includes queue-drain races, outbox transaction atomicity, archived pre-cloud seed lifecycle, customer-ledger seed filtering, pre-sync product create -> archive, and cursor/reconciliation behavior.

### Phase 2 — Contract Completeness: COMPLETE

The supported V1 mutation inventory was traced through local repositories/outbox, handlers, Fulus API commands, production RPC/database mutations, change feed, and canonical reconciliation.

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

### Phase 3 — Concurrency & Conflict Correctness: COMPLETE

Verified:
- stale/current optimistic-concurrency behavior;
- durable local conflict records and resolution;
- business-scoped idempotency request-hash conflict behavior across supported commands;
- cash-drawer serialization;
- product/catalog row locking where required;
- absolute inventory targets serialized by product/stock row locks;
- server-side delta calculation from authoritative stock;
- final absolute target written inside the same transaction;
- unique inventory operation IDs;
- change-feed append in the authoritative transaction.

Production inventory definitions verified:
- `set_inventory_quantity(uuid,uuid,uuid,integer,text,text,uuid)`
- `apply_inventory_adjustment(uuid,uuid,uuid,integer,text,text,uuid)`

### Phase 4 — Recovery, Restore & Scale: COMPLETE at the software/test proof level

Verified lifecycle:

`SYNC_CURSOR_TOO_OLD`
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

Production checks performed against project `bejcuvoxemwomcatgyxz`:
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

Latest production hardening migrations:
- `202609221500_inventory_command_idempotency`
- `202609221530_action_command_idempotency`

Production migration history records the connector-applied versions for these migrations, and the production `fulus-api` is now ACTIVE at version 45 with the final `P0009 -> IDEMPOTENCY_CONFLICT` mapper.

## CI / live E2E evidence

The final hardening CI is required to be green before merge.

Required successful jobs:
- Resolve dependencies
- Generate Dart code
- Static analysis
- Flutter tests
- Fulus live sync contract E2E

APK jobs remain skipped.

The live E2E covers:
- authenticated access;
- stale cursor rejection;
- authoritative restore boundary;
- ephemeral device registration;
- product create;
- stale catalog mutation conflict;
- valid current catalog mutation;
- concurrent absolute stock targets 101/202;
- same-payload inventory replay;
- conflicting inventory replay -> `IDEMPOTENCY_CONFLICT`;
- generic idempotent replay;
- conflicting generic replay;
- product delete cleanup/change-feed behavior.

The first hardening CI attempt exposed one real integration gap: the database correctly raised `P0009`, but the generic `fulus-api` action error mapper returned HTTP 400 `COMMAND_FAILED`. That mapper was fixed and production `fulus-api` was redeployed as version 45. The next CI/live E2E run is the final verification gate.

## Final invariants

Every supported cloud mutation has a durable local intent and a verified server contract. Same-operation replay with the same request is safe; same-operation replay with altered request data is rejected as `IDEMPOTENCY_CONFLICT`. Stale mutable writes become explicit conflicts. Pull cursors advance only after successful local application. Stale-cursor recovery bootstraps before incremental pull. Restore cannot replace local cloud-owned state while outbound work or unresolved conflicts are present. Sync Ready is gated on successful post-recovery reconciliation. Absolute stock adjustment is an authoritative server target, not a client-invented delta.

## Audit conclusion

Cloud Sync V1 is not declared final until the current hardening branch's CI/live E2E passes after the production `fulus-api` version-45 deployment, the PR is merged, and main is re-verified at the merge commit.

APK release/build remains intentionally skipped.
