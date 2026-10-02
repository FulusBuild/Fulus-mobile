# Fulus Deep Code Audit — Master Plan

**Status:** Active  
**Audit model:** 20 parts × 4 inspection passes  
**Goal:** line-by-line, function-by-function, class-by-class verification with evidence-backed fixes and verification.

## 1. Purpose

This is the master plan for a deep Fulus code audit. It is deeper than a normal architecture or production-readiness review.

Every part must inspect:

1. files
2. classes/interfaces
3. functions/methods
4. lines/branches
5. dependency/call chains
6. database/network boundaries
7. concurrency/lifecycle behavior
8. tests and runtime evidence

The goal is not to produce a list of possible problems. The goal is to establish evidence-backed correctness.

## 2. Non-negotiable rules

**Inventory → Trace → Inspect → Prove → Classify → Fix → Test → Cross-check → CI → Record**

- Do not guess when source/evidence can be inspected.
- Do not declare a finding without a concrete code path.
- Do not weaken tests to make CI green.
- Do not delete a failing test because the implementation disagrees with it.
- Do not make speculative rewrites.
- Prefer the smallest safe fix that restores the intended invariant.
- Cross-part findings must be linked rather than duplicated.
- Trace local operations into cloud/sync consequences where applicable.
- Trace cloud operations back into local projection/convergence where applicable.
- Financial, authorization, tenant isolation, and concurrency findings require strong evidence.
- Green CI does not replace device/runtime/production evidence.
- Never merge while required CI is red or unknown.
- After every fix, inspect adjacent code for the same defect class.

## 3. Evidence states

| State | Meaning |
|---|---|
| **Proven** | Source plus sufficient targeted evidence supports the invariant. |
| **Partially proven** | Source/tests exist but required runtime/production/device evidence is missing. |
| **Finding** | Concrete behavior violates or weakens an intended invariant. |
| **Opportunity** | Improvement candidate without demonstrated correctness failure. |
| **Deferred** | Evidence is insufficient to justify a change. |
| **Closed** | Finding fixed and required verification completed. |

Never use vague states such as “looks good” or “probably safe.”

## 4. Severity

| Severity | Meaning |
|---|---|
| **Blocker** | Data loss/corruption, unauthorized access, unrecoverable production failure, or critical workflow blocked. |
| **Critical** | Serious correctness/security/financial failure with a credible production path. |
| **High** | Important correctness, reliability, authorization, sync, lifecycle, or UX failure. |
| **Medium** | Concrete bounded weakness or important missing verification. |
| **Low** | Minor correctness, maintainability, consistency, or robustness issue. |
| **Informational** | Observation/documentation/architecture note without an immediate defect. |

# 5. The 20 audit parts

## Part 01 — App Bootstrap & Lifecycle

**Scope:** `main`, bootstrap, DI, initialization, shutdown, disposal, restart, process lifecycle, database lifecycle, first-frame prerequisites.

**Deep checks:** initialization ordering/races, duplicate initialization, stale captured dependencies, disposal, startup timeouts, background/foreground, cold/warm start, process death.

**Invariant:** Fulus reaches a valid usable state deterministically without stale resources or hidden lifecycle dependencies.

## Part 02 — Authentication & Sessions

**Scope:** sign-up, sign-in, sign-out, session restore, token refresh, expiry/revocation, password handling, email confirmation, employee login, persistence.

**Deep checks:** auth transitions, refresh single-flight, fresh-install login, process-death recovery, identity projection, error mapping, credential leakage.

**Invariant:** valid users authenticate and recover sessions reliably without inconsistent local/cloud identity state.

## Part 03 — Employee, Membership & Access Control

**Scope:** employees, invitations, memberships, roles, permissions, active employee, employee switching/login, permission projection.

**Deep checks:** invitation source of truth, identity mapping, role/permission resolution, unauthorized UI and mutations, stale permissions, revocation, cross-business/location access.

**Invariant:** authoritative membership/role access is enforced consistently by UI, local state, repositories, APIs, and database policies.

## Part 04 — Business & Location Isolation

**Scope:** business IDs, location IDs, memberships, active location, switching, location-scoped queries/mutations.

