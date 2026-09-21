# Fulus Sync Implementation State

Purpose: durable resume point for future engineering sessions.
Last verified: 2026-09-21
Repository: FulusBuild/Fulus-mobile
Working branch: feat/cloud-sync-v1-hardening-v2
Open PR: #56
PR state: open, ready for review, not merged
Current branch HEAD at handoff creation: 7e526b9305ce23be00b01d741d6efe289bbf87f7
Production Supabase project: bejcuvoxemwomcatgyxz

This is a resume contract, not permission to trust old claims blindly. A new session MUST verify the repository, CI, deployed database/functions, and relevant code before extending the implementation.

## Current objective

Continue Fulus Cloud Sync toward production-grade local-first convergence. The next incomplete architectural layer is Phase 4 recovery/bootstrap, followed by remaining scale, health, and production verification work.

Do not stop merely because CI becomes green.

## Verified baseline

### Phase 1 — correctness
Implemented work includes:
- stale sync queue cleanup during restore;
- SyncEngine drain-race follow-up run;
- supplier update outbox atomicity;
- supplier update sync regression coverage;
- customer/expense update work where verified cloud commands exist.

### Phase 2 — cloud contract hardening
Implemented work includes:
- catalog change-feed triggers;
- catalog idempotency and request-hash protection;
- customer/expense command contract hardening;
- location/permission/actor checks;
- machine-readable sync error handling;
- removal/lockdown of legacy public RPC execution paths;
- production migrations applied during the current hardening effort.

### Phase 3 — concurrency
Implemented work includes:
- durable sync_queue_items.base_cursor;
- client update payloads carrying base cursor where supported;
- server optimistic concurrency checks;
- SYNC_CONFLICT machine-readable response;
- durable sync_conflict_records;
- conflict-aware Sync Health;
- explicit Keep Cloud Version resolution;
- explicit Keep My Version retry path;
- inbound-pull protection while unresolved conflicts exist.

These items MUST still be independently verified before being called production-complete.

### Performance/security work already performed
- sync-path FK indexes added;
- redundant/duplicate indexes removed;
- catalog/command execute privileges tightened;
- cash-drawer close execute lockdown added;
- production security/performance advisors inspected;
- known remaining advisor findings are outside the immediate sync critical path or require broader policy decisions.

## Current CI truth

The previously observed run #1351 / ID 35614605680 was cancelled because it was superseded. It is NOT evidence of success or failure.

The handoff documents themselves were then committed in three documentation commits. The current HEAD recorded above is the source point for the next session.

The next session MUST inspect the newest workflow run for the current HEAD before making claims about CI.

## Immediate next actions

### Phase 4A — cursor-too-old recovery
The server already detects a stale/too-old sync cursor and returns a machine-readable recovery-required response.

This is NOT complete recovery.

Implement and verify:
1. client recognizes SYNC_CURSOR_TOO_OLD;
2. coordinator enters an explicit recovery state;
3. local cursor is NOT silently advanced;
4. device obtains an authoritative bootstrap/snapshot;
5. bootstrap is reconciled safely;
6. pending local mutations are preserved or explicitly reconciled according to policy;
7. cursor is replaced only after bootstrap succeeds;
8. Sync Ready is reached only after reconciliation;
9. repeated recovery is idempotent;
10. app kill during bootstrap resumes safely.

### Phase 4B — bootstrap/snapshot
Design the smallest production-safe protocol compatible with the current architecture:
- authoritative snapshot or bounded bootstrap;
- server-side business scoping;
- stable snapshot cursor/sequence boundary;
- bounded payloads;
- resumability if practical;
- local import/reconciliation;
- post-bootstrap delta pull;
- no skipped changes between snapshot boundary and final cursor.

Do not invent a second synchronization architecture.

### Phase 4C — batch canonical reads
Replace avoidable one-entity-at-a-time canonical fetches with bounded batching where the existing server contract supports it. Preserve per-entity reconciliation and error isolation.

### Phase 4D — failure/replay
Add tests for:
- timeout after server commit;
- replay with same operation ID;
- replay with different request;
- app kill during push;
- app kill after server acceptance but before local queue removal;
- app kill during pull;
- app kill during bootstrap;
- token expiry with queued work;
- revoked device;
- network loss during recovery.

### Phase 5 — scale
Then implement/verify:
- bounded change-feed pages;
- batch canonical reads;
- snapshot/bootstrap;
- cursor retention/compaction;
- observability;
- per-business isolation;
- sensible rate limits.

Do not optimize by weakening correctness.

### Phase 6 — authoritative Sync Health
Sync Health must expose facts from the actual sync system:
- cloud connection;
- device authorization;
- Sync Ready;
- last successful push;
- last successful pull;
- pending;
- retrying;
- blocked/attention;
- conflicts;
- last sync error;
- current cursor;
- recovery/bootstrap state if active.

### Phase 7 — final verification
Perform all five independently:
1. architecture audit;
2. client-flow audit;
3. server-flow audit;
4. failure/recovery audit;
5. final diff + CI + integration/E2E + production audit.

Only after all five pass should an APK be built.

## Critical invariants

Every syncable mutation is one local transaction containing the business mutation and durable outbox append.

Every outbound operation has:
- stable operation ID;
- deterministic request envelope;
- server idempotency;
- same ID plus same request = same authoritative effect/result;
- same ID plus materially different request = explicit rejection.

Inbound:
- reconcile before acknowledging cursor;
- never silently skip a change;
- canonical state is authoritative.

Concurrency:
- mutable updates carry server base cursor/revision where supported;
- stale edits produce SYNC_CONFLICT;
- conflicting local work is durable;
- inbound pull must not overwrite unresolved dirty local state;
- conflict resolution explicitly chooses cloud or local;
- choosing local only clears the conflict after the retried authoritative mutation succeeds.

Restore:
- stale pre-restore outbound queue must not replay old state;
- canonical reconciliation must finish before Sync Ready.

## Known traps

- Do not treat cloud sync as backup-only.
- Do not fake a server contract for an entity whose backend does not exist.
- Do not claim an entity is syncable because a Dart handler exists.
- Do not use message text as the primary error classifier when a machine-readable code exists.
- Do not delete an outbox item merely because the HTTP request was sent.
- Do not advance the cursor before successful reconciliation.
- Do not let inbound canonical state overwrite an unresolved local mutation.
- Do not assume idempotency solves concurrency.
- Do not call cursor-too-old detection recovery until the client actually bootstraps.
- Do not release an APK before the five final audits.
- Do not perform destructive rebuild/reset operations to hide state problems.

## Definition of done

Fulus Cloud Sync v1 is complete only when the architecture document definition of done is satisfied in code and verified by tests:
- offline create/update;
- app close/reopen without losing pending work;
- reconnect without duplicate financial effects;
- multiple authorized devices;
- inbound changes from another device;
- crash-safe push/pull/restore/bootstrap;
- authentication/device recovery;
- explicit concurrent-edit handling;
- trustworthy Sync Health;
- restore reaches Sync Ready only after reconciliation.

## Session exit protocol

If work stops before completion, update this file with:
- exact HEAD;
- exact phase/sub-phase;
- what was implemented;
- what was verified;
- CI run ID and conclusion;
- production migration/function state;
- first concrete next action;
- known blockers.

Never leave the next session to infer the resume point from chat history.
