# Fulus Sync Implementation State

Last verified: 2026-09-22
Repository: FulusBuild/Fulus-mobile
Branch: feat/cloud-sync-v1-hardening-v2
PR: #56 open/unmerged
HEAD: 590d6849c7fb1697d5f42c6a42e135b24cd2ad58
Supabase project: bejcuvoxemwomcatgyxz

## Current truth

Cloud Sync V1 has passed the live catalog/idempotency/concurrency E2E and the latest full CI run #1423 / ID 35689037116 is GREEN on HEAD.

Recovery hardening now also reports failures from the recovery-start lifecycle callback, keeps Sync Health in `recovering` until the post-bootstrap delta pull succeeds, performs a final pending-outbox/conflict gate inside the atomic bootstrap transaction, and persists the authoritative boundary before post-bootstrap pull. The local cloud dataset is explicitly single-business: a durable local business binding now forces authoritative snapshot recovery when the selected business changes, preventing cross-business row mixing.

The recovery lifecycle is now explicitly:
410 SYNC_CURSOR_TOO_OLD -> CloudSyncRecovery -> authoritative snapshot -> atomic bootstrap/import -> persist snapshot boundary cursor -> post-bootstrap delta pull -> Sync Ready.

Earlier live E2E blockers were an ambiguous catalog SQL entity_id reference, a double-wrapped catalog API response, and an E2E assumption that cursor 0 remains readable despite bounded retention. All were fixed and CI subsequently passed.

Production inspection also found an obsolete 9-argument `cloud_catalog_mutate` overload. No repository callers remained; it was removed from production and the matching migration is committed:
`supabase/migrations/202609220500_drop_legacy_cloud_catalog_mutate_overload.sql`

## Implemented

Client: durable local outbox atomicity, queue scheduling/retry, stable operation IDs, machine-readable failures, cursor-aware updates, canonical pull/reconciliation, conflict records/resolution, stale-cursor recovery, atomic restore/bootstrap, local-only table preservation, authoritative snapshot boundary cursor persistence, post-bootstrap delta pull, Sync Health recovery state, Sync Ready gating, bounded canonical batch reads.

Server: JWT verification, membership checks, authenticated-user/device binding, catalog idempotency/request-hash protection, optimistic concurrency, authoritative change-feed emission, bounded pull, restore snapshot boundary, 90-day retention with bounded deletion, daily pg_cron retention, sync-path index/FK cleanup, legacy RPC execute lockdown, obsolete catalog overload removal.

Production functions:
- fulus-api v43
- fulus-sync-state v4
- both JWT verified and actor/device scoped.

## Verification

GitHub:
- PR #56 open/unmerged.
- CI #1431 / 35690922113 was cancelled by subsequent branch updates; the last completed full CI was GREEN before the latest recovery-hardening and RLS-performance changes.
- Generate Dart code GREEN.
- Static analysis GREEN.
- Flutter tests GREEN.
- Live sync contract test GREEN.
- APK build skipped as intended.

Supabase:
- `cloud_catalog_mutate` has exactly one production signature: uuid,uuid,uuid,text,text,text,uuid,jsonb,bigint,text.
- `service_role` can execute that contract.
- Security advisor: `diagnostic_events` RLS-without-policy INFO; leaked-password protection WARN.
- Performance advisor: the six auth.uid() per-row RLS initplan findings were eliminated by migration `supabase/migrations/202609220540_optimize_sync_related_rls_auth_uid_initplan.sql`. Remaining findings are broad multiple-permissive-policy and unused-index notices; do not delete indexes solely from current unused statistics without workload evidence.

## Remaining work

1. Complete the live stale-cursor recovery/replay verification and final CI/E2E audit.
2. Add/run crash and replay coverage: process death during bootstrap, timeout after server commit, pull replay before cursor persistence, token expiry with queued work, revoked device, network loss during recovery.
3. Prove multi-device convergence using the real client coordinator/reconciler.
4. Finalize multi-business isolation verification; the local Drift cloud-owned dataset is single-business and business switches now require authoritative recovery.
5. Perform final architecture, client, server, failure/recovery, scale, Sync Health, production DB/security, final diff, full CI, and E2E/integration audits.
6. APK release remains blocked until those audits pass.

## Next concrete action

Continue the recovery audit from the verified code path:
`SyncTriggers._runSyncCycle -> CloudSyncRecovery.recover -> CloudSyncBootstrapCoordinator.bootstrap -> CloudRestoreImporter -> setCursor(boundary) -> pullAndApply -> onRecoveryReconciled/Sync Ready`.

Then harden the remaining crash/replay and multi-device invariants before final audit.

## Invariants

Every supported syncable mutation is one local transaction containing business mutation plus durable outbox append. Same operation ID plus same request is replay-safe; altered request is rejected. Cursor advances only after reconciliation. Stale mutable writes produce SYNC_CONFLICT. Unresolved conflicts cannot be silently overwritten. Stale cursor recovery bootstraps before incremental pull. The restore transaction commits before its authoritative boundary is persisted. Sync Ready is restored only after the post-recovery pull succeeds.

## Session exit

Before stopping, update this file and docs/FULUS_SYNC_HANDOFF.md with exact HEAD, phase, verified work, CI, production state, next action, and blockers.