**Deep checks:** every query/mutation scope, caches, A→B switching, in-flight A operations, pending A outbox work, UI projections.

**Invariant:** business/location data and mutations never leak across scopes.

## Part 05 — Local Database & Persistence

**Scope:** Drift schema, tables, DAOs, queries, indexes, constraints, transactions, migrations, DB lifecycle.

**Deep checks:** every table/column, nullability/defaults, FKs, uniqueness, indexes, predicates, transaction boundaries, migration/upgrade/partial-failure behavior.

**Invariant:** local persistence preserves business invariants across normal operation, interruption, restart, and migration.

## Part 06 — Repository Layer

**Scope:** all repositories, interfaces, implementations, and DAOs they invoke.

**Deep checks per method:** inputs, outputs, transactions, scope, errors, side effects, projections, outbox behavior, authorization assumptions, concurrency.

**Invariant:** repositories provide correct domain behavior without silently dropping errors or creating inconsistent state.

## Part 07 — Domain & Business Logic

**Scope:** entities, value objects, use cases, services, calculators, validators, business rules.

**Deep checks:** invariants, transitions, arithmetic, validation, edge cases, null/default semantics, duplicate rules, UI/local/cloud rule consistency.

**Invariant:** each business operation has one coherent set of rules regardless of invocation path.

## Part 08 — Product & Catalog

**Scope:** products, categories, suppliers, pricing, SKUs, barcodes, images, archive/delete behavior.

**Deep checks:** identity/uniqueness, relationships, image lifecycle, CRUD, archive/delete, restore, sync, duplicates, stale references.

**Invariant:** catalog identity and relationships survive CRUD, offline use, sync, restore, and multi-device changes.

## Part 09 — Sales & Checkout

**Scope:** cart, sale creation, sale items, payments, split payments, discounts, refunds, returns, voids, receipts.

**Deep checks:** atomicity, duplicate submission, retries, totals, inventory effects, customer-credit effects, offline behavior, process death.

**Invariant:** a sale is consistently applied or safely recoverable; retries cannot duplicate financial/inventory effects.

## Part 10 — Financial & Ledger Integrity

**Scope:** integer money, balances, income, expenses, cash movements, payments, credit, reversals, financial projections.

**Deep checks:** arithmetic, rounding, signs, balance calculations, reversals, duplicates, concurrency, historical immutability, scope.

**Invariant:** financial state is deterministic, integer-safe, auditable, and resistant to duplicate/partial application.

**Special rule:** financial findings require explicit regression evidence before closure.

## Part 11 — Inventory & Stock

**Scope:** stock levels, movements, adjustments, sale deductions, returns, restore, location stock.

**Deep checks:** movement identity, quantity arithmetic, negative-stock rules, duplicate movements, sale/return coupling, location scope, concurrency, restore, sync.

**Invariant:** stock is the deterministic result of valid inventory events and converges correctly across retries/devices.

## Part 12 — Customers & Credit

**Scope:** customers, balances, credit sales, customer payments, history.

**Deep checks:** identity, balance arithmetic, allocation, reversal, duplicate payments, deletion/archive, authorization, scope, sync.

**Invariant:** customer balances/history remain correct after sales, payments, reversals, retries, and synchronization.

## Part 13 — Cloud APIs & Edge Functions

**Scope:** Supabase RPCs, Edge Functions, Fulus APIs, DTOs, authentication/authorization.

**Deep checks:** validation, auth, membership/location/business authorization, idempotency, OCC, error mapping, response validation, privilege boundaries, secrets.

**Invariant:** every cloud mutation is authenticated, authorized, validated, scoped, and retry-safe where applicable.

## Part 14 — Sync Engine

**Scope:** outbox, push, pull, cursors, sync sequence, dependency ordering, retries, leases, reconciliation, canonical apply.

**Deep checks:** durable outbox, ordering, idempotency, cursor advancement, partial push/pull, duplicate delivery, concurrent workers, lease expiry, process death, offline/online transitions.

**Invariant:** authorized devices converge without lost, duplicated, reordered, or unauthorized mutations.

## Part 15 — Backup, Restore & Cross-Device Provisioning

