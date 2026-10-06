# Fulus Benchmark Work Handoff and Engineering State

**Repository:** FulusBuild/Fulus-mobile  
**PR:** #179, `fix/benchmark-money-restore-hardening`  
**Base:** `main` at `bce6f3a11e59827e7d0139e03916184d261aeb0a`  
**PR head reported by GitHub:** `683b7f5ef114e19b98691014c2ec87ba90f7aeeb`  
**CI merge commit currently reported in the failing build:** `0e33d3b21317b2570b17f59ca285c39510ca61d7`  
**Status:** PR open, not merged. Do not merge until the active P0s are resolved and CI is green.

This document is a continuation/handoff record for another AI engineer. It records the benchmark yardstick, source-audit conclusions, changes already made, open findings, current CI evidence, and the exact order in which work should continue.

---

## 1. Governing benchmark documents

The benchmark work is governed by:

1. `docs/architecture/FULUS_ARCHITECTURAL_BENCHMARK.md`
2. `docs/architecture/FULUS_IMPLEMENTATION_BENCHMARK.md`

The question is not "does the code look good?" The governing question is:

> If a strong principal engineering team designed Fulus from a blank repository, would they choose these architectural boundaries, invariants, and implementations?

The benchmark deliberately uses external engineering standards as a yardstick, including Google Cloud, AWS, Azure, Google SRE, Android Architecture, OWASP, and CMU SEI.

The benchmark conclusion is **not** that Fulus needs a rewrite. The architecture is fundamentally strong. The work is to harden dangerous boundaries, remove accidental complexity, and prove the distributed/runtime guarantees physically.

---

# 2. Fulus architecture benchmark conclusion

## Strong areas

These are substantially aligned with a principal-level design:

- local-first/offline-first operation
- SQLite/Drift as the immediate local source for UI
- durable outbox
- stable operation identity
- server-side idempotency
- canonical server/change-feed reconciliation
- optimistic concurrency control
- location-scoped authorization
- cloud-authoritative membership and permissions
- transactional financial mutations
- integer minor-unit money internally
- durable sync execution
- diagnostics
- database migrations
- CI and regression testing
- domain entities separated from Flutter/Drift/Supabase concerns
- transactional sale mutation with sale/items/payments/stock/outbox in one local transaction

## Areas that remain weaker

- native restore versus sync fencing
- strict money wire contract at every real request path
- physical Android restore/reopen/process-death proof
- some runtime/distributed guarantees are still inferred from source rather than physically demonstrated
- product location hydration historically created a second synchronization authority
- observability is not yet expressed as full business/user SLOs
- some database invariants could be encoded more directly
- the sync coordination surface has accumulated historical classes
- Money is still fundamentally `typedef Money = int`, which limits type safety
- presentation state management is mixed
- operation dispatch uses operation-type branching rather than a typed command/registry boundary

## Overall benchmark judgment

The architecture is strong enough that a principal team would **refactor and harden rather than rewrite**.

The rough similarity assessment recorded in the implementation benchmark was approximately:

- offline-first: 95%
- local DB: 95%
- repository boundary: 90%
- transactional sales: 95%
- durable outbox: 95%
- idempotent sync: 95%
- canonical reconciliation: 90%
- authentication: 95%
- location isolation: 90%
- sync fencing: 85%
- restore: 70%
- money: 65%
- state management: 70%
- API dispatch: 75%
- raw SQL boundary: 70%
- sync/domain coupling: 75%
- bootstrap/composition: 85%
- documentation/comments: 70%
- overall engineering shape: approximately 82%

These percentages are not a code-quality score. They express how closely the current implementation shape resembles what a strong greenfield principal-team design would likely look like.

---

# 3. Benchmark decision framework

Every finding is classified as:

- **Keep**: design is already appropriate.
- **Strengthen**: architecture is correct but a boundary/proof is incomplete.
- **Simplify**: design works but has unnecessary cognitive surface.
- **Redesign**: current boundary can produce dangerous behavior and needs a materially stronger boundary.
- **Reject**: direction would move Fulus away from the benchmark.

