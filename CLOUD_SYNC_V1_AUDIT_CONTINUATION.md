# Fulus Mobile — Cloud Sync V1 Audit Continuation

Continue the exhaustive Cloud Sync V1 production-readiness audit for `FulusBuild/Fulus-mobile`, branch `main`.

Do not restart the audit. Do not merely write a report. Work iteratively:

**inspect → prove → fix → regression/E2E test → commit → CI → inspect CI → continue.**

Do not stop at the first green CI run. Do not build an APK unless explicitly requested.

## Immediate starting point

Latest fix commit:

`837255d6a25f1fae694bf52c133d15edd5373e60`

The mutation-matrix E2E previously failed at `expense.update` because production `expenses` has no `updated_at` column. Verified production columns are:

`id, business_id, location_id, amount, category, description, operation_id, expense_date, created_by, device_id, payment_method`.

The bad `updated_at=now()` assignment was removed from:

`supabase/migrations/202609211800_phase_3_optimistic_concurrency.sql`

**First task:** find the latest CI run for the fix commit, monitor it to completion, fix every failure, and verify the corrected `fulus_api_update_expense` function is actually deployed in Supabase. Never assume repository HEAD equals production.

## Already hardened areas

Do not redo these blindly, but verify current implementation where relevant:

- local-first SQLite → durable outbox → API → authoritative Supabase mutation → `sync_changes` → cursor → canonical reconciliation
- product initial stock/location atomic creation
- sync readiness/reconnect and cursor-too-old recovery
- native/web backup separation
- Quick Sale cloud sync
- income contract normalization
- stock sale/return change-feed emission and timestamps
- restore FK ordering and queue/conflict clearing
- expense categories
- action idempotency and concurrency locks
- SyncQueue race hardening
- recovery failure propagation
- retry semantics
- user-facing sync error sanitization
- rejected sale/return/customer-repayment reconciliation
- financial rejection handling
- location idempotency/replay
- live mutation matrix
- cumulative return quantity enforcement
- active-device scope hardening
- finance/payment/inventory RPC hardening
- cash drawer atomicity
- canonical aggregate sync model
- paid-at-creation sale/payment/cash atomicity
- cursor ordering/persistence hardening
- outbox process-death model test
- blocked/conflicted outbox supersession
- category/supplier lifecycle hardening
- authoritative restore and business-switching safety

Important commits include:

`0b3140da8d5af945912671b006b834353ddb5f34`
`b879d97d7bd7f232f095710ea0b1225ab6a7fbf3`
`7d1626f0ac957601319f7866f81efd19ad1eac19`
`dae22dca6fddc14a0a7208120667c7841396980e`
`821b15231e40636e041bd4ee778f5d83cec348e7`
`f5d15585834b3208aab3c5773b22aafbce924fbd`
`666adc776f6abc25fe15936f2de6eb52b9c4e580`
`ce9339c14b37f9b091458beb8daaa7fe6bfeb1ce`
`55cab545abda7ea4cafeca45eaf2b440537b3699`
`0d86dfce2916715bb461ff21703363a930c6cc56`
`5c139c4df17c337c7a64da946ce22ccf0059cd96`
`a3abb5b3933085a9cb648a00433cf8c6e3ea2846`
`8aac2446997786e65f96a2dbee27e4150df15aa3`
`837255d6a25f1fae694bf52c133d15edd5373e60`

## Remaining audit priorities

### 1. Full lifecycle audit

For every sync entity verify:

create, update, delete/archive, create→update before sync, create→delete before sync, repeated updates, blocked→newer mutation, conflict→newer mutation, replay, rejection, canonical reconciliation, and change-feed emission.

Entities:

`category, customer, customer_ledger, expense, expense_category, income_record, location, product, return, sale, stock_movement, supplier, cash_drawer_shift`.

### 2. Dependency ordering

Inspect actual:

- `lib/sync/sync_queue.dart`
- `lib/sync/sync_engine.dart`

Verify priority constants, dependency normalization, prerequisite server IDs, retry classification, starvation/deadlock, child-before-parent behavior, and create/update/delete coalescing.

Search all call sites of:

- `normalizeDependencyPriorities`
- `seedExistingBusinessData`

### 3. Process death

The current process-death test is modeled/unit-level. Determine whether true device-level kill/restart evidence is required.

Target proof:

local mutation → durable queue → server commit → process killed before queue deletion → restart → replay → idempotency prevents duplicate → queue converges.

### 4. Multi-device concurrency