**Scope:** snapshots, restore importer, employee provisioning, ordering, device registration, restore cursor, post-restore sync.

**Deep checks:** snapshot completeness, dependency ordering, atomicity, partial restore, malformed rows, identity projection, readiness, retry, fresh-install behavior.

**Invariant:** a fresh device can be provisioned without partial business state or indefinite blocking on secondary synchronization.

## Part 16 — Multi-Device Convergence & Conflict Safety

**Scope:** OCC, conflict detection, canonical reconciliation, device identity, concurrent edits, convergence tooling.

**Deep checks:** simultaneous edits, sale/stock races, returns, offline edits, reconnect, duplicate retry, process death, registration changes.

**Invariant:** concurrent devices converge deterministically while preserving financial, inventory, identity, and authorization invariants.

## Part 17 — Background Execution & OS Lifecycle

**Scope:** WorkManager, background sync, retries, suspension, force-stop, process death, network transitions.

**Deep checks:** durable scheduling, worker idempotency/concurrency, lease interaction, retry/backoff, kill during mutation, network loss, OS restrictions.

**Invariant:** important durable work survives application and OS lifecycle interruptions.

## Part 18 — UI, Navigation & Application State

**Scope:** screens, routes, navigation, controllers/providers, loading, first frame, back navigation, employee/location state, stale UI.

**Deep checks:** route ownership, async gates, FutureBuilder/streams, flashes/splash screens, back stack, state restoration, stale/unauthorized data, errors.

**Invariant:** primary workflows feel immediate and show only correct authorized state.

## Part 19 — Errors, Diagnostics & Observability

**Scope:** exceptions, error mapping, logging, diagnostics, sync failure reporting, user-facing errors.

**Deep checks:** swallowed exceptions, generic errors hiding root causes, retry decisions, sensitive logs, diagnostic persistence/upload/retry/retention.

**Invariant:** important failures remain diagnosable without exposing sensitive information or breaking offline operation.

## Part 20 — Security & Production Hardening

**Scope:** RLS, RPC grants, Edge Function authorization, secrets, validation, tenant isolation, migration security, production/release configuration.

**Deep checks:** privilege escalation, anonymous/authenticated access, cross-business/location access, role bypasses, direct DB access, SECURITY DEFINER exposure, secret/config drift.

**Invariant:** no actor can access or mutate outside its authoritative business, membership, location, and permission boundaries.

# 6. Four inspection passes for every part

### Pass A — Structural inventory

Record files, classes, interfaces, enums, extensions, providers, services, repositories, methods, tests, callers, and dependencies.

### Pass B — Function/class audit

For every relevant class/function inspect inputs, outputs, state changes, dependencies, DB/network calls, side effects, exceptions, retries, authorization, concurrency, callers, and tests.

### Pass C — Line/branch audit

Inspect actual implementation for wrong conditions/order, nullability mistakes, incorrect IDs/scopes, missing transactions/awaits, swallowed exceptions, races, duplicate/partial writes, stale state, unsafe defaults, unreachable branches, and cleanup.

### Pass D — Cross-system audit

Trace important operations end-to-end:

```
UI → Controller → Use Case → Repository → Drift
→ Outbox → Sync → Edge Function → Postgres
→ Change Feed → Other Device → Drift
```

The deliverable is an end-to-end invariant verification, not merely a source review.

# 7. Cross-cutting dimensions

Every applicable part must explicitly consider:

- correctness
- data integrity
- authorization
- business isolation
- location isolation
- concurrency
- retry safety
- offline behavior
- process death
- lifecycle
- observability
- performance
- UX
- test coverage
- production parity

# 8. Finding format

Use:

### FINDING-ID

**Part:**  
**Severity:**  
**Status:**  
**Files:**  
**Functions/classes:**  

**Observed behavior**  
What the code actually does.

**Expected invariant**  
What must be true.

**Root cause**  
The exact implementation reason.

**Impact**  
What can happen in production.

**Evidence**  
Source trace, tests, runtime observation, SQL/log evidence, or reproduction.

**Fix**  
Smallest safe corrective change.

**Regression test**  
What proves the fix.