Important: do not turn benchmark work into speculative cleanup. Fix proven boundary failures first.

---

# 4. Cross-cutting invariants

The benchmark established these invariants:

### A. Local continuity
The application must remain useful and immediately responsive from local state without requiring a cloud round trip for ordinary work.

### B. Money magnitude preservation
A money value such as ₦300 must remain ₦300 through local storage, domain calculations, serialization, server persistence, reconciliation, and presentation.

### C. Atomic local mutation
A business mutation and its durable sync operation must be committed atomically.

### D. Durable operation identity
An operation must retain a stable identity across retries, restarts, and network failures.

### E. Canonical convergence
After synchronization, local state must converge to the canonical server state unless a newer local mutation legitimately supersedes an older server result.

### F. Location isolation
Data and mutations must never cross business/location authorization boundaries.

### G. Actor integrity
The server must know which authenticated actor performed an operation.

### H. Server authorization
Client-side permissions are not sufficient. Server-side authorization is authoritative.

### I. Restore safety
Database replacement must not race with active sync or leave the application in a partially restored state.

### J. User-visible immediacy
The UI should reflect local mutations immediately and let synchronization happen invisibly afterward.

---

# 5. Source audit findings

## P0-001: Native/local restore did not originally have a sync maintenance fence

### Source
`lib/data/repositories/backup_repository_impl_native.dart`

The original native restore path closed the database for maintenance but did not first acquire the same sync execution maintenance fence used by the cloud restore path.

### Why this matters

A foreground/background sync process could theoretically still be operating while the live SQLite file was being renamed/replaced.

The cloud restore path was already stronger:

- acquire maintenance lease
- verify ownership
- reject unsafe pending/conflict state
- restore transactionally
- check foreign keys
- release fence

### Work already attempted

PR #179 added:

- `SyncExecutionLease.releaseMaintenanceOn(AppDatabase db)`
- maintenance acquisition to `AppDatabaseLifecycle.closeForMaintenance()`
- maintenance lease retention across database close/reopen
- release through the newly opened database

Relevant files:

- `lib/sync/sync_execution_lease.dart`
- `lib/data/local/database/app_database_lifecycle.dart`
- `lib/data/repositories/backup_repository_impl_native.dart`

### Critical remaining issue

This is **not yet a true cross-process physical restore fence**.

The maintenance lease row itself lives in the SQLite database being replaced.

That means:

1. Process A acquires a lease in SQLite.
2. Process A closes/replaces the database file.
3. The lease row disappears with the old/replaced database.
4. A second process that still has an old SQLite connection can potentially continue operating against the old file.

Therefore the benchmark conclusion remains:

> The native restore fence needs a durable synchronization primitive outside the replaceable SQLite database, or an equivalent OS/process-level exclusion mechanism.

Do not mark this P0 fixed merely because the acquire/release calls exist.

---

# 6. P0-002: Strict money wire contract is not enforced on the real operation path

## Intended contract

Financial values crossing the cloud API boundary should be decimal strings with exactly two decimal places, for example:

- `"300.00"`
- `"0.00"`
- `"-25.50"`

Numeric JSON values such as:

- `300`
- `300.0`
- `300.50`

must not be accepted as monetary wire values.

This is intended to eliminate JavaScript number semantics and prevent minor-unit/major-unit confusion.

## Source

`supabase/functions/fulus-api/index.ts`

PR #179 added recursive money-wire validation around `MONEY_WIRE_KEYS`, with the expected format:

`^-?\\d+\\.\\d{2}$`

and an `INVALID_MONEY_WIRE` contract error for invalid monetary JSON.

## Critical live evidence

The actual production-style E2E test deliberately submitted numeric monetary input through the operation submission path.

Expected:

- rejection
- contract error
- no operation acceptance

Actual:

- HTTP 201
- response status 202
- `accepted: true`
- operation entered the queue

Observed:

`Bad state: Strict money wire rejected neither numeric monetary input nor returned the expected contract error: HTTP 201 {data: {response: {data: {status: received, accepted: true, operation_id: e2e-money-wire-invalid-..., server_operation_id: ..., server_authoritative: true}}, status_code: 202}}`

### Interpretation

This is a real P0, not a flaky test.

The validator exists, but it does not cover the actual `submit_operation` payload path.

The next engineer must trace:

1. `fulus-api` request parsing
2. `submit_operation` dispatch
3. extraction of the nested operation payload
4. where `invalidMoneyField` is called
5. whether the monetary keys are inside a nested `payload`, `data`, or operation-specific object
6. whether validation occurs before queue insertion
7. whether every operation type reaches the same validator
8. whether the response path can still accept numeric monetary data

Do not weaken the E2E assertion. The E2E found a genuine contract hole.

---

# 7. P0-003: Money presentation and arithmetic boundary leaks

Several Money-to-double leaks were found during the benchmark.

## Fixed

### Formatter

The formatter previously accepted:

`formatMoney(num value)`

and performed numeric conversion.

It is now intended to accept:

`formatMoney(Money amount)`

and explicitly call `moneyToMajor()` only at the presentation boundary.

### Refund estimate

`refund_confirm_screen.dart` previously used double-based monetary arithmetic.

It was changed to remain in Money.

### Dashboard/customer/supplier aggregates

Aggregates were changed from double accumulation to Money accumulation.

Example:

`customers.fold<Money>(zeroMoney, ...)`

### Sell payment logic

`CartCubit.addPayment()` previously did a Money → major double → Money round trip.

It now keeps comparison/arithmetic in Money and performs major-unit conversion only once at the external input boundary.

### Remaining benchmark work

The broad money fitness suite should still prove all financial paths, including:

- Products
- Sales
- Sale payments
- Sale item prices
- Sale item cost
- Expenses
- Income
- Returns/refunds
- Customer repayments
- Customer credit
- Supplier balances
- Cash drawer opening
- Cash drawer closing
- Cash differences
- dashboard aggregates
- presentation formatting
- cloud request serialization
- cloud response parsing
- reconciliation

The benchmark requirement is magnitude preservation, not merely absence of obvious `double` declarations.

---

# 8. P1-001: Product location hydration was a second synchronization authority

## Original problem

`bootstrap.dart` called:

`productRepository.syncFromServer()`

on location context change.

The old method:

- fetched the product listing endpoint
- wrote product catalog fields
- wrote stock levels

This meant product state could be written by both:

1. canonical change-feed reconciliation
2. product repository snapshot synchronization

That is dangerous because the second path can bypass canonical ordering/conflict rules.

## Changes already made

The boundary was narrowed to:

`hydrateActiveLocationStockFromServer()`

It now:

- only hydrates active-location stock
- does not overwrite canonical product catalog fields
- only hydrates products already present in canonical local state
- does not create missing canonical products
- does not overwrite pending local stock
- uses a transaction around the stock projection update
- participates in the sync execution lease
- has regression tests

### Important identity fix

Server product ID and local product ID are not guaranteed to be identical.

The mapper was corrected from:

`productLocalId: id`

to an explicit:

`productLocalId: productLocalId`

with the actual local product row ID supplied by the repository.

This prevents foreign-key failures and identity corruption when:

- server ID = `p123`
- local ID = `local-p123`

## Remaining concern

The hydration path is now much safer, but it remains a targeted secondary stock writer.

The benchmark position is:

> A snapshot hydration path is acceptable only as a narrowly scoped read-model hydration, and it must remain serialized with sync execution and must never become a second canonical synchronization authority.

Do not expand this method back into catalog synchronization.

---

# 9. Canonical change-feed application

The canonical synchronization path in `bootstrap.dart` has:

- `prepareChanges`
- `applyPreparedChanges`
- `shouldApplyChange`
- `withApplyTransaction`

`shouldApplyChange` uses:

`SyncQueue.hasPendingMutationForServerEntity(entityType, serverId)`

The canonical apply transaction calls:

`syncExecutionLease.ensureHeldForTransaction()`

This is the correct architectural direction.

The entity coverage includes:

- employee
- sale
- customer
- customer_ledger
- category
- supplier
- location
- return
- expense_category
- cash_drawer_shift
- expense
- income_record
- stock_movement
- product

Do not add arbitrary repository-level guards around every entity. Preserve one canonical conflict/reconciliation authority.

---

# 10. P1-002: Same-runtime maintenance fencing is not fully proven

The lease allows maintenance acquisition when an active sync lease is owned by the same owner.

What remains missing is explicit regression proof for the same-runtime overlap case.

Need a test proving:

1. sync execution is held
2. maintenance request is attempted by the same runtime/owner
3. expected behavior is deterministic
4. no unsafe overlapping transaction is permitted

---

# 11. P1-003: Physical Android restore/reopen/process-death proof

Source review cannot prove the Android runtime behavior.

The benchmark requires eventual physical evidence for:

- database restore
- database reopen
- process death during sync
- process death during restore
- WorkManager restart
- startup session restoration
- outbox durability
- cursor durability
- location switch
- pending mutation survival
- login/reinstall restoration

The user explicitly decided not to turn this into one enormous "deep E2E" project.

Therefore:

> Use targeted production/runtime evidence, not a giant all-system E2E.

---

# 12. P1-004: Android WorkManager/process lifecycle proof

The architecture depends on durable/background sync behavior.

The benchmark identified:

- process death
- background execution
- WorkManager rescheduling
- startup recovery
- lease recovery

as areas requiring runtime evidence.

Do not rewrite the sync architecture merely because these have not yet been physically tested.

---

# 13. P1-005: Money fitness coverage

The money migration and benchmark should be protected by a systematic fitness suite.

Minimum expected invariants:

### Example

`Money(30000 minor units)`

must represent:

`₦300.00`

and must never accidentally become:

`₦30,000.00`

through:

- UI entry
- repository persistence
- sync serialization
- API response
- database reconciliation
- display formatting

Tests should cover all monetary write boundaries, not just Products.

---

# 14. P1-006: DB invariants

Already strong:

- unique draft cart per location
- unique open cash drawer per location

Examples:

`idx_draft_carts_location_id`

and:

`idx_cash_drawer_shifts_open_location`

The benchmark recommendation is selective enforcement of important invariants in the database rather than relying entirely on Dart.

Do not create indexes merely for theoretical purity.

---

# 15. P1-007: Observability/SLOs

Diagnostics are already strong at the engineering level.

The next maturity step is to define business/user SLOs such as:

- local mutation visibility latency
- sync completion latency
- restore completion time
- backup freshness
- failed operation rate
- reconciliation failure rate
- cloud availability from the user's perspective
- stale-data duration

This is not a current PR blocker unless a specific production issue exposes it.

---

# 16. P2 / longer-term architecture improvements

These are benchmark improvements, not reasons to block the current PR unless they expose a current correctness defect.

## P2-001: Replace `typedef Money = int`

A real Money value object would provide stronger compile-time guarantees.

Ideal greenfield properties:

- currency-aware value
- strict minor-unit arithmetic
- explicit conversion
- no accidental numeric mixing
- strict wire serialization
- strict parsing

Do not introduce a large rewrite merely to achieve this.

## P2-002: Currency precision model

The current model effectively assumes two decimal places.

For a global product, explicitly decide support for currencies such as:

- JPY: 0 decimals
- KWD: 3 decimals

This is a product/domain decision, not merely formatting.

## P2-003: Sync coordination simplification

Current classes include:

- `SyncService`
- `SyncTriggers`
- `SyncCycleRunner`
- `SyncEngine`
- `SyncExecutionLease`
- `SyncRestoreReconciliationGate`
- `SyncCoordinator`
- `CloudSessionBootstrapCoordinator`
- `CloudSyncBootstrapCoordinator`
- `CloudSyncRecovery`
- `EmployeeCloudSessionCoordinator`
- `FulusConnectionState`

