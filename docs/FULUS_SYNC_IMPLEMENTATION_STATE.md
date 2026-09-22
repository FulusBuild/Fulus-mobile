# Fulus Sync Implementation State

Last audited: 2026-09-22
Repository: FulusBuild/Fulus-mobile
Audit branch: audit/cloud-sync-v1-completion
PR: #58 (audit continuation)
Main merge base: 4114ee538b1622df95c72faabbc301d584232fea
Current code HEAD: 5bcac523a6622987be6cfafbadd0af0a9573d574f
Supabase project: bejcuvoxemwomcatgyxz

## Current truth

The V1 completion audit found two additional real lifecycle/concurrency gaps after PR #57:
1. Archived products created offline could be pushed as active products because product.update was queued/coalesced into product.create without a cloud delete.
2. Concurrent absolute stock targets could still race inside the server's nested delta RPC. The production live E2E reproduced this with a stock_nonnegative constraint failure.

Both gaps are now fixed:
- Product create/update/delete lifecycle is explicit and idempotent.
- Archived offline-created customers complete create -> archive update; catalog archive handlers also converge correctly.
- Absolute stock targets are now serialized on the product/stock row and written directly to the requested absolute target inside one server transaction.
- Production migration fix_absolute_stock_adjustment_atomic_target is applied.
- Live E2E run #1468 / 35703729612 passed after the production fix.

## Phase status

### Phase 1 — Correctness: COMPLETE
- Business mutation + durable outbox append occur in the same local transaction.
- Stable operation IDs and replay-safe retry classification.
- Queue drain race protection and follow-up draining.
- Dependency-aware ordering and startup seeding.
- Duplicate queue suppression.
- Base-cursor capture.
- Canonical reconciliation.
- Cursor advancement only after the complete feed page is reconciled.

### Phase 2 — Contract completeness: COMPLETE for the supported V1 user-facing mutation surface
Verified client/server paths cover:
- sale create
- customer create/update/archive/restore
- customer repayment
- expense create/update
- expense category create
- income create
- location create
- product/category/supplier catalog create/update/delete
- return create
- cash drawer open/close
- stock in/out
- absolute stock adjustment

Sale payment legs are local children of sale.create and are not independent cloud mutations. Sale stock movements are server-derived. Stock transfer is intentionally outside the current V1 user-facing command surface.

### Phase 3 — Concurrency/idempotency: COMPLETE
- Optimistic base-cursor protection for mutable entities.
- Durable local conflict records and explicit resolution.
- Request-hash/idempotency conflict protection.
- Cash drawer close serialization.
- Absolute stock target serialization at the database row level.
- Live E2E exercises stale/current catalog concurrency, concurrent absolute stock targets, idempotent replay, and conflicting replay.

### Phase 4 — Recovery/scale: COMPLETE at the software/test proof level
Recovery lifecycle:
SYNC_CURSOR_TOO_OLD -> CloudSyncRecovery -> pending/conflict safety gate -> authoritative restore snapshot -> atomic bootstrap/import -> persist authoritative boundary -> delta pull -> reconciliation -> Sync Ready.

Verified:
- stale-cursor detection
- authoritative restore snapshot
- atomic local bootstrap/import
- local-only table preservation
- durable authoritative sync boundary
- post-bootstrap delta pull
- canonical batch reads
- 90-day feed retention
- active pg_cron retention job
- Sync Health/recovery lifecycle state
- single-business cloud dataset isolation
- authoritative recovery on business switching
- rollback of business selection on failed recovery

Physical device-kill testing is not claimed as a literal live-device test. Crash safety is proven through transaction atomicity, durable-boundary ordering, readiness gating, failure propagation, and automated recovery tests.

### Phase 5 — Production/security/performance/final integration: COMPLETE
Verified against production:
- JWT authentication and membership checks
- device ownership/status authorization
- restricted RPC execute privileges
- catalog actor/membership authorization
- idempotency/request-hash behavior
- sync feed indexes and FK/index review
- RLS policies on sync_changes/sync_operations/devices/idempotency_keys
- 90-day retention and active cron schedule
- restore snapshot and canonical-state functions
- production edge functions
- production migration history
- final live sync E2E

## Production state

- fulus-api: v44 ACTIVE.
- fulus-sync-state: v4.
- Absolute stock migrations applied through fix_absolute_stock_adjustment_atomic_target.
- Legacy 9-argument cloud_catalog_mutate overload removed.
- Bootstrap-boundary and retention migrations applied.
- Known Supabase advisor findings remain outside the Cloud Sync V1 correctness contract: diagnostic_events RLS INFO, leaked-password protection WARN, and broad unused-index/policy advisories. Indexes are not removed solely from advisor statistics.

## Verification evidence

Latest green CI:
- Run #1468
- Run ID 35703729612
- HEAD 5bcac523a6622987be6cfafbadd0af0a9573d574f
- Resolve dependencies: PASS
- Generate Dart code: PASS
- Static analysis: PASS
- Flutter tests: PASS
- Fulus live sync contract E2E: PASS
- APK jobs: intentionally skipped

Live E2E explicitly passed:
- fresh Supabase authentication
- stale cursor rejection
- authoritative restore boundary
- ephemeral device registration
- product create
- stale catalog update -> SYNC_CONFLICT
- current catalog update
- concurrent absolute targets 101/202
- committed post-concurrency stock is one of the requested targets
- idempotent replay
- conflicting replay -> IDEMPOTENCY_CONFLICT
- product delete cleanup

## Final completion gate

Before declaring the V1 work fully complete:
1. Keep the current audit branch CI green after documentation changes.
2. Re-check the final diff against main.
3. Re-check production migration history and function definitions.
4. Merge PR #58 only after those checks.
5. Do not trigger an APK release as part of this audit.

## Invariants

Every supported mutation is local-first and durable. Replay with the same operation/request is safe; altered idempotency input is rejected. Mutable stale writes become explicit conflicts. Cursor advancement happens only after reconciliation. Stale-cursor recovery bootstraps before incremental pull. Restore commits before the durable boundary is persisted. Sync Ready follows successful post-recovery reconciliation. Absolute stock adjustment is an authoritative target, never a client-invented delta.
