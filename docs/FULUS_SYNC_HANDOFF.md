# Fulus Cloud Sync — Fresh Session Handoff

## Mission

Continue the existing Fulus Cloud Sync implementation from the repository state. This is an engineering continuation, not a redesign.

The objective is a production-grade local-first synchronization system in which Fulus remains usable offline, durable local mutations are eventually pushed, authoritative remote changes are pulled, concurrent mutable edits are detected explicitly, and crashes/retries converge without duplicate business effects.

## Read first

Before touching code, read:
1. docs/FULUS_CLOUD_SYNC_V1_ARCHITECTURE.md
2. docs/FULUS_SYNC_IMPLEMENTATION_STATE.md
3. this handoff
4. current PR #56
5. current branch diff against main
6. latest CI for the current HEAD

Then inspect relevant client and Supabase paths rather than relying solely on this document.

## Current repository state

- Repository: FulusBuild/Fulus-mobile
- Branch: feat/cloud-sync-v1-hardening-v2
- PR: #56
- PR status: open, ready for review, not merged
- Production Supabase project: bejcuvoxemwomcatgyxz
- Last verified HEAD: a423cd10a918939646637dd6302bb935196e0901

The branch contains substantial sync hardening. Do not restart or replace it with a new architecture.

## Operating instructions

### Verify before changing

Check:
- branch and HEAD;
- working tree;
- PR status;
- latest CI;
- recent commits;
- architecture/state documents;
- production migrations/functions;
- current client/server implementations.

If a handoff statement disagrees with source, source wins and the state document must be corrected.

### Find the first incomplete invariant

Do not choose the easiest remaining task.

Trace the complete lifecycle:

local mutation
-> local transaction
-> durable outbox
-> scheduler
-> API
-> authentication/business/device authorization
-> idempotency
-> concurrency
-> authoritative server mutation
-> change-feed event
-> cursor
-> canonical read
-> local reconciliation
-> conflict/recovery
-> retry/replay
-> Sync Health

The first missing or weak link becomes the next implementation target.

### Iterate without stopping

For each change:
- implement the complete behavior;
- add or adjust focused tests;
- run broader tests;
- inspect the diff;
- inspect CI;
- fix failures immediately;
- continue to the next dependent gap.

A green CI run is a checkpoint, not the definition of completion.

### Do not manufacture completeness

If a backend contract does not exist, do not invent a client-only implementation and call it synchronized.

If production state differs from repository migrations, verify and reconcile that difference deliberately.

If a recovery path only returns an error but does not recover, it is not implemented.

## Current priority

Phase 4 recovery/bootstrap, bounded canonical batching, retention scheduling, and the remaining production index cleanup are now implemented. The next session must verify the complete lifecycle end-to-end rather than assuming the code path is correct.

Implemented in the current branch:
- stale cursor recovery from machine-readable SYNC_CURSOR_TOO_OLD;
- authoritative snapshot sync boundary in the restore RPC;
- atomic bootstrap/import with local-only data preservation;
- post-bootstrap delta pull;
- explicit Sync Health recovery state;
- bounded canonical batch reads for simple entities;
- production deployment of fulus-sync-state version 3 with JWT verification enabled;
- production verification that repository and deployed fulus-sync-state source match exactly;
- production `pg_cron` retention job `fulus-sync-change-retention` is active daily at 03:30 UTC;
- duplicate sync-path indexes were removed and remaining `staff_invites` FK indexes were added;
- `fulus-api` v41 and `fulus-sync-state` v4 enforce authenticated-user/device binding and match repository source exactly.

The first genuinely incomplete work is now verification and scale hardening:

1. Prove stale-cursor recovery against the live service:
   stale cursor -> 410 -> bootstrap -> boundary cursor -> delta pull -> Sync Ready.
2. Add/run crash and replay tests:
   - process death during bootstrap;
   - push timeout after server commit;
   - pull replay after local apply but before cursor persistence;
   - token expiry with queued work;
   - revoked device;
   - network loss during recovery.
