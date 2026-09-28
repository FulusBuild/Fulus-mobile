# Fulus Full Production Readiness Audit

**Audit branch:** `audit/full-production-readiness`  
**Baseline:** `main` after PR #95 merge (`d0e8030877e91e6c2e06fed90f2e3e05772a0588`)  
**Date:** 2026-09-28  
**Scope:** Production Readiness, Sync & Data Integrity, UI/UX Interaction Reliability, Performance Engineering, Architecture

## Audit status

The broad pass is complete enough to establish the initial ledger. This is **not** a production-readiness sign-off.

### Evidence states

- **Proven:** supported by current source plus targeted automated/live evidence.
- **Partially proven:** source/tests exist, but a required runtime/production condition is not yet verified.
- **Finding:** concrete code/config behavior violates or weakens an intended invariant.
- **Opportunity:** measurable/observed optimization candidate without a correctness failure.
- **Deferred:** evidence is insufficient to justify a change.

## Prioritized ledger

| ID | Track | Severity | Status | Evidence | Root cause / affected area | Invariant | Proposed fix / verification |
|---|---|---|---|---|---|---|---|
| PR-001 | Production / Architecture | **Blocker** | **Closed by PR #94; physical verification pending** | `AppDatabaseLifecycle` explicitly documents that `reopenAfterMaintenance()` creates a fresh DB while existing repositories retain references to the old instance. Backup UI calls `restoreBackup()` and immediately remains in the running app. No restart gate is enforced. | Local file restore / DI lifetime. Existing repositories, sync handlers and services capture the original `AppDatabase`. | After a local DB restore, every database consumer must use the restored database before business use resumes. | Fix restore lifecycle. Preferred first safe closure: make restore a restart-required boundary and prevent normal business use until restart, or implement a proven swappable DB indirection across the complete DI graph. Add regression test and physical restore/reopen verification. |
| SYNC-001 | Sync & Data Integrity / Observability | **High** | **Closed by PR #95; runtime verification pending** | PR #95 changed `SyncTriggers` to capture durable outbound work before the drain and changed `SyncStatusNotifier.recordPushSuccess()` to require that evidence plus an empty queue afterward. CI passed analyzer, full Flutter tests, live sync contract and multi-device convergence before merge. | Push-success accounting previously inferred success from post-run queue emptiness alone. | “Last successful cloud sync/backup” must represent an actual successful outbound reconciliation, not a timer/resume/login/empty-queue check. | Code and regression tests are merged. Remaining verification: observe the timestamp through login/resume/no-op triggers and a real sale on Android; it must remain unchanged for no-op cycles and advance only after successful outbound work drains. |
| SEC-001 | Production / Security | **High** | **Open, production configuration** | Live Supabase security advisor on production project `bejcuvoxemwomcatgyxz` reports `auth_leaked_password_protection` at WARN: leaked-password protection is disabled. A direct production SQL check also confirmed privileged `SECURITY DEFINER` functions are not executable by `anon` or `authenticated`; no new public execution exposure was found in this pass. | Production Auth configuration. | Compromised passwords should be rejected when the production Auth plan/configuration supports the control. | Verify whether the current Auth plan exposes the control. If available, enable it and rerun the security advisor. If unavailable, retain this as an explicit release/security limitation. |
| LIFE-001 | Production / Lifecycle | High | Partially proven | WorkManager callback, durable SQLite lease, process-death replay tests and startup recovery code exist. README explicitly says physical Android validation is still a release gate. | Android OS lifecycle is not fully represented by Dart unit tests. | After process termination/background suspension, queued local work must remain durable and later reconcile without duplicate financial effects. | Physical Android test: force-stop/kill, offline sale, reopen, network restore, WorkManager wake, verify one remote effect and local convergence. |
| DATA-001 | Sync & Data Integrity | High | Partially proven | Targeted tests exist for outbox ordering, process death, OCC, canonical reconciliation, returns, payments and multi-device convergence tooling. Production migration history is current through `20260928050000`. | Remaining risk is runtime breadth rather than an identified current defect. | Sale/payment/return/stock/customer-credit state converges without duplicate or lost financial effects across retries/devices. | Re-run live contract and multi-device convergence after every sync-affecting fix; add missing adversarial cases only where evidence shows a gap. |
| LOC-001 | Production / Sync / UI | Medium | Partially proven | `activeLocationIdProvider` is the single authoritative resolver; Sell/Stock still await it for data-bearing work. PR #92 prewarms it during bootstrap. | Location resolution is local but remains an async prerequisite for location-scoped bodies. | Location A→B switching must not leak in-flight A mutations into B, and primary workspaces should render their safe structure without unsafe location bypasses. | Physical cold/warm A→B verification, including pending A outbox + in-flight sync. Do not bypass resolver without a proven safe cached boundary. |
| UI-001 | UI/UX Interaction Reliability | Medium | Partially proven | Instant UI contract/audit and PR #89–#91 address primary navigation, route transition flash, hydration, and split-payment flash. Secondary routes remain mixed FutureBuilder/local hydration. | Some screens still use asynchronous local data gates by design. | Primary workspace navigation paints immediately; secondary routes preserve useful structure while local data hydrates. | Finish route-by-route runtime verification. Change only proven blocking gates. |
| PERF-001 | Performance Engineering | Medium | Opportunity / Mostly closed for current findings | PR #93 removed Money balance feed materialization. Production advisor reports unused indexes and multiple permissive RLS policies. Current production dataset is small, so unused-index findings are not evidence of a user-visible bottleneck. | Historical index accumulation and RLS policy structure. | Optimize only measured/proven bottlenecks and preserve query semantics. | Defer unused-index cleanup until workload/query evidence exists. Review multiple permissive policies when performance data justifies it. |
| ARCH-001 | Architecture | Medium | Open via PR-001 | DI creates repositories/handlers with direct `AppDatabase` references. Lifecycle separately mutates a captured database variable. | Database lifetime is not represented as a stable application-level abstraction. | There must be one authoritative live DB instance for all consumers during a running process. | Close through PR-001; avoid broad DI rewrite unless the restart-boundary approach proves insufficient. |
| ARCH-002 | Architecture / State Ownership | Low | Deferred | Sync UI combines queue-derived `SyncStatusNotifier` with `FulusConnectionState` readiness/network/session state. The separation is intentional and currently documented. | Two state models describe different dimensions but are easy to confuse. | Queue health, cloud readiness, session validity, and network state must remain distinct and never imply each other incorrectly. | Add invariant tests/documentation only if a concrete contradiction is found. |
| PROD-001 | Production Release | Medium | Partially proven | Release APK build is guarded by signing secrets, production application ID and HTTPS API URL, but release artifact creation is manual `workflow_dispatch`. | Release orchestration is not automatic. | A production release must be reproducible, signed, configured for production, and gated by the required CI/live checks. | Keep manual release if intentional, but verify the actual release workflow on a signed build before launch. |
| PROD-002 | Supabase Production | Medium | Proven configuration, runtime parity continuously gated | Production project is active/healthy; migration history matches repository through `20260928050000`; seven Edge Functions are active with JWT verification; production deployment workflow verifies migration history/schema and runs live sync + multi-device tests. | No current concrete defect found. | Production DB/functions must correspond to reviewed main SHA and pass post-deploy live contracts. | Continue as a release gate; do not treat static source review as replacement for post-deploy evidence. |
| OBS-001 | Observability | Medium | Partially proven | Diagnostic store, fallback store, sync failure capture, remote diagnostics and production function exist. | Physical failure/diagnostic delivery paths are not yet exercised comprehensively. | Important sync/auth/database failures must remain diagnosable without compromising local operation. | Runtime-check diagnostic persistence, upload retry, retention, and behavior when cloud is unavailable. |
| MIG-001 | Database Migration | Medium | Proven chain, runtime upgrade coverage still required | CI validates unique migration versions/core table creation. Production verifies exact history and `supabase db diff --linked` against repository. Mobile DB has versioned migrations through schema 14. | Two independent migration systems require separate upgrade evidence. | Existing installs upgrade without business-data loss; production schema equals repository migration result. | Add/retain physical/fixture upgrade tests for representative old mobile DB versions; production migration workflow remains mandatory. |

