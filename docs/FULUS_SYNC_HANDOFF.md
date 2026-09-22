# Fulus Cloud Sync — Fresh Session Handoff

## Mission
Continue PR #57 to production-grade local-first convergence with durable offline mutations, authenticated/device-scoped push, idempotent authoritative writes, canonical pull, explicit concurrency conflicts, crash-safe recovery, and trustworthy Sync Health.

## Current state
Repository: FulusBuild/Fulus-mobile
Branch: feat/cloud-sync-v1-hardening-v2
PR #57: open, unmerged
HEAD at this refresh: bbd259b9ecea1bbd8057edac454c0fe53810d50b
Supabase: bejcuvoxemwomcatgyxz

A complete phase audit on 2026-09-22 found and closed the one genuine V1 contract gap: absolute stock adjustments were locally queueable but rejected by the cloud handler. The server now exposes an authoritative absolute-target stock command, the API exposes inventory_set, the client maps stock_adjustment.create, and the handler reconciles the returned stock.

Production:
- fulus-api v44 ACTIVE
- fulus-sync-state v4
- stock-adjustment migration applied
- legacy 9-argument cloud_catalog_mutate overload removed
- retention and bootstrap-boundary migrations applied

The prior full CI run #1442 / 35693603162 was GREEN. New commits after that run require a fresh CI result.

## Verified lifecycle
local mutation -> local transaction -> durable outbox -> scheduling/retry -> authenticated API -> membership/device authorization -> idempotency -> optimistic concurrency -> authoritative mutation -> sync_changes -> pull -> canonical reconciliation -> cursor advancement -> conflict/recovery -> Sync Health.

Recovery:
stale cursor -> SYNC_CURSOR_TOO_OLD -> CloudSyncRecovery -> pending/conflict gate -> authoritative restore snapshot -> atomic bootstrap/import -> persist boundary -> delta pull -> Sync Ready.

The local cloud-owned Drift dataset is single-business. A durable binding forces authoritative recovery before a business switch; failed recovery rolls the UI selection back.

## Supported V1 command coverage
- sale create/payment
- customer create/update/repayment
- expense create/update
- expense category create
- income create
- location create
- product/category/supplier catalog mutations
- return create
- cash drawer open/close
- stock in/out
- absolute stock adjustment

Sale stock movements are server-derived. Stock transfer is not exposed by the current V1 UI and is not a supported user mutation.

## Verification coverage
Unit/integration coverage exists for:
- queue/retry/races/dependencies
- canonical reconciliation
- conflicts
- restore/bootstrap
- cursor boundaries
- Sync Trigger recovery/readiness ordering
- stock adjustment synchronization

Live server E2E covers stale-cursor contract, authoritative snapshot availability, idempotency/concurrency and retention behavior.

## Release gates still to execute
1. Fresh CI on current HEAD.
2. Live E2E on current HEAD/backend.
3. Architecture audit.
4. Client-flow audit.
5. Server-flow audit.
6. Failure/recovery audit.
7. Scale/retention/Sync Health audit.
8. Final diff against main.
9. Production migration/function/version verification.
10. Multi-device convergence and replay verification at the available integration-test level.

Do not merge PR #57 or trigger the APK until these gates are genuinely green.

## Operating rules
Source and live production state outrank this handoff. Do not redo completed work. Do not advance cursors before reconciliation. Do not silently overwrite unresolved mutations. Do not delete indexes merely because advisor statistics say unused. Do not perform destructive resets. Continue dependent work without stopping for progress reports.

## Session exit
Update this handoff and FULUS_SYNC_IMPLEMENTATION_STATE.md with exact HEAD, CI, production versions, completed gates, unresolved risks, and next action.
