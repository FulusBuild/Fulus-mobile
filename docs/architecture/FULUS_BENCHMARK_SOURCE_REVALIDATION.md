# Fulus Benchmark / Source Revalidation — 2026-10-06

## Status

**Source-level revalidation:** complete against current `main` at `034a03a7f9325aea8f178e8f5773477512697657`.

**Method:** revalidate the existing 20-part deep-code audit and both architecture benchmarks against the current source tree. Review benchmark-relevant files at line/function/class granularity, then cross-check concrete invariants with repository searches for the old implementation patterns. Historical findings are not accepted as current findings without current-source confirmation.

**Important boundary:** source completion is not the same as runtime/production closure. Android process-death, physical restore, UI first-frame behavior, final live multi-device convergence, and the production leaked-password setting remain evidence tasks.

## 1. Changes since the previous implementation-benchmark baseline

Previous implementation-benchmark baseline: `2fe9203ecaccb9509f67f15ff9bf982922a873a3`.

Material changes subsequently revalidated:

- #161 strict money wire contract.
- #162 SQLite restore maintenance fence.
- #163 restore ownership simplification around the maintenance fence.
- #164 legacy queue actor repair removed from generic `SyncEngine`.
- #165 typed sync-operation wire serialization.
- #166 employee identity projection persistence boundary.
- #167 durable sync/change-feed cursor persistence in SQLite.
- #170 migration-chain validity repair.
- #172 state-management boundary fitness test.
- #173 removal of obsolete legacy sale double-money transport.
- #175 production migration-history repair.
- #174 local JWT claims verification in `fulus-api`.

## 2. Line/function/class-level revalidation

### Money

Reviewed `money.dart`, money-bearing domain entities/DTOs, Drift tables and migrations, repositories, sync handlers, canonical reconcilers, strict-money migrations, financial fidelity SQL, and money fitness tests.

Current invariant: `Money` is integer minor units. Persisted SQLite monetary columns are INTEGER. Migration v17 converts historical REAL values at the migration boundary. JSON money is a canonical decimal string with exactly two decimals. The parser rejects JSON numbers and non-canonical strings.

**Result: source invariant closed. Runtime upgrade/convergence evidence remains.**

### Sale / checkout / cash change

Reviewed `CartCubit.addPayment`, draft-cart payment persistence, `DraftCartRepositoryImpl.completeSale`, `SaleDraft`, `SalePayment`, `Sale`, sale repository transaction, cash-drawer calculations, receipts/reports, `fulus_api_create_sale_atomic_v2`, and cash-tender/change tests.

Current invariant: cash tendered is distinct from applied cash; applied cash contributes to amount paid; change is tendered minus applied cash; credit is not collected cash; cloud cash ledger records applied cash; cloud validates payment totals against the authoritative sale total; retry is idempotent.

**Result: source contract closed; live cash-change offline→sync evidence remains.**

### Sync engine

Reviewed `SyncEngine.runOnce`, queue draining/dependency handling, retry classification, conflict parking, actor attribution, queue completion, execution lease interaction, handler registration, and legacy queue actor repair injection.

PR #164 moved entity-specific legacy queue repair out of the generic engine.

**Result: generic sync boundary revalidated.**

### Sync cursor

Reviewed `SyncCursorStore`, `DatabaseSyncCursorStore`, bootstrap wiring, restore cursor initialization, cursor transaction boundaries, replay tests, and legacy SharedPreferences migration.

Production now uses SQLite-backed cursor persistence. SharedPreferences remains only as a migration/legacy test adapter.

**Result: source invariant closed.**

### Restore / maintenance

Reviewed `SyncExecutionLease.acquireMaintenance`, maintenance renewal/ownership checks, protected transactions, `CloudRestoreCoordinator`, restore importer, restore screen cursor handling, and restore/sync tests.

Current source provides a dedicated maintenance fence that waits for active sync, prevents new sync leases, renews ownership, and protects the destructive restore transaction.

**Result: source redesign requirement closed. Physical Android restore/process-death evidence remains.**

### Authentication

Reviewed `fulus-api/index.ts`, JWT extraction and claims verification, membership lookup, device registration, business/location authorization, actor propagation, and auth recovery.

