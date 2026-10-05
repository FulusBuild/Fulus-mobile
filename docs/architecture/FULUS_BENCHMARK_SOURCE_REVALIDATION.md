# Fulus Benchmark Source Revalidation

**Date:** 2026-10-05  
**Source baseline:** `main` at `f7b6e97cb398e8eb7591583f287c26ac659456b5`  
**Purpose:** Re-validate the architectural benchmark against the actual current source after benchmark items 1-7 and the subsequent strict money/auth work.

This document supersedes stale status statements in earlier benchmark sections where later source changes have already addressed the finding.

## Verdict

Fulus does **not** need a wholesale architectural rewrite.

The benchmarked architecture is substantially sound. The revalidation found that several earlier benchmark findings have now been fixed in source, while a smaller set of evidence and boundary gaps remains.

### Current classification

- Architecture shape: **GREEN / strong**
- Correctness boundaries: **GREEN with targeted hardening**
- Implementation simplicity: **YELLOW / evolutionary seams remain**
- Runtime proof: **YELLOW / physical Android evidence remains**
- Production-readiness benchmark: **NOT YET CLOSED**

## Area-by-area revalidation

| # | Area | Current source finding | Status | Action |
|---|---|---|---|---|
| 1 | Simplicity / restraint | Core remains one Flutter app, SQLite/Drift, durable sync, Supabase. Benchmark refactors reduced accidental seams without introducing distributed infrastructure. | GREEN/YELLOW | Keep. Reject speculative microservices/Kubernetes. |
| 2 | Offline-first | Local business mutations and durable outbox remain the primary path; UI does not require cloud acknowledgement for normal operation. | GREEN | Physical Android proof remains part of final validation. |
| 3 | Transactional domain operations | Local sale/business effects remain transactionally persisted; cloud financial mutations remain authoritative transactional RPCs. | GREEN | Deep E2E should prove failure atomicity end-to-end. |
| 4 | Durable outbox / delivery | Durable SQLite queue, operation identity, retries, dependencies, actor attribution and server idempotency remain intact. | GREEN | Add outcome/convergence measurements. |
| 5 | Synchronization / convergence | SyncService facade, durable lease, cursor persistence, replay-safe reconciliation, OCC and dependency-aware draining remain. Cursor is now SQLite-backed. | GREEN/YELLOW | Physical process-death, foreground/background and long-running convergence evidence remains. |
| 6 | Source of truth / projection | Local SQLite is immediate on-device source; cloud is business-wide canonical authority; reconciliation bridges them. | GREEN | Keep the authority model explicit. |
| 7 | Identity / authorization | Cloud membership/permissions remain authoritative; local employee state is a projection. Server-side business/location/device/actor checks remain. | GREEN/YELLOW | Authenticated Edge Functions still have inconsistent JWT verification paths; see Auth Resilience below. |
| 8 | Location isolation | Location-scoped mutations, membership checks and change-feed filtering remain enforced. | GREEN/YELLOW | Physical A→B switching with pending/in-flight work still needs proof. |
| 9 | Money representation | Integer minor units remain local. Cloud writes use explicit decimal-string conversion. Restore snapshots now normalize monetary NUMERIC values to decimal strings. The client parser rejects ambiguous JSON numbers. | GREEN/YELLOW | Remove or migrate legacy unused remote paths that still convert Money to double. Expand E2E matrix. |
| 10 | Financial semantics | Sale/payment/credit/refund/cash semantics have targeted fidelity and convergence tests; money magnitude boundary is explicit. | GREEN/YELLOW | Deep E2E must verify identities across local → wire → cloud → canonical → local. |
| 11 | Restore / recovery | A dedicated SQLite maintenance lease now fences destructive restore against active/new sync runtimes. Restore is transactional and validates foreign keys. | GREEN/YELLOW | Physical Android restore/reopen/process-death evidence remains. |
| 12 | Database invariants | Local DB now enforces one draft cart per location and one open cash drawer shift per location with unique/partial indexes. Product SKU/barcode uniqueness is also DB-backed. | GREEN | Migration-chain reproducibility must remain green. |
| 13 | Security | RLS, server authorization, actor/device/location checks, grants hardening and adversarial authorization tests remain. | GREEN/YELLOW | Continue production authorization matrix and auth resilience validation. |
| 14 | Observability | Diagnostic events, breadcrumbs, error capture, remote upload and sync diagnostics exist. | YELLOW | Add product/business outcome metrics such as sale success, convergence time, queue age, restore success and recovery time. |
| 15 | Performance / instant UX | Local-first and progressive hydration architecture supports instant UI; route behavior has targeted source/unit coverage. | YELLOW | Real Android route latency and cold/warm visual behavior remain unproven. |
| 16 | Change management / migrations | Ordered Drift migrations and Supabase migrations exist, including explicit financial and sync-state migrations. | YELLOW | Migration-chain workflow currently exposed a syntax defect in `20261005093000_optimize_money_wire_normalizer.sql`; PR #170 fixes it. Do not close this area until the rebuild-from-zero workflow is green. |
| 17 | Testing / architecture fitness | Fulus has unusually strong targeted tests for sync, money, restore, concurrency, authorization and convergence. | GREEN/YELLOW | Deep E2E suite is the next major evidence layer, not a replacement for targeted tests. |
| 18 | Scalability | Async sync, batching, indexes and server transactions provide a sensible growth path without premature service decomposition. | GREEN/YELLOW | Measure real workload limits before adding infrastructure. |
| 19 | Cost efficiency | Local-first reduces unnecessary network dependence and sync can batch/incrementally reconcile. | GREEN/YELLOW | No workload-based cost model yet; measure before optimization. |
| 20 | Sustainability | Bounded local/network work is directionally efficient. | GREEN/YELLOW | No additional architecture justified until material impact is demonstrated. |

