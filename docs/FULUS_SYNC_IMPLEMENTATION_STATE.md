# Fulus Sync Implementation State

Purpose: durable resume point for future engineering sessions.
Last verified: 2026-09-21
Repository: FulusBuild/Fulus-mobile
Working branch: feat/cloud-sync-v1-hardening-v2
Open PR: #56
PR state: open, ready for review, not merged
Current branch HEAD before this final state-document commit: df54967494deb1255afd0988211b5aa725690de5
Production Supabase project: bejcuvoxemwomcatgyxz

This is a resume contract, not permission to trust old claims blindly. A new session MUST verify the repository, CI, deployed database/functions, and relevant code before extending the implementation.

## Current objective

Continue Fulus Cloud Sync toward production-grade local-first convergence. Phase 4 recovery/bootstrap and bounded canonical batching are now implemented in the branch and deployed for the canonical-read function. Remaining work is crash/E2E verification, retention/compaction scheduling, full audit, and CI.

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

## Current session implementation

### Phase 4A — cursor-too-old recovery
Implemented:
- machine-readable SYNC_CURSOR_TOO_OLD is classified by ApiClient;
- SyncTriggers now catches the protocol signal and invokes explicit recovery;
- CloudSyncRecovery blocks bootstrap when outbound queue items or unresolved conflicts exist;
- authoritative restore snapshot now contains sync_boundary;
- CloudSyncBootstrapCoordinator imports the snapshot atomically and recreates the active local identity/session;
- bootstrap preserves local-only/unexported tables such as attendance, leave, supplier ledger, and tax remittance data;
- cursor is replaced only after the bootstrap transaction commits;
- the coordinator then performs the normal delta pull from the snapshot boundary;
- Sync Health records recovery state (idle, recovering, blocked) and the last recovery error;
- Sync Ready is cleared while recovery runs.

### Phase 4B — snapshot boundary
Implemented and production-applied:
- restore snapshot version is now 6;
- sync_boundary is the per-business max sync_changes.sequence from the same PostgreSQL statement snapshot as the exported business rows;
- expense categories are included now that the production table exists;
- production RPC definition was verified directly;
- production migrations sync_bootstrap_boundary and bootstrap_snapshot_expense_categories are applied.

### Phase 4C — batch canonical reads
Implemented:
- fulus-sync-state supports entity_ids batches capped at 100 for simple entities;
- the function is deployed as version 3 with JWT verification enabled;
- repository source and deployed function source are byte-for-byte identical;
- FulusSyncApi implements the batch transport contract;
- FulusCanonicalTypedReconciler batches simple entities while retaining per-entity canonical handlers;
- FulusSyncCoordinator can apply a feed page as one reconciliation batch and only advances the cursor after the whole page succeeds.

### Sync Health
Implemented:
- recovery state and last recovery error are persisted;
- Sync Health UI displays recovery state/error alongside push/pull/cursor facts.

## Current verification truth

Production Supabase:
- project: bejcuvoxemwomcatgyxz
- fulus-api: version 39, repository source matches deployed source exactly, verify_jwt=true;
- fulus-sync-state: version 3, repository source matches deployed source exactly, verify_jwt=true;
- latest migrations applied: sync_bootstrap_boundary, bootstrap_snapshot_expense_categories;
- production restore snapshot RPC returned version 6, a valid sync_boundary, and an expense_categories array for a real owner-authorized business;
- production security advisor still reports diagnostic_events RLS-without-policy (INFO) and leaked-password protection disabled (WARN);
- production performance advisor still reports several non-sync-path findings plus multiple permissive-policy warnings and duplicate indexes outside the completed sync-path cleanup.

GitHub:
- PR #56 remains open and unmerged;
- no review threads or submitted reviews are currently reported;
- the current CI workflow file has PR triggers, but the GitHub connector has not returned a workflow run for the current branch commits yet;
- the only current commit status observed is the Vercel build-rate-limit failure, not a code/test conclusion.

## Remaining work — first genuinely incomplete items

1. Crash/replay verification
   - add focused tests for app kill during bootstrap, push replay, pull replay, and timeout-after-commit;
   - run the live fulus_sync_e2e.dart contract test against production.
2. Recovery integration verification
   - prove a real stale cursor receives 410, performs bootstrap, resumes from sync_boundary, and reaches Sync Ready.
3. Retention/compaction
   - the architecture requires a retention/compaction policy; the production database currently has no scheduled pg_cron extension;
   - implement a safe pruning mechanism and verify stale-cursor recovery against retained history before calling scale complete.
4. Full final audits
   - architecture;
   - client flow;
   - server flow;
   - failure/recovery;
   - scale/performance;
   - Sync Health;
   - production database/function/security;
   - final diff;
   - full CI;
   - E2E/integration.
5. APK remains blocked until all audits above pass.

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