3. Verify the production retention schedule and stale-cursor recovery together once retained history is present; the 90-day pruner and daily pg_cron job are already deployed.
4. Run full architecture/client/server/failure/scale/health/security/diff/CI/E2E audits.
5. Do not build or release an APK before those audits pass.

### Exact next engineering action

Inspect and test the current recovery path first, beginning with:
- lib/data/remote/cloud_sync_recovery.dart
- lib/data/remote/cloud_sync_bootstrap_coordinator.dart
- lib/sync/sync_triggers.dart
- lib/data/remote/fulus_sync_coordinator.dart
- supabase/functions/fulus-api/index.ts
- supabase/functions/fulus-sync-state/index.ts
- the two bootstrap migrations

Then add focused integration coverage for SYNC_CURSOR_TOO_OLD and bootstrap boundary convergence before touching retention.

## Architecture constraints

Fulus synchronizes business operations and authoritative entity state, not the SQLite database itself.

Core invariants:

Mutation atomicity:
ONE LOCAL TRANSACTION
  business mutation
  outbox append

Idempotency:
same operation ID + same request
  -> one business effect
  -> repeat returns authoritative result

Inbound acknowledgement:
reconcile successfully
  -> then advance cursor

Concurrency:
base cursor/revision matches
  -> accept
base cursor/revision stale
  -> SYNC_CONFLICT

Conflict lifecycle:
conflict
  -> durable conflict record
  -> block unsafe inbound overwrite
  -> user chooses Cloud or Local
  -> Cloud: canonical reconcile then resolve
  -> Local: retry from current cursor
  -> resolve only after authoritative retry succeeds

## Existing important components

Expect to encounter:
- SyncEngine
- SyncQueue
- FulusSyncCoordinator
- FulusSyncApi
- typed canonical reconcilers
- SyncConflictRecords
- SyncConflictResolver
- SyncStatusNotifier
- Sync Health UI
- Supabase fulus-api
- sync_changes
- sync_operations
- idempotency infrastructure
- optimistic-concurrency migrations
- catalog mutation infrastructure.

Inspect their current source before editing because the branch continues evolving.

## Failure cases that must eventually be proven

1. Offline mutation -> reconnect -> success.
2. App killed after local mutation -> queue survives.
3. Server commits -> response lost -> same operation retries -> no duplicate effect.
4. Same operation ID with altered payload -> rejected.
5. Pull change -> app killed before acknowledgement -> replay is safe.
6. Concurrent device edit -> explicit conflict.
7. Keep Cloud -> canonical state restored locally.
8. Keep Local -> mutation retries from a current base and remains pending until accepted.
9. Cursor too old -> bootstrap -> delta convergence.
10. Token expiry -> local work preserved.
11. Device revoked -> cloud writes stop without destroying local work.
12. Restore -> stale queue cleared -> canonical reconciliation -> Sync Ready.
13. Bootstrap interrupted -> safe retry/resume.
14. Large change feed -> bounded pages without cursor loss.

## Final audit requirement

Before declaring the project complete, independently inspect:

### Architecture
Does implementation still match the architecture document?

### Client flow
Can every supported local mutation travel through the intended outbox/API/reconciliation lifecycle?

### Server flow
Does every supported command enforce authorization, business/device isolation, idempotency, concurrency where required, authoritative mutation, and change-feed emission?

### Failure/recovery
Can crashes, retries, stale cursors, token expiry, device revocation, and restore converge safely?

### Final
Is the diff coherent? Is CI green for the actual final HEAD? Do tests/E2E cover dangerous paths? Is production Supabase state consistent with the repository?

Only after all five pass should release APK work begin.

## If the session must stop

Update docs/FULUS_SYNC_IMPLEMENTATION_STATE.md before stopping.

Record:
- HEAD;
- current phase;
- exact incomplete item;
- files changed;
- tests run;
- CI run;
- production changes;
- next command/action;
- unresolved risks.

The next session must be able to resume without asking the user what happened.