PR #174 changed API identity verification from `auth.getUser()` to `auth.getClaims()`, eliminating the unnecessary Auth user network round-trip while retaining verified JWT identity.

Supabase currently recommends `getClaims()` for JWT verification and notes that `getUser()` performs a network request. 

**Result: source invariant closed; production resilience evidence remains.**

### Employee identity/access

Reviewed employee identity projection persistence, employee cloud-session coordination, employee restore, membership/role projection, authorization guards, employee canonical-pull fencing, and state restoration.

Cloud membership remains authoritative; local employee state is a projection.

**Result: source boundary closed; cross-device employee runtime evidence remains.**

### State management

Reviewed Riverpod usage, Sell cart Cubit boundary, and `test/architecture/state_management_boundary_test.dart`.

The current rule is explicit: Riverpod is primary and flutter_bloc/Cubit is allowed only inside the Sell cart boundary.

**Result: source/fitness boundary closed.**

### Database invariants

Reviewed Drift table definitions, migrations, repository read-before-write patterns, sale/inventory/payment constraints, and the remaining draft-cart/cash-drawer cardinality findings.

Remaining application-level cardinality races are separate hardening candidates where safe DB uniqueness can be added without destructive migration assumptions.

**Result: no new source-critical defect proven.**

### UI/navigation

Reviewed `router.dart`, `app_shell.dart`, primary branch navigation, progressive local hydration, permission-aware routing, More customer/printer/settings back paths, and Instant UI tests.

**Result: source intent is correct; physical Android first-frame/back-navigation evidence remains P18-001.**

### Diagnostics / observability

Reviewed DiagnosticLogger capture, store failure containment, event stream, export/read/maintenance operations, and regression tests.

The Part 19 throwing-store defect is fixed.

**Result: source invariant closed; runtime/production telemetry evidence remains.**

### Security

Reviewed RLS coverage, SECURITY DEFINER functions, function grants, search_path hardening, actor/device/business/location checks, API JWT validation, and staff/restore authorization.

**Result: source security boundary remains strong. Production leaked-password protection remains an external configuration item.**

## 3. Current benchmark scorecard

| Area | Source result | Remaining proof |
|---|---|---|
| Offline-first | Green | Android runtime |
| Local transaction atomicity | Green | Runtime failure injection |
| Durable outbox | Green | Physical process death |
| Sync dependency/retry | Green | Long-running runtime |
| Canonical convergence | Green/yellow | Two-runtime live evidence |
| Money representation | Green/yellow | Upgrade + live convergence |
| Money wire | Green | Full live journey |
| Cash tender/change | Green/yellow | Offline→sync Android journey |
| Restore fencing | Green/yellow | Physical Android restore |
| Employee identity | Green/yellow | Cross-device runtime |
| Location isolation | Green/yellow | A→B pending/in-flight runtime |
| State management | Green | Regression CI |
| UI immediacy | Green/yellow | Physical Android |
| Diagnostics | Green/yellow | Production evidence |
| Security | Green/yellow | Production configuration/advisor |
| Migration chain | Green | Production deployment verification |

## 4. Remaining blockers/evidence gaps

### P17-001
Physical Android process termination followed by WorkManager headless recovery, session/device readiness, push/pull, and queue completion.

### P18-001
Physical Android cold/warm navigation, offline/delayed hydration, branch preservation, and More back-navigation.

### P15 runtime evidence
Physical fresh restore, database reopen, cursor continuation, and post-restore synchronization.

### P16 runtime evidence
Two-runtime local SQLite convergence plus authorized live sale/return workflow.

### P20-001
Production Supabase leaked-password protection must be enabled and the security advisor rerun.

### Financial runtime evidence
The source migration and exact-money contracts are implemented. The remaining requirement is representative previous-version upgrade proof and live end-to-end financial convergence.

## 5. Historical findings superseded by current source

These historical findings are no longer valid descriptions of the current implementation:

- local monetary persistence being SQLite REAL;
- generic SyncEngine owning entity-specific legacy queue repair;
- production sync cursor being SharedPreferences-backed;
- restore lacking a maintenance fence;
- `fulus-api` using `getUser()` for every request;
- cash tender/change lacking a local/cloud distinction.

They remain useful as audit history, but must not be used as current defects.

