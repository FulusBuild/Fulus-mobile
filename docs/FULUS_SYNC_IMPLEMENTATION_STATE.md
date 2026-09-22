# Fulus Sync Implementation State

Last verified: 2026-09-22
Repository: FulusBuild/Fulus-mobile
Branch: feat/cloud-sync-v1-hardening-v2
PR: #56 open/unmerged
HEAD before docs refresh: 6b5a3c51e86a2ba04185c328ddb9cbe5f5fb82bb
Supabase project: bejcuvoxemwomcatgyxz

## Current truth

Cloud Sync V1 is past the live E2E contract blocker. CI run #1418 / ID 35688023237 passed on commit 6e8bca79d05ed54d2f89938734024f07fa61023f.

The live E2E now completes the catalog/idempotency/concurrency contract. Previous failures were caused by an ambiguous SQL entity_id reference, a double-wrapped catalog API response, and an E2E assumption that cursor 0 must remain readable despite bounded retention.

After the green checkpoint, production inspection found an obsolete 9-argument cloud_catalog_mutate overload still executable by service_role. No repository callers remain. It was removed from production and the matching migration was committed:
supabase/migrations/202609220500_drop_legacy_cloud_catalog_mutate_overload.sql

Production now exposes only the 10-argument catalog mutation contract with bigint base_cursor.

## Implemented

Client: durable local outbox atomicity, queue scheduling/retry, stable operation IDs, machine-readable failures, cursor-aware updates, canonical pull/reconciliation, conflict records/resolution, stale-cursor recovery, atomic restore/bootstrap, local-only table preservation, snapshot boundary cursor, post-bootstrap delta pull, Sync Health recovery state, Sync Ready gating, bounded canonical batch reads.

Server: JWT verification, membership checks, authenticated-user/device binding, catalog idempotency/request-hash protection, optimistic concurrency, authoritative change-feed emission, bounded pull, restore snapshot boundary, 90-day retention with bounded deletion, daily pg_cron retention, sync-path index/FK cleanup, legacy RPC execute lockdown, obsolete catalog overload removal.

Production functions:
- fulus-api v43
- fulus-sync-state v4
- both JWT verified and actor/device scoped.

## Verification

GitHub:
- PR #56 open/unmerged.
- CI #1418 / 35688023237 green.
- APK build skipped as intended.

Supabase:
- cloud_catalog_mutate has exactly one production signature: uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text.
- service_role can execute that contract.
- Security advisor: diagnostic_events RLS-without-policy INFO; leaked-password protection WARN.
- Performance advisor: broad RLS optimization and unused-index notices remain. Do not delete indexes solely from current unused statistics without workload evidence.

## Remaining work

1. Prove full stale-cursor recovery through the real client: 410 -> bootstrap -> sync_boundary -> delta pull -> Sync Ready.
2. Add/run crash and replay tests: process death during bootstrap, timeout after server commit, pull replay before cursor persistence, token expiry with queued work, revoked device, network loss during recovery.
3. Prove multi-device convergence using the real client coordinator/reconciler.
4. Perform final architecture, client, server, failure/recovery, scale, Sync Health, production DB/security, final diff, CI, and E2E audits.
5. APK release remains blocked until those audits pass.

## Next concrete action

Trace SyncTriggers -> CloudSyncRecovery -> CloudSyncBootstrapCoordinator -> restore/import -> FulusSyncCoordinator -> Sync Health, then add/strengthen integration coverage proving stale-cursor recovery reaches Sync Ready.

## Invariants

Every supported syncable mutation is one local transaction containing business mutation plus durable outbox append. Same operation ID plus same request is replay-safe; altered request is rejected. Cursor advances only after reconciliation. Stale mutable writes produce SYNC_CONFLICT. Unresolved conflicts cannot be silently overwritten. Stale cursor recovery must bootstrap before incremental pull. Sync Ready means reconciliation completed.

## Session exit

Before stopping, update this file and docs/FULUS_SYNC_HANDOFF.md with exact HEAD, phase, verified work, CI, production state, next action, and blockers.
