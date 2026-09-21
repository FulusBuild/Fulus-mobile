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
- Last verified HEAD recorded in the state document.

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

The immediate unfinished layer is Phase 4 recovery/bootstrap.

The server can already report a stale cursor using a machine-readable SYNC_CURSOR_TOO_OLD response. The missing architectural step is actual client recovery.

Implement:

stale cursor
-> explicit recovery state
-> authoritative snapshot/bootstrap
-> safe local reconciliation
-> cursor replacement at known sequence boundary
-> delta pull after boundary
-> Sync Ready

Requirements:
- no silent data loss;
- no skipped feed changes;
- preserve or explicitly reconcile legitimate local pending mutations;
- bounded/resumable work where practical;
- safe after process death;
- idempotent retry;
- clear Sync Health state.

Then continue through:
- batch canonical reads;
- replay/crash recovery;
- token/device recovery;
- retention/compaction;
- authoritative Sync Health;
- final five audits.

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