## Benchmark implementation items revalidated

### Item 1 — Money wire boundary

The original corruption was a real architectural boundary defect, not a Sell-screen defect.

Current source now has:

- integer minor-unit local money;
- explicit `moneyToWire()` on cloud writes;
- strict decimal-string parsing on cloud reads;
- server-side restore normalization;
- money wire fitness tests.

**Decision:** KEEP the architecture. STRENGTHEN proof and remove remaining legacy double-based remote paths.

### Item 2 — Restore maintenance fence

The earlier benchmark called restore fencing a blocker. That status is now stale.

The current source has a dedicated `cloud_sync_maintenance` SQLite lease. It waits for active sync, blocks new sync acquisition, renews while restore runs, verifies ownership inside the restore transaction, and releases after completion.

Targeted tests explicitly prove that the maintenance fence waits for sync and blocks new sync, and that restore can operate without redundantly acquiring the ordinary sync lease.

**Decision:** GREEN architecturally. Runtime proof remains.

### Item 3 — Generic SyncEngine/domain coupling

The legacy actor repair has been moved out of `SyncEngine` into `LegacyQueueActorRepair`.

**Decision:** GREEN. The generic sync runtime no longer needs to know the schema of sale/cash-drawer/return/customer-ledger tables for that repair.

### Item 4 — Typed sync operation serialization

The central transport now delegates known operation wire shapes through `FulusSyncOperationSerializer` and a closed operation type model while preserving unknown-operation compatibility.

**Decision:** GREEN. Avoid adding one class per operation without a real invariant.

### Item 5 — Employee identity projection

Employee cloud-session orchestration is separated from local identity/session persistence through `LocalEmployeeIdentityStore`.

The store owns transactional local user/employee/permission/session projection and stable identity matching.

**Decision:** GREEN/YELLOW. The persistence boundary is correct. Direct SQL is now concentrated inside the persistence store rather than the cloud-session coordinator. No further abstraction should be added unless it removes real coupling.