Most have legitimate responsibilities, but the cognitive surface is high.

Guardrail:

> Do not add another coordinator unless it owns a genuinely distinct invariant.

Do not collapse everything into one giant sync class.

## P2-004: Typed API commands

`FulusSyncApi.submitOperation()` currently dispatches by operation type.

A greenfield design might use typed commands/registry/adapters.

No emergency rewrite is justified.

## P2-005: Raw SQL boundary

Some raw SQL in employee cloud-session coordination is justified at a cross-device restore boundary.

Long-term, move persistence-specific SQL toward the persistence layer if doing so reduces coupling without weakening correctness.

## P2-006: Presentation state management

Fulus currently mixes:

- Riverpod
- local streams
- FutureBuilder
- Cubit
- repository calls
- route lifecycle
- permission projections

This is not automatically bad.

Do not standardize state management blindly.

The greenfield direction is:

UI → local state abstraction → application/feature operation → repository → local DB

with synchronization outside the rendering graph.

---

# 17. Employee/auth architecture

The source review found the employee/auth architecture broadly sound.

Target behavior:

### First join

Invitation → Join Fulus → create Fulus password → restore authorized business → Home

### Later login/reinstall

Email + Fulus password → restore authorized business automatically

Important distinction:

- Fulus password = account authentication
- App Lock/approval PIN = local device security

Cloud-owned employee roster/roles should remain authoritative.

Do not redesign employee authentication based only on historical runtime symptoms. Use targeted runtime evidence when verifying employee sign-in.

---

# 18. Sync architecture principles that must not be violated

Do not:

- move Fulus from local-first to cloud-first
- replace the durable outbox with direct network writes
- remove execution leases
- bypass canonical reconciliation
- create separate synchronization authorities for individual entities
- remove repositories just to reduce file count
- weaken tests to make CI green
- add generic guards everywhere
- collapse the entire sync architecture into one class
- introduce cloud/network concepts into normal UI flows

The intended user experience remains invisible sync, similar to the mental model of messaging apps:

- work locally
- persist immediately
- sync automatically
- retry invisibly
- recover after process death
- show only useful connection state

---

# 19. Current PR #179 purpose

PR #179 was originally created to:

- keep receipt formatting typed to minor-unit Money
- fix refund estimates to remain in Money
- keep customer/supplier/dashboard aggregates in Money
- enforce decimal-string monetary request fields at `fulus-api`
- add regression protection for ₦300 vs ₦30,000 magnitude drift
- begin hardening native restore fencing

The PR description correctly notes that native restore fencing is a separate follow-up because a SQLite-backed lease inside the replaceable database is not a sufficient physical fence.

The PR should not be merged until the actual P0 correctness holes are resolved.

---

# 20. Current CI failure: build_runner syntax failure

The latest CI output supplied to the engineering session is:

`build_runner` fails while parsing:

`lib/data/repositories/product_repository_impl.dart`

At approximately line 336:

- `'if' can't be used as an identifier because it's a keyword.`
- `Expected to find ')'.`
- `A function body must be provided.`
- plus 12 additional parser errors

The same parse failure is reported by:

- riverpod_generator
- freezed
- json_serializable
- drift_dev

This means the generator failures are downstream effects of a Dart syntax/parsing error in `product_repository_impl.dart`.

### Important

Do not chase each generator separately.

Fix the syntax error in the source file first.

The exact current CI command was:

`dart run build_runner build --delete-conflicting-outputs --low-resources-mode`

The installed build_runner also reports:

> These options have been removed and were ignored: --delete-conflicting-outputs, --low-resources-mode

That warning is separate from the source syntax failure.

### Secondary CI script problem

After build_runner failed, the shell also reported:

`textn: command not found`

This is from the failure-commenting shell script, not the Dart source failure.

It should be treated as CI plumbing cleanup after the actual build failure is fixed. Do not mistake it for the root cause.

