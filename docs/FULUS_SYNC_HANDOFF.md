# Fulus Cloud Sync — Fresh Session Handoff

## Mission

Continue PR #56 as an engineering continuation. Goal: production-grade local-first convergence with durable offline mutations, authenticated/device-scoped push, idempotent authoritative writes, canonical pull, explicit concurrency conflicts, crash-safe recovery, and trustworthy Sync Health.

## Current state

Repository: FulusBuild/Fulus-mobile
Branch: feat/cloud-sync-v1-hardening-v2
PR #56: open, unmerged
Current HEAD: 8fbf596008dd5fa004202ba8a0774ce410fac89e
Supabase: bejcuvoxemwomcatgyxz

CI #1423 / 35689037116 is GREEN. It passed dependency resolution, Dart generation, static analysis, Flutter tests, and the live Fulus sync contract test. APK build remains intentionally skipped.

The latest code fix repaired a malformed `lib/app/bootstrap.dart` introduced during cursor hardening and preserved the intended change: after the authoritative restore transaction commits, `FulusSyncCoordinator.setCursor(businessId, boundary)` persists the snapshot boundary before the post-bootstrap delta pull.

Coordinator tests cover authoritative boundary persistence and rejection of negative boundaries.

## Verified lifecycle

local mutation -> local transaction -> durable outbox -> scheduler/retry -> authenticated API -> membership/device authorization -> idempotency -> optimistic concurrency -> authoritative mutation -> sync_changes -> pull -> canonical reconciliation -> cursor advancement -> conflict/recovery -> Sync Health.

Recovery:
stale cursor -> SYNC_CURSOR_TOO_OLD -> CloudSyncRecovery -> pending/conflict preflight -> authoritative restore snapshot -> atomic bootstrap/import -> persist snapshot boundary -> delta pull -> Sync Ready only after successful reconciliation.

The bootstrap transaction preserves local-only tables and recreates local authentication/session state. Process death during that transaction rolls the database transaction back. A process death after commit but before SharedPreferences cursor persistence can cause a safe recovery replay; the snapshot remains authoritative and bootstrap is transactional.

## Production

fulus-api v43: JWT verified, membership/device actor binding, corrected catalog response envelope.
fulus-sync-state v4: JWT verified, authenticated-user/device binding.
90-day sync_changes retention with bounded deletion and daily pg_cron.
Sync-path index/FK cleanup completed.
Obsolete 9-argument catalog mutation overload removed; only the 10-argument bigint-base-cursor contract remains.

Remaining advisor findings:
- diagnostic_events RLS without policy (INFO);
- leaked-password protection disabled (WARN);
- broad RLS performance warnings and unused-index notices.
Do not treat unused-index notices as automatic deletion instructions.

## Next work — continue, do not stop at green CI

1. Prove the complete stale-cursor recovery path through a real client session, including replay after a process restart.
2. Add/run crash and replay coverage: process death during bootstrap; timeout after server commit; pull replay before cursor persistence; token expiry with queued work; revoked device; network loss during recovery.
3. Prove multi-device convergence: device A mutation -> server -> device B pull -> canonical reconciliation -> cursor; concurrent edit -> durable conflict -> explicit resolution.
4. Audit multi-business isolation. Current recovery preflight checks the local sync queue/conflicts globally because queue rows do not currently carry business_id; determine whether this is an intentional single-active-business invariant or requires scoping.
5. Perform final architecture, client, server, failure/recovery, scale, Sync Health, production DB/security, final diff, full CI, and E2E/integration audits.
6. APK remains blocked until all audits pass.

## Required source inspection

Start with:
- lib/sync/sync_triggers.dart
- lib/data/remote/cloud_sync_recovery.dart
- lib/data/remote/cloud_sync_bootstrap_coordinator.dart
- lib/data/remote/fulus_sync_coordinator.dart
- lib/app/bootstrap.dart
- lib/data/remote/cloud_restore_importer.dart
- restore snapshot API
- Sync Health notifier/UI
- supabase/functions/fulus-api/index.ts
- supabase/functions/fulus-sync-state/index.ts

Then implement the first missing invariant; do not redo completed work.

## Operating rules

Source and live production state outrank this document. Do not invent backend contracts. Do not advance cursors before reconciliation. Do not silently overwrite unresolved local mutations. Do not delete indexes merely because current advisor statistics say unused. Do not perform destructive resets. Continue through dependent work rather than stopping after a status report.

## Session exit

Before stopping, update both sync docs with exact HEAD, CI, production state, completed work, remaining work, and first next action.