**Cross-check**  
Adjacent/related paths inspected for the same defect.

**Verification**  
CI/runtime/device/production evidence.

# 9. Central audit ledger

Maintain:

| ID | Part | Severity | Status | File | Function/Class | Finding | Invariant | Fix | Test | Evidence | CI | Runtime |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

IDs:

- `P01-001`, `P01-002`, ...
- `P20-001`, ...
- Cross-cutting: `X-001`, `X-002`, ...

# 10. Per-part documents

Use:

```
docs/deep-code-audit/
  MASTER_PLAN.md
  PART-01-BOOTSTRAP-LIFECYCLE.md
  PART-02-AUTH-SESSIONS.md
  PART-03-EMPLOYEE-ACCESS.md
  PART-04-BUSINESS-LOCATION.md
  PART-05-LOCAL-DATABASE.md
  PART-06-REPOSITORIES.md
  PART-07-DOMAIN-LOGIC.md
  PART-08-PRODUCT-CATALOG.md
  PART-09-SALES-CHECKOUT.md
  PART-10-FINANCIAL-INTEGRITY.md
  PART-11-INVENTORY-STOCK.md
  PART-12-CUSTOMERS-CREDIT.md
  PART-13-CLOUD-APIS.md
  PART-14-SYNC-ENGINE.md
  PART-15-RESTORE-PROVISIONING.md
  PART-16-MULTI-DEVICE.md
  PART-17-BACKGROUND-LIFECYCLE.md
  PART-18-UI-NAVIGATION.md
  PART-19-ERRORS-OBSERVABILITY.md
  PART-20-SECURITY-HARDENING.md
  FINDINGS.md
  CROSS-CUTTING.md
  FINAL-REPORT.md
```

# 11. Independent-session protocol

At the start of every session:

1. Read this master plan.
2. Read the assigned part document if it exists.
3. Read `FINDINGS.md`.
4. Read `CROSS-CUTTING.md`.
5. Inspect current `main` and record the baseline SHA.
6. Check whether another session already changed the relevant area.
7. Do not repeat closed findings except for cross-checking.

At the end:

1. update the part document
2. update findings/cross-cutting records
3. record evidence
4. record unknowns
5. record tests
6. record CI status
7. record commit/PR
8. record next work

# 12. Session handoff template

```markdown
## Session handoff

**Part:**  
**Baseline SHA:**  
**Audit branch:**  
**Current SHA:**  

### Completed
- ...

### Findings
- ...

### Fixed
- ...

### Still open
- ...

### Deferred
- ...

### Evidence
- ...

### Tests
- ...

### CI
- ...

### Runtime/production verification
- ...

### Files inspected
- ...

### Next recommended step
- ...
```

# 13. Recommended order

```
01 Bootstrap/Lifecycle
 ↓
02 Auth/Sessions
 ↓
03 Employee/Access
 ↓
04 Business/Location
 ↓
05 Database
 ↓
06 Repositories
 ↓
07 Domain Logic
 ↓
08 Products
 ↓
09 Sales
 ↓
10 Financial
 ↓
11 Inventory
 ↓
12 Customers
 ↓
13 Cloud APIs
 ↓
14 Sync
 ↓
15 Restore
 ↓
16 Multi-device
 ↓
17 Background
 ↓
18 UI
 ↓
19 Errors/Observability
 ↓
20 Security/Production
```

Independent sessions may work in parallel when scopes do not overlap. After Parts 01–20, perform cross-cutting reconciliation.

# 14. Cross-cutting reconciliation

After all 20 parts inspect:

### Duplicate logic
Multiple implementations of the same business rule.

### Contradictory invariants
UI, domain, local DB, cloud API, and Postgres making incompatible assumptions.

### Identity chain
Auth user ID → membership ID → employee ID → device ID → business ID → location ID → local row IDs.

### State chain
Auth state → employee state → location state → sync state → connection state → database state → UI state.

### Failure paths
For important operations consider:

```
success
offline
timeout
auth expiry
duplicate retry
process death
partial cloud failure
partial local failure
concurrent operation
revocation
```

# 15. Fulus first-class invariants

