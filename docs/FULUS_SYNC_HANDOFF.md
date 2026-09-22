# Fulus Cloud Sync — Fresh Session Handoff

## Mission

Continue PR #56 as an engineering continuation. Goal: production-grade local-first convergence with durable offline mutations, authenticated/device-scoped push, idempotent authoritative writes, canonical pull, explicit concurrency conflicts, crash-safe recovery, and trustworthy Sync Health.

## Current state

Repository: FulusBuild/Fulus-mobile
Branch: feat/cloud-sync-v1-hardening-v2
PR #56: open, unmerged
Supabase: bejcuvoxemwomcatgyxz

CI #1418 / 35688023237 is GREEN on commit 6e8bca79d05ed54d2f89938734024f07fa61023f.

Three E2E blockers were fixed: ambiguous catalog concurrency SQL, double-wrapped catalog response, and stale-retention cursor handling.

Production then revealed an obsolete 9-argument cloud_catalog_mutate overload. No repository callers remain. It was removed from production and committed as:
supabase/migrations/202609220500_drop_legacy_cloud_catalog_mutate_overload.sql

Only the 10-argument bigint-base-cursor contract remains.

## Implemented lifecycle

local mutation -> local transaction -> durable outbox -> scheduler/retry -> authenticated API -> membership/device authorization -> idempotency -> optimistic concurrency -> authoritative mutation -> sync_changes -> pull -> canonical reconciliation -> cursor advancement -> conflict/recovery -> Sync Health.

Recovery path:
stale cursor -> SYNC_CURSOR_TOO_OLD -> CloudSyncRecovery -> authoritative restore snapshot -> atomic bootstrap/import -> sync_boundary -> delta pull -> Sync Ready only after successful reconciliation.

Restore preserves local-only data and does not replay stale pre-restore outbound work.

## Production

fulus-api v43: JWT verified, membership/device actor binding, corrected catalog response envelope.
fulus-sync-state v4: JWT verified, authenticated-user/device binding.
90-day sync_changes retention with bounded deletion and daily pg_cron.
Sync-path index/FK cleanup completed.
Legacy catalog overload removed.

Remaining advisor findings:
- diagnostic_events RLS without policy (INFO);
- leaked-password protection disabled (WARN);
- broad RLS performance warnings and unused-index notices.
Do not treat unused-index notices as automatic deletion instructions.

## Next work — continue, do not stop at green CI

1. Recovery integration: prove 410 -> bootstrap -> boundary cursor -> delta pull -> Sync Ready through the real client.
2. Crash/replay: process death during bootstrap; timeout after server commit; pull replay before cursor persistence; token expiry; revoked device; network loss.
3. Multi-device convergence: device A mutation -> server -> device B pull -> canonical reconciliation -> cursor; concurrent edit -> durable conflict -> Cloud/Local resolution.
4. Final audits: architecture, client, server, failure/recovery, scale, Sync Health, production DB/security, final diff, full CI, E2E/integration.
5. APK remains blocked until all audits pass.

## Required source inspection

Start with:
- lib/sync/sync_triggers.dart
- lib/data/remote/cloud_sync_recovery.dart
- lib/data/remote/cloud_sync_bootstrap_coordinator.dart
- lib/data/remote/fulus_sync_coordinator.dart
- lib/app/bootstrap.dart
- restore snapshot API/importer
- Sync Health notifier/UI
- supabase/functions/fulus-api/index.ts
- supabase/functions/fulus-sync-state/index.ts

Then implement the first missing invariant; do not redo completed work.

## Operating rules

Source and live production state outrank this document. Do not invent backend contracts. Do not advance cursors before reconciliation. Do not silently overwrite unresolved local mutations. Do not delete indexes merely because current advisor statistics say unused. Do not perform destructive resets. Continue through dependent work rather than stopping after a status report.

## Session exit

Before stopping, update both sync docs with exact HEAD, CI, production state, completed work, remaining work, and first next action.