---

# 21. Current CI failure: strict money E2E failure

A separate live E2E run failed earlier with:

`Bad state: Strict money wire rejected neither numeric monetary input nor returned the expected contract error`

Actual response:

- HTTP 201
- nested status code 202
- `status: received`
- `accepted: true`
- `operation_id: e2e-money-wire-invalid-...`
- `server_operation_id: ...`
- `server_authoritative: true`

This proves the invalid numeric monetary input was accepted by the real `submit_operation` path.

This is a P0 and must be fixed at the API boundary.

---

# 22. Current E2E change-feed work

The change-feed finder in:

`tool/fulus_sync_e2e.dart`

was strengthened because mutation acknowledgement can precede change-feed projection visibility.

The current strategy:

- up to 8 polling attempts
- 1-second delay between attempts
- handles HTTP 410 retention expiration
- resumes from `oldest_sequence - 1` when bootstrap recovery is required
- scans the full retained feed
- no arbitrary 20-page cap
- tracks the latest matching entity sequence
- only fails after retained data has been fully scanned across retries

This was a reliability improvement and should be preserved.

Do not reintroduce a fixed arbitrary page limit simply to make CI faster.

---

# 23. Product hydration tests

`test/repository/product_repository_test.dart` now verifies the narrowed hydration boundary.

Important fixtures:

- products have a local ID distinct from server ID
- active location is seeded
- canonical product rows exist before hydration
- hydration updates stock
- catalog fields are not treated as hydration-owned state
- missing canonical products are not created
- pending local stock is protected
- pagination works

The test fixture pattern is intentionally reusable.

---

# 24. Relevant source files

### Benchmark documents

- `docs/architecture/FULUS_ARCHITECTURAL_BENCHMARK.md`
- `docs/architecture/FULUS_IMPLEMENTATION_BENCHMARK.md`

### Sync execution

- `lib/sync/sync_execution_lease.dart`

### Database lifecycle

- `lib/data/local/database/app_database_lifecycle.dart`

### Native restore

- `lib/data/repositories/backup_repository_impl_native.dart`

### Product repository

- `lib/data/repositories/product_repository_impl.dart`

### Bootstrap/canonical sync wiring

- `lib/app/bootstrap.dart`

### Money model

- `lib/core/money/money.dart`

### Money formatter

- formatter source containing `formatMoney(Money amount)`

### Refund UI

- `lib/features/sell/presentation/screens/refund_confirm_screen.dart`

### Cloud API

- `supabase/functions/fulus-api/index.ts`

### E2E

- `tool/fulus_sync_e2e.dart`

### Product repository tests

- `test/repository/product_repository_test.dart`

---

# 25. Important historical commits

Relevant benchmark/hardening commits include:

- `9c4a92d3a85ef3ff2e85e92d6d8533cd871e390e`
- `dda08cd7859a51e62e521766b07815b0bc28e5a6`
- `3635fc71c359bae0a91a70679e7fe8f6412ead80`
- `0688867b8ae245f313aeb2f97f1e69fb9ab2e749`
- `6764a31798597302d7f4c79294c1862f24992541`
- `d8a60069bb1d74a1c5378c91d0175f092f1d01c9`
- `3952d79664d69c99ac07e82dbf00813bf6a48a72`
- `d1d4802ad2d95276142a7b2237aa6c3dbb91d783`
- `011293c6cbb3468976fca0ec3799dbb355bec9b2`
- `4bfca2769cad8f7b4504df6c7da9b4f0d6c48b8b`
- `1f8afa20c5e9ca42b101bb0dcab5248f81c72d29`
- `ef13c2bd9ec9ad81eda1dd89bad822e124b0cac6`
- `2dd28bfcd1ad1c59ce5d42d2309d11bed0787964`
- `bbdbcec2417e9497e67c189d4c8d86cf442b2d1b`
- `ca169e5e87c1961323099abc41e6f49c07db196f`
- `69247d5c21c3ac2ca74405947fe646fa74614029`