- **Local-first:** core business operations remain usable offline.
- **Invisible sync:** users should not manage technical sync concepts.
- **Durable mutation:** accepted local mutations remain durable until reconciled.
- **Idempotency:** retries do not duplicate financial, inventory, customer, or employee effects.
- **Tenant isolation:** business A cannot reach business B.
- **Location isolation:** location A cannot reach location B.
- **Authorization:** UI visibility is not the security boundary.
- **Financial integrity:** money is integer-safe, deterministic, atomic where required, and reversal-safe.
- **Inventory integrity:** stock events cannot be duplicated by retry.
- **Convergence:** authorized devices eventually converge.
- **Process death:** durable work survives termination.
- **Restore integrity:** restore cannot claim readiness while required state is missing.
- **Instant UI:** primary navigation does not wait on unnecessary network/secondary hydration.
- **Error diagnosability:** important failures retain enough evidence to identify root cause.

# 16. Definition of done for each part

- [ ] File inventory completed
- [ ] Classes/interfaces inspected
- [ ] Functions/methods inspected
- [ ] Important branches inspected
- [ ] Call chains traced
- [ ] DB boundaries inspected
- [ ] Network boundaries inspected where applicable
- [ ] Authorization boundaries inspected where applicable
- [ ] Concurrency/retry behavior considered
- [ ] Failure paths considered
- [ ] Tests reviewed
- [ ] Missing tests identified
- [ ] Concrete findings recorded
- [ ] Fixes implemented where justified
- [ ] Regression tests added/updated
- [ ] Relevant tests pass
- [ ] Required CI passes
- [ ] Cross-check completed
- [ ] Evidence recorded
- [ ] Remaining uncertainty documented
- [ ] Part document updated
- [ ] Commit/PR recorded

# 17. Definition of done for the entire audit

- [ ] Parts 01–20 completed
- [ ] Blocker/Critical findings closed or explicitly accepted with evidence
- [ ] High findings closed or explicitly tracked with a release decision
- [ ] Cross-cutting reconciliation completed
- [ ] Duplicate/contradictory logic reviewed
- [ ] Identity chain verified
- [ ] Local-first invariants verified
- [ ] Sync invariants verified
- [ ] Financial invariants verified
- [ ] Inventory invariants verified
- [ ] Restore invariants verified
- [ ] Multi-device convergence verified
- [ ] Process-death behavior verified
- [ ] Security boundaries verified
- [ ] Required Android evidence collected
- [ ] Required production Supabase evidence collected
- [ ] Final CI green
- [ ] Final report produced
- [ ] Remaining limitations explicit

Completion does **not** mean “no findings.” It means remaining risks are known, evidenced, classified, and tracked.

# 18. Final report

The final report should contain:

1. Executive summary
2. Audit baseline
3. Parts completed
4. Findings by severity
5. Findings by subsystem
6. Fixed findings
7. Deferred findings
8. Runtime verification gaps
9. Security findings
10. Financial/data-integrity findings
11. Sync/convergence findings
12. UI/lifecycle findings
13. Cross-cutting findings
14. Test evidence
15. CI evidence
16. Production evidence
17. Remaining risks
18. Recommended next engineering phase

Do not claim production readiness merely because all code was inspected.

# 19. Starting another session

Example instruction:

> Read `docs/deep-code-audit/MASTER_PLAN.md`. You are responsible for Part 14, Sync Engine. Inspect the current `main` branch deeply, line by line, function by function, class by class. Follow the master-plan evidence rules. Do not stop at identifying issues: prove them, fix safe concrete findings, add regression tests, cross-check adjacent code, run CI, and update the Part 14 audit document and findings ledger. Continue until the part is genuinely complete or remaining items require explicit runtime/production evidence.

The session should work from the current repository state rather than relying on assumptions from previous sessions.

# 20. Core philosophy

The audit is not:

> “Does this code look good?”

It is:

> **“Can we prove that this implementation preserves Fulus's required invariants under normal operation, offline operation, retries, concurrency, process death, synchronization, restore, authorization changes, and multi-device use?”**

**Inspect deeply. Prove concretely. Fix conservatively. Test aggressively. Cross-check everything. Never declare complete on assumption.**