## 6. Revalidation conclusion

The current source is materially more complete than the 2026-10-05 benchmark baseline.

The major architectural changes introduced since that baseline were checked against their owning invariants rather than accepted merely because their PRs were green.

**Source verdict: strong / conditionally production-ready.**

The remaining work is primarily runtime and production evidence, not another broad source rewrite.

The benchmark must not be declared fully closed until the remaining Android, live multi-device, restore, upgrade, and production-configuration evidence is observed.

## 2026-10-06 — PR #179 benchmark-hardening continuation

This continuation followed **Inventory → Trace → Inspect → Prove → Classify → Fix → Test → Cross-check → CI → Record**.

### Current findings on PR #179

- **P0 build:** the CI failure was an orphaned duplicate source tail after the closing brace of `lib/data/repositories/product_repository_impl.dart`. Removing only that invalid tail restored code generation/static analysis; no intended repository logic was removed.
- **P0 money wire:** `FulusSyncApi.submitOperation()` serializes known `sale.create` operations to the flattened `sale_create` action. Sale payments can carry `tendered_amount`, so the strict request validator must treat that key as monetary. The validator, response normalizers, fitness field list, and migration are now aligned; the live contract test explicitly exercises numeric `tendered_amount` on the flattened submit-operation wire.
- **P0 restore fence:** the SQLite maintenance row is not a physical fence because restore replaces the database file containing that row. The implementation therefore uses the sidecar filesystem `FileLock` as the physical cross-process fence, while retaining the SQLite lease for logical sync/maintenance coordination. The maintenance-row renewal timer is suspended before the live DB is closed; the sidecar lock remains held across the file replacement until the fresh DB is reopened and the fence is released.
- **P1 stock hydration:** active-location stock hydration now participates in the shared execution lease for its whole network/projection path. Each page checks ownership before network I/O, and the stock projection transaction revalidates ownership at the SQLite writer boundary. A regression forces lease loss during network I/O and requires the hydration to abort without applying stale stock.

### CI/evidence state

The repository already proved code generation and static analysis after the initial source fix. The first post-fix CI failure was the obsolete same-process restore-fence test; that test has been replaced with a separate OS-process probe. Final CI status must be rechecked after the latest hardening commits.

Runtime caveat remains unchanged: this source hardening does not claim physical Android process-death/restore evidence or full live multi-device convergence without those observations.


2026-10-06 — PR #179 cardinality/analyzer continuation

- P1 DB cardinality hardening: schema v21 now enforces one draft cart per location and one open cash-drawer shift per location with non-destructive duplicate preflight during upgrade. Sequential and concurrent persistence regressions are present; this supersedes the historical P05-002/P05-003 source findings.
- CI analyzer cleanup: removed the final redundant non-null assertion in the restore-fence regression (`restoredDb!`).
- Remaining gates are evidence/configuration only: Android WorkManager/process-death, physical restore/reopen/upgrade, multi-device runtime convergence, UI runtime evidence, and production Auth leaked-password protection.


## 2026-10-07 — P3 current-main revalidation

P3 was re-applied against the post-PR #183 `main` baseline. The readiness ownership finding remains valid: `SyncService` owns readiness state and cloud-bootstrap coalescing, so the separate `SyncReadinessGate` was redundant.

Current source changes: `SyncService.ensureReady()` is the readiness boundary; `SyncTriggers` retains only the adapter logic needed to invoke that boundary; the duplicate readiness gate and its direct regression test are removed. No cycle, lease, connectivity, restore, or recovery invariant was removed.

**P3 source result: 🟢 for this coordination cluster, CI verified on post-merge main.**


## 2026-10-07 — P2/P3 current-main record

PR #180's P2 findings were revalidated against the current post-PR #184 baseline and carried forward here because the original PR branch had diverged from main.

P2 remains **🟢/🟡 substantially closed**: state-management and database-cardinality boundaries are source-fixed; coordination entropy is a guardrail rather than a proven defect; historical comments are maintainability debt; architecture-fitness coverage remains the principal implementation gap.

P3 readiness simplification is **🟢 source-verified and CI-verified** on current main. The merged change removed the duplicate readiness state-machine class and retained the distinct cycle, connectivity, lease, restore, and recovery coordination boundaries.