PR #179 has subsequently advanced beyond some of those commits.

---

# 26. Complete priority list

## P0: must resolve before merging current benchmark hardening

### P0-1. Fix strict money wire enforcement
The actual `submit_operation` path accepts numeric monetary input.

Source:

`supabase/functions/fulus-api/index.ts`

Proof:

live E2E returned HTTP 201 / accepted=true for intentionally invalid numeric money.

### P0-2. Implement a real native restore maintenance fence
The current lease is stored in the SQLite database being replaced.

Source:

- `lib/sync/sync_execution_lease.dart`
- `lib/data/local/database/app_database_lifecycle.dart`
- `lib/data/repositories/backup_repository_impl_native.dart`

Need a fence that survives/rejects concurrent activity across database replacement/process boundaries.

### P0-3. Repair current source syntax failure
`lib/data/repositories/product_repository_impl.dart` has a parser error around line 336.

This currently blocks build_runner and therefore CI.

---

## P1: important benchmark hardening after P0

### P1-1. Strengthen product hydration serialization
Keep hydration stock-only and serialized with sync execution.

### P1-2. Prove same-runtime maintenance fencing
Add regression coverage for lease ownership/overlap behavior.

### P1-3. Physical Android restore/reopen proof
Test actual APK/runtime behavior.

### P1-4. WorkManager/process-death proof
Prove durable sync recovery across Android process lifecycle.

### P1-5. Complete money fitness suite
Cover every financial write/read/presentation/cloud boundary.

### P1-6. Selective DB invariant strengthening
Only where the invariant is materially important.

### P1-7. Define business/user SLOs
Turn diagnostics into measurable user-facing reliability targets.

---

## P2: architectural refinement

### P2-1. Real Money value object
Replace `typedef Money = int` eventually.

### P2-2. Explicit currency precision model
Do not assume every global currency is two decimal places.

### P2-3. Reduce sync cognitive surface
Only where multiple classes truly own overlapping responsibilities.

### P2-4. Typed operation command/registry
Potential future API dispatch refinement.

### P2-5. Move raw SQL toward persistence boundaries
Only when it reduces coupling safely.

### P2-6. Consolidate presentation state patterns
Only if it clearly improves consistency without creating a new abstraction burden.

---

# 27. Exact next engineering sequence

Another AI should continue in this order:

## Step 1: Fix the current Dart parser failure

Inspect `lib/data/repositories/product_repository_impl.dart` around line 336 and surrounding function/class boundaries.

Do not make unrelated refactors.

Run:

- formatter
- analyzer
- targeted product repository tests
- build_runner

Only after the file parses should generator failures be reconsidered.

## Step 2: Re-run the relevant CI checks

Confirm:

- build_runner
- flutter analyze
- unit/repository tests

Do not interpret downstream generator errors until source parsing is clean.

## Step 3: Trace the real money operation path

Start at the E2E invalid-money operation.

Trace:

E2E request
→ HTTP route
→ `submit_operation`
→ request parsing
→ operation payload extraction
→ money validation
→ operation-specific dispatch
→ queue insertion
→ response

Find the exact point where numeric money bypasses validation.

## Step 4: Fix validation at the correct boundary

Preferred boundary:

> reject invalid money before the operation can enter the durable operation queue.

Do not merely add validation to one operation handler.

The contract should cover all monetary fields in operation payloads.

## Step 5: Add/retain regression coverage

The regression must prove:

- valid decimal strings are accepted
- numeric monetary values are rejected
- malformed decimal strings are rejected
- negative values with valid formatting are handled correctly
- nested monetary fields are validated
- rejection happens before durable acceptance

## Step 6: Fix the native restore fence correctly

Do not stop at SQLite-backed lease acquisition.

Design a fence that remains valid while the SQLite file is being replaced.

The implementation should account for:

- foreground sync
- background sync
- WorkManager
- multiple runtime instances/processes
- process death
- restore rollback
- reopen

## Step 7: Re-run targeted tests