Prove stale update rejection using base cursor, durable conflict creation, preservation of local state, safe canonical pull, and explicit resolution.

### 5. Offline/reconnect

Prove offline mutation persistence, app restart persistence, reconnect sync, exactly-once server effect, and replay safety when network dies after server commit.

### 6. Business switching

Prove A→B authoritative recovery, no cross-business mixing, correct cursor, post-recovery delta pull, Sync Ready only after success, and safe rollback if B recovery fails.

### 7. Security/RPC audit

For every mutation RPC inspect production:

- `pg_get_functiondef`
- `pg_get_function_identity_arguments`
- `proacl`

Verify no unsafe public execute, no dangerous legacy overload, SECURITY DEFINER, controlled `search_path`, membership/permission, active device scope, business scope, idempotency, request hash, operation type, and optimistic concurrency where required.

Search especially for `ON CONFLICT DO NOTHING` followed by an unlocked idempotency read.

### 8. Change-feed completeness

For every mutation verify authoritative mutation → exactly the correct `sync_changes` event.

Check entity type, entity ID, operation, payload, timestamps, business ID, sequence, and delete convergence.

### 9. Cursor/recovery adversarial tests

Test duplicate sequence, reordered sequence, global sequence gaps, empty page + `hasMore`, already-acknowledged page + `hasMore`, cursor ahead of response, cursor persistence failure, cursor-too-old recovery, post-recovery delta failure, and recovery process death.

### 10. Production integrity

Recheck negative stock, duplicate stock levels, impossible inventory movements, sale/payment mismatches, cash ledger mismatches, credit ledger mismatches, over-returns, orphaned sale items/payments/return items, invalid business/device relationships, stale devices, malformed sync changes, duplicate idempotency keys, unresolved conflicts, attention-needed records, and permanently stuck queue rows.

Do not delete production data merely to clean test artifacts.

### 11. Security observations

Previously observed:

- `diagnostic_events` has RLS but no policies; explicitly verify whether server-only access is intentional and secure.
- Supabase Auth leaked-password protection is disabled; classify as production security hardening.
- RLS performance advisories exist; do not blindly remove policies or indexes.

## Evidence standard

🟢 Proven = implementation + meaningful test/production evidence + CI.

🟡 Partial = implemented but missing an important proof layer.

🔴 Unknown = not verified or contradictory evidence.

Never say “probably safe.”

## Required engineering loop

For every defect:

inspect → reproduce/prove → establish authoritative contract → implement minimal durable fix → add regression/E2E coverage → commit → CI → inspect CI → production verification where possible → continue.

## Final objective

Make Cloud Sync V1 genuinely production-durable. Leave behind implementation, tests, CI evidence and production verification—not merely an audit report.


## 2026-09-25 concurrency continuation

### Proven and fixed in this continuation

- Durable local-business reset now requires successful acquisition of the shared SQLite sync lease. A failed acquisition no longer permits destructive reset. Regression coverage proves reset is refused while another runtime holds the lease.
- Cloud restore now uses the shared sync execution lease and starts its destructive import transaction with the lease ownership fence. Production wiring shares the same lease with the interactive restore path.
- Rejected-operation canonical recovery is fenced against a newer local mutation for the same entity. The check occurs inside the protected SQLite transaction after the canonical fetch, so an in-flight rejected operation cannot overwrite a newer queued local mutation.
- The guard covers product recovery from sale rejection, expense recovery, customer repayment recovery, return product/customer recovery, and cash-drawer recovery.
- Same-timestamp queued mutations are treated conservatively as newer for recovery fencing because queue timestamps are not a durable total-order identifier.
- Operation identity sweep confirms production client sync handlers pass the durable queue item ID as the server operation ID. Server migrations use business/device-scoped idempotency records and row locking for the audited command surface.
- CI verified green after the final concurrency changes: workflow run 36095959193 completed successfully, including static analysis, Flutter tests, live sync contract tests, and multi-device convergence tests.

### Final verification boundary

The concurrency audit's durable-state mutation sweep found no additional unprotected production path that can delete/overwrite sync queue state or cloud-owned business state outside the established lease/transaction boundaries. Ordinary local queue insertion remains intentionally lease-free because user mutations must be allowed to create newer durable work while a sync runtime is active; the stale-recovery fence explicitly preserves such newer work.

The established evidence standard remains: implementation plus regression/contract evidence plus green CI. No claim of exactly-once local execution is made; correctness relies on durable queue identity, server idempotency, canonical reconciliation, and at-least-once replay safety.