## Broad pass: already strongly evidenced

### Sync/data integrity
- Durable outbox exists with retry state, dependency priorities and deduplication.
- Cross-runtime SQLite sync lease exists and is tested.
- Canonical pull/application is separated from the local write transaction after the SQLite-locking finding.
- OCC uses `baseCursor` / server change-feed sequence and catalog serialization.
- Return/sale/payment paths have dedicated handlers and regression tests.
- Process-death replay and multi-device convergence tooling exist.
- Auth refresh is single-flight and preserves refresh credentials across transient transport failures.
- Production migrations include idempotency scope, actor binding, OCC serialization, location authorization, return hardening and financial fidelity changes.

### UI/interaction
- Primary navigation uses `StatefulShellRoute.indexedStack` and immediate primary pages.
- Fulus local-first first-frame contract is explicitly documented.
- PR #89–#93 addressed concrete first-frame, hydration, navigation, split-payment and Money balance findings.
- Vercel is not treated as runtime evidence.

### Production cloud
- Production Supabase project is active/healthy.
- Production migration history is current and repository-aligned.
- Edge Functions are active and JWT verification is enabled.
- Production deployment workflow gates on exact mobile CI, migration/schema verification, post-deploy sync E2E and multi-device convergence.

## Not yet proven by source alone

1. Physical Android process death + WorkManager recovery.
2. Long-running sync under sustained connectivity and repeated foreground/background contention.
3. Physical A→B location switching while A has pending/in-flight sync.
4. Full local backup restore followed by continued application use without restart.
5. Release-signed APK install/upgrade and database migration on representative existing data.
6. Runtime diagnostic behavior during SQLite contention, auth expiry, offline periods and function failures.
7. Route-by-route cold/warm interaction latency on a representative Android device.

## Current audit update — 2026-09-28

- **SYNC-001 is closed at code level** after PR #95 merge; Android runtime timestamp verification remains outstanding.
- **SEC-001 remains open**: production Auth leaked-password protection is disabled according to the live Supabase security advisor. No anonymous/authenticated execution of the inspected production `SECURITY DEFINER` functions was found.
- **ARCH-002 remains deferred**: the sync screen intentionally combines queue state with explicit cloud readiness, but source review did not establish a false-success condition after PR #95. Keep the two dimensions distinct in future UI changes.
- **PERF-001 remains deferred**: production currently reports 44 unused indexes and 30 multiple-permissive-policy findings; these are not treated as correctness or user-visible performance defects without workload evidence.

## Explicitly deferred

- Blanket FutureBuilder rewrite.
- Speculative financial projections/caching.
- Unused-index deletion based only on the current production advisor.
- RLS policy consolidation without workload evidence.
- Broad DI/database architecture rewrite before closing the concrete restore lifecycle defect.
- Vercel as visual/runtime proof.

## Working rule

No finding is marked closed from analyzer success alone. A code fix requires targeted regression coverage, cross-checking against the affected invariants, green CI, and production/runtime verification where listed above.