At minimum:

- money boundary tests
- sync lease tests
- restore tests
- product hydration tests
- E2E money contract
- relevant production evidence jobs

## Step 8: Only then evaluate P1 work

Do not start broad P2 cleanup before P0 is proven.

## Step 9: CI must be genuinely green

Green means the actual PR checks pass, not merely that one local command succeeds.

## Step 10: Final source/diff review

Review:

- line by line
- function by function
- class by class
- changed tests
- changed production code
- benchmark document alignment
- no duplicated synchronization authority
- no money conversion regressions
- no weakened assertions
- no unrelated cleanup

Only after that should merge be considered.

---

# 28. CI interpretation rules for the next AI

When CI fails:

1. Identify the first real source error.
2. Separate root errors from generator cascades.
3. Separate infrastructure/script failures from application failures.
4. Never weaken a test to obtain green CI.
5. Never remove a benchmark regression merely because it exposes a real defect.
6. If a live E2E catches a contract violation, treat that as production evidence.
7. Stay in the loop through the next CI run after each meaningful fix.

The latest failure contains two distinct classes:

### Application/source failure

`product_repository_impl.dart` parser error.

### CI plumbing failure

`textn: command not found`

The first must be fixed first.

---

# 29. What has NOT been established

Do not claim these are proven until runtime evidence exists:

- native restore is safe across multiple Android processes
- WorkManager process-death behavior is fully proven
- employee reinstall/login flow is fully proven
- every money write boundary is protected
- every location-switch edge case converges correctly
- full production backup/restore lifecycle is proven
- global currency precision is supported

Source correctness and runtime proof are different things.

---

# 30. Final state for handoff

Fulus is not in a "rewrite the architecture" state.

It is in a **benchmark hardening and proof** state.

The correct mindset for the next AI is:

> Preserve the architecture that is already right. Fix the dangerous boundary that evidence has exposed. Prove the distributed/runtime guarantee. Avoid speculative redesign.

The immediate blockers are:

1. **Dart syntax error in ProductRepositoryImpl**
2. **Real submit_operation money-wire validation hole**
3. **True cross-process native restore fence**

After those:

4. targeted P1 runtime/proof work
5. final benchmark source/diff review
6. green CI
7. merge

Do not start a giant deep E2E project. The user explicitly decided that was broader than necessary. Use focused evidence for the remaining guarantees.


---

# 2026-10-06 — P1 closure continuation

The following P1 engineering work is now implemented in source/tests:

- **P1-1 Product hydration serialization:** active-location stock hydration remains stock-only, participates in the shared execution lease, checks lease ownership during paging, and revalidates ownership at the SQLite writer boundary.
- **P1-2 Same-runtime maintenance fencing:** the maintenance regression explicitly covers an active sync lease and verifies that maintenance waits, then blocks a new sync lease while maintenance is held.
- **P1-5 Money fitness:** strict wire fields include `tendered_amount`; canonical decimal-string parsing is covered; large integer minor-unit formatting is covered at the JavaScript-safe boundary; both shared money formatters are integer-arithmetic based.
- **P1-6 DB invariants:** schema-level uniqueness protects one draft cart/location and one open cash drawer/location, with non-destructive migration preflight and separate-connection concurrency tests.
- **P1-7 Reliability SLO definition:** `docs/architecture/FULUS_RELIABILITY_SLOS.md` defines measurable local-first, sync, reconciliation, restore, money-precision, and cardinality SLOs plus their evidence boundaries.

The latest CI run exposed analyzer warnings in the new formatter/cardinality changes. Those warnings were corrected rather than suppressed. The next CI run must be green before these source/test closures are considered CI-proven.

**P1-3 and P1-4 remain evidence gates, not unresolved source defects:** physical Android restore/reopen and Android process-death/WorkManager behavior require an actual Android runtime. The repository must not claim those observations without running them.

**Important:** P1 source closure does not mean production SLO achievement. Production/runtime evidence remains separately tracked as required by the benchmark.
