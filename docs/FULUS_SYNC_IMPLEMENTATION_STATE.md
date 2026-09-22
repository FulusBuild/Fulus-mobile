# Fulus Sync Implementation State

Last verified: 2026-09-22
Repository: FulusBuild/Fulus-mobile
Branch: feat/cloud-sync-v1-hardening-v2
PR: #56 open/unmerged
HEAD at this refresh: 5756b54b5eabbe9f8a23018216c363eb71445e95
Supabase project: bejcuvoxemwomcatgyxz

## Current truth

Cloud Sync V1 implementation has completed the durable local-first outbox, authenticated/device-scoped server boundary, idempotent authoritative writes, canonical pull/reconciliation, optimistic concurrency, durable conflicts, stale-cursor recovery, atomic restore/bootstrap, authoritative boundary persistence, post-recovery readiness gating, retention, batch canonical reads, Sync Health, and single-business local dataset isolation.

A phase audit on 2026-09-22 found one genuine contract gap: local absolute stock adjustments were queued but the stock sync handler deliberately rejected them because the server command only accepted deltas. This is now closed. The server has an authoritative absolute-target command (set_inventory_quantity / fulus_api_set_inventory_quantity), the API exposes inventory_set, the client maps stock_adjustment.create, and the handler reconciles the server-returned stock. The production migration 202609221200_phase_2_stock_adjustment_sync is applied and fulus-api is deployed at v44.

The recovery lifecycle is:
410 SYNC_CURSOR_TOO_OLD -> CloudSyncRecovery -> pending/conflict safety gate -> authoritative restore snapshot -> atomic bootstrap/import -> persist snapshot boundary -> post-bootstrap delta pull -> Sync Ready.

The local cloud-owned Drift dataset is intentionally single-business because those tables do not carry business_id. A durable local business binding forces authoritative recovery before a business switch is accepted; failed recovery rolls the selection back.

## Phase status

### Phase 1 — Correctness: COMPLETE
- Local mutation plus durable outbox in one transaction.
- Stable operation IDs and replay-safe retries.
- Queue scheduling, dependency ordering, race handling, startup seeding.
- Cursor advances only after reconciliation.
- Existing local data can be seeded into the sync queue.

### Phase 2 — Contract completeness: COMPLETE for currently supported user-facing sync operations
Verified handler/API coverage includes:
- sales
- sale payments
- customers
- customer updates
- customer repayments
- expenses
- expense updates
- expense categories
- incomes
- locations
- products
- categories
- suppliers
- returns
- cash drawer open/close
- stock in/out
- absolute stock adjustment

Sale-generated stock movements remain server-derived and are not submitted independently. Stock transfer is not exposed by the current stock-movement UI and therefore is not a supported V1 user mutation.

### Phase 3 — Concurrency: IMPLEMENTED
- Base-cursor/revision protection for mutable entities where required.
- Durable sync_conflict_records.
- Explicit cloud/local conflict resolution.
- Idempotency request-hash protection.
- Cash-drawer close concurrency protection.

### Phase 4 — Recovery/scale: IMPLEMENTED
- Stale cursor detection and authoritative snapshot.
- Atomic restore/import.
- Local-only table preservation.
- Authoritative sync_boundary.
- Durable boundary cursor.
- Batch canonical reads.
- Recovery lifecycle/Sync Health.
- 90-day change-feed retention with bounded deletion.
- Daily pg_cron retention.
- Multi-business local isolation.

### Phase 5 — Production/security/performance: IMPLEMENTED
- JWT and membership authorization.
- Device ownership binding.
- RPC execute lockdown.
- Legacy catalog overload removal.
- Catalog idempotency/request-hash protection.
- Sync-path index/FK review.
- auth.uid() initplan RLS optimization.
- Production restore/canonical APIs deployed.

## Production state

- fulus-api: v44 ACTIVE.
- fulus-sync-state: v4.
- Stock-adjustment migration applied as production migration 20260922063556.
- Legacy 9-argument cloud_catalog_mutate overload removed.
- Relevant retention and bootstrap-boundary migrations applied.
- Security advisor still reports the known diagnostic_events RLS INFO and leaked-password protection WARN.
- Remaining performance advisor findings are broad policy/index advisories; unused-index notices are not treated as automatic deletion instructions.

## Verification

Automated client coverage includes:
- queue/retry/race/dependency tests
- canonical reconciliation tests
- conflict resolution tests
- restore/bootstrap tests
- cursor boundary tests
- Sync Trigger recovery/readiness ordering tests
- stock adjustment sync test

The main CI run #1442 / 35693603162 was GREEN on the prior hardening HEAD. New commits after that run require a fresh CI result before merge.

The live server E2E verifies stale-cursor signaling, authoritative snapshot availability, idempotency/concurrency contracts and retention behavior. It is not a substitute for a physical-device/process-death test.

## Final release gates

Before merging PR #56:
1. Fresh CI must be GREEN on the current HEAD.
2. Live sync E2E must pass on the current backend/client contract.
3. Architecture audit.
4. Client-flow audit.
5. Server-flow audit.
6. Failure/recovery audit.
7. Scale/retention and Sync Health audit.
8. Final diff against main.
9. Production migration/function/version verification.
10. Multi-device convergence and replay verification at the available integration-test level.

APK release remains blocked until these gates pass.

## Invariants

Every supported syncable mutation is a local transaction containing the business mutation plus durable outbox append. Same operation ID plus same request is replay-safe; altered request is rejected. Cursor advances only after reconciliation. Stale mutable writes produce SYNC_CONFLICT. Unresolved conflicts cannot be silently overwritten. Stale cursor recovery bootstraps before incremental pull. The restore transaction commits before its authoritative boundary is persisted. Sync Ready is restored only after the post-recovery pull succeeds. Absolute stock adjustment is an authoritative server target, never a client-invented delta.

## Next action

Run fresh CI on the current HEAD, inspect every job, then perform the final five audits and only merge after all release gates are genuinely green.