### Item 6 — Durable sync cursor

The previous benchmark statement that the cursor lives in SharedPreferences is stale.

Production wiring now uses `DatabaseSyncCursorStore` and the `SyncCursors` SQLite table. SharedPreferences remains only as a legacy migration source/test adapter.

**Decision:** GREEN. The acknowledgement boundary now lives with local business/outbox persistence.

### Item 7 — State management

Riverpod remains the primary application state model. Sell CartCubit is the single deliberate exception.

Current source search shows `flutter_bloc` usage confined to Sell.

**Decision:** GREEN/YELLOW. The boundary is correct, but the benchmark guardrail is currently primarily documented rather than mechanically enforced. Add an architecture fitness test/CI guard so new Cubit/BLoC usage outside Sell fails automatically.

## Newly discovered issues from source revalidation

### A. Supabase migration-chain syntax defect

The zero-to-current migration rebuild currently fails in `20261005093000_optimize_money_wire_normalizer.sql` because its PL/pgSQL `FOREACH` syntax uses `IN ARRAY[` instead of `IN ARRAY ARRAY[`.

PR #170 corrects this without changing runtime behavior.

This is a benchmark evidence blocker because a production architecture must remain reproducibly rebuildable from its migration history.

### B. Legacy remote money path

`lib/data/remote/endpoints/sales_api.dart` still contains an `updateSale()` path that converts `Money` through `moneyToMajor()` before an HTTP PATCH.

Current source tracing shows the queued production sale-write path uses `FulusSyncApi` and `SaleSyncHandler`; the legacy `SalesApi.updateSale()` method has no current production caller.

This should therefore be treated as **legacy/dead-path cleanup**, not evidence that the active sale path still violates the money contract.

The preferred action is to remove the dead method/transport surface or migrate it to the strict wire contract before declaring the money boundary permanently closed.

### C. Auth verification resilience

The benchmark E2E exposed a valid/unexpired JWT being converted into a 401 because `fulus-api` called `auth.getUser()`, creating an Auth network dependency on every request.

PR #169 changes `fulus-api` to local JWT claims verification.

Source revalidation found other authenticated Edge Functions still using `getUser()`. They should be reviewed individually: functions that only need JWT identity can avoid the Auth hot-path dependency, while functions that genuinely require the freshest Auth user record may still have a reason to use `getUser()`.

This is a reliability-boundary review, not a blanket replace-everything refactor.

### D. Product-level observability is still incomplete

Fulus has diagnostic infrastructure, but it does not yet have a mature set of product-level reliability measurements.

The next benchmark evidence layer should measure outcomes such as:

- successful sale completion;
- local commit latency;
- sync convergence time;
- oldest pending outbox age;
- restore success/failure and duration;
- recovery after process death;
- authorization failure rate;
- user-visible route latency.

### E. Physical runtime proof remains the largest evidence gap

Source/unit tests cannot prove:

- Android force-stop → WorkManager recovery;
- foreground/background sync contention on real devices;
- physical location switching with pending work;
- fresh-install cloud restore/reopen;
- process death during restore;
- signed release upgrade;
- cold/warm route latency and first-frame behavior.

These are not reasons to redesign the architecture. They are reasons to prove it.

## Revalidation conclusion

The benchmark's original architectural conclusion remains correct but its status must be updated:

> Fulus is not architecturally wrong. Most of the major boundaries now look like deliberate engineering decisions rather than accidental complexity.

The remaining work is primarily:

1. close the migration-chain defect;
2. finish the benchmark source-document revalidation;
3. mechanically enforce the state-management boundary;
4. remove/migrate the dead legacy money path;
5. review authenticated Edge Functions for unnecessary Auth network dependencies;
6. establish product-level reliability measurements;
7. then build the deep E2E suite for physical/system-level proof.

Only after those steps should the benchmark be considered closed and the project move into the full deep-E2E production-validation phase.
