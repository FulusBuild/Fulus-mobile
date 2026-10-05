# Fulus Architectural Benchmark

**Status:** Active architectural benchmark and decision baseline  
**Baseline:** Fulus main after the PR #160 money-boundary merge, 2026-10-05

## Purpose

This document benchmarks Fulus against published engineering standards and practices from Google Cloud, AWS, Microsoft Azure, Google SRE, Android Architecture, OWASP, and Carnegie Mellon SEI.

It is a decision framework, not a claim of endorsement by those organizations. The yardstick is their published engineering principles; infrastructure choices remain specific to Fulus.

The benchmark answers five questions for every architectural area:

- **Keep** — the design is sound and should remain.
- **Strengthen** — the design is right but needs hardening or proof.
- **Simplify** — the design can provide the same guarantee with less complexity.
- **Redesign** — the current boundary cannot reliably satisfy the requirement.
- **Reject** — a proposed pattern adds complexity without a justified Fulus quality benefit.

---

# 1. External engineering yardstick

## AWS Well-Architected

AWS defines a consistent set of practices and questions for evaluating architectures across operational excellence, security, reliability, performance efficiency, cost optimization, and sustainability.

Fulus uses the principles, not AWS-specific infrastructure. The benchmark therefore asks whether Fulus can operate, recover, secure, change, and measure itself reliably over its full lifecycle.

## Google Cloud Well-Architected

Google Cloud evaluates operational excellence, security, reliability, cost, performance, and sustainability, with strong emphasis on resilient operation and continuous improvement.

Fulus therefore treats reliability as a user/business property, not simply server uptime.

## Microsoft Azure Well-Architected

Azure emphasizes reliability, security, cost optimization, operational excellence, and performance efficiency. Its reliability guidance explicitly favors simplicity, failure-mode analysis, recovery planning, appropriate redundancy, and measurable reliability.

Fulus therefore rejects complexity that does not protect a real business requirement.

## Google SRE

Google SRE emphasizes user-centered SLOs, actionable monitoring, controlled releases, reliability testing, automation, and simplicity.

Fulus therefore must eventually measure outcomes such as sale success, convergence time, recovery time, restore success, and user-visible latency.

## Android offline-first architecture

Android guidance says critical functionality should work without reliable network access, local data should be available immediately, repositories should mediate local/network data sources, writes can be queued, and synchronization must explicitly handle conflicts and retries.

This strongly validates Fulus's local-first direction.

## OWASP

OWASP API guidance treats authorization as a server-side responsibility and specifically highlights broken object-level authorization as a major API risk.

Fulus therefore cannot trust client-provided business IDs, location IDs, object IDs, employee IDs, or device IDs as authority.

## CMU SEI ATAM

SEI's Architecture Tradeoff Analysis Method evaluates architecture through quality attributes, risks, sensitivities, and trade-offs.

Fulus adopts the same mindset: every important mechanism must identify the quality attribute or invariant it protects, the failure it prevents, its trade-offs, and the evidence that proves it.

---

# 2. Benchmark methodology

Each domain is evaluated using:

1. External engineering criterion.
2. Fulus intended architecture.
3. Actual implementation evidence.
4. Result:
   - 🟢 Meets
   - 🟡 Partial / hardening or evidence required
   - 🔴 Does not meet / blocker
   - ⚪ Not applicable
5. Keep / Strengthen / Simplify / Redesign / Reject decision.
6. Executable or physical fitness test.

The benchmark deliberately distinguishes architecture defects, implementation defects, evidence gaps, intentional trade-offs, and unnecessary complexity.

---

# 3. Executive benchmark result

Fulus has a **strong core architecture** and does not need a wholesale rewrite.

The strongest architectural decisions are:

- local-first/offline-first business operation;
- SQLite/Drift as the immediate local source for UI reads;
- durable local outbox;
- asynchronous synchronization;
- stable operation identity and server idempotency;
- server canonical state and reconciliation;
- optimistic concurrency controls;
- location-scoped mutations and authorization;
- cloud-authoritative membership and permissions;
- transactional financial operations;
- explicit money representation;
- durable sync execution coordination;
- diagnostic capture;
- migration-as-code and CI.

The important weaknesses are boundary weaknesses, not a fundamentally wrong architecture:

1. Restore needs a true maintenance fence against active sync.
2. Money boundaries need a strict, unambiguous wire contract.
3. Several distributed guarantees still need physical Android/runtime proof.
4. Some local invariants should be enforced by database constraints.
5. Observability needs user/business SLOs.
6. Future architecture must continue simplifying rather than accumulating coordination layers.

**Overall architectural direction: 🟢 STRONG**  
**Current production architecture: 🟡 CONDITIONAL**  
**Primary blockers: restore fencing/evidence and final money-boundary hardening.**

---

# 4. Domain benchmark

## 4.1 Simplicity and architectural restraint — 🟢

**Evidence:** Fulus remains one Flutter application with one local SQLite database, one sync subsystem, and one primary cloud platform. It does not require microservices, Kubernetes, or a general-purpose message broker.

**Decision: KEEP**

Keep local-first architecture, centralized sync boundaries, and explicit coordination only where an invariant is protected.

**Strengthen:** document the invariant protected by every gate and periodically remove abstractions that no longer protect a real property.

**Reject:** microservices, Kubernetes, service meshes, or brokers solely for fashion or hypothetical scale.

---

## 4.2 Offline-first operation — 🟢

Android's offline-first guidance requires critical functionality to remain usable without reliable network access.

Fulus sale creation writes sale, items, payments, stock, customer credit, and the durable outbox entry in one local transaction before network synchronization.

**Decision: KEEP**

**Fitness test:** disable network, create a sale, kill the app, reopen, restore connectivity, and verify one canonical cloud mutation.

**Reject:** making checkout wait for cloud acknowledgement.

---

## 4.3 Transactional domain operations — 🟢

Fulus performs the local sale mutation transactionally and uses authoritative cloud transaction functions for financial operations.

**Decision: KEEP / STRENGTHEN**

Maintain atomic local business effects and cloud financial transactions.

**Fitness test:** a failed operation must not leave a partial sale, partial payment, partial stock decrement, or missing durable sync intent.

---

## 4.4 Durable outbox and delivery — 🟢

Fulus has a durable SQLite sync queue, stable operation IDs, retries, backoff, dependencies, actor/location attribution, and server idempotency.

Azure's Transactional Outbox guidance uses the same core principle: persist business state and outbound intent atomically so failure cannot silently lose an event.

**Decision: KEEP**

**Strengthen:** monitor queue age, retry count, attention-needed operations, and convergence time.

**Reject:** fire-and-forget network writes and retry logic without idempotency.

---

## 4.5 Synchronization and convergence — 🟢/🟡

Fulus has server sync_sequence ordering, a durable pull cursor, apply-before-cursor-advance behavior, replay-safe reconciliation, OCC, conflict records, dependency-aware draining, and a cross-runtime SQLite execution lease.

The architecture is strong. Runtime proof is incomplete.

**Decision: KEEP / STRENGTHEN**

Required evidence:

- physical process-death recovery;
- foreground/background contention;
- long-running sync;
- multi-device convergence;
- stale cursor/replay conditions.

---

## 4.6 Source of truth and projection — 🟢

Fulus uses a deliberate two-level authority model:

- local DB = immediate on-device application source;
- cloud = business-wide canonical state;
- synchronization reconciles canonical state into the local projection.

**Decision: KEEP**

Every domain object should document its local source, cloud authority, sync direction, conflict authority, and identity key.

**Reject:** ambiguous designs where local and cloud are both called authoritative.

---

## 4.7 Identity, membership, and authorization — 🟢/🟡

Cloud membership, roles, permissions, and location membership are authoritative. Local employee/access state is a projection used for offline enforcement. Server functions validate business, location, actor, device, and permission relationships.

OWASP's authorization principles support this server-authoritative boundary.

**Decision: KEEP / STRENGTHEN**

Continue adversarial authorization tests and explicitly document delayed offline revocation.

The offline revocation delay is an intentional trade-off: immediate remote authorization would violate Fulus's offline-first requirement.

---

## 4.8 Location isolation — 🟡

Fulus has location-scoped stock, transactions, authorization, device/idempotency scope, and mutation location identity.

The remaining critical proof is:

1. mutation created in Location A;
2. mutation remains pending or in-flight;
3. user switches to B;
4. new B mutations are created;
5. reconnect occurs;
6. A mutation settles in A;
7. B never inherits A transient state.

**Decision: STRENGTHEN**

Do not mark this fully green until the adversarial scenario is proven.

---

## 4.9 Money representation — 🟡

The reported corruption exposed an architectural boundary violation: local minor-unit integers were being mixed with cloud major-unit representations.

PR #160 corrected the cloud write boundary using explicit money wire conversion.

The intended invariant is:

local minor integer -> decimal wire value -> cloud numeric

and the reverse exactly once.

**Decision: KEEP DESIGN / STRENGTHEN CONTRACT**

Local/domain/SQLite money should remain integer minor units.

The remaining hardening is important: the wire contract should not permit an integer to ambiguously mean either major or minor units. The current parser remains permissive for integer wire values, so the final benchmark should require an explicit decimal-string contract and tests for all money-bearing entities.

**Mandatory money fitness tests:**

- 300 price x 100 quantity;
- amounts below one major unit;
- large amounts;
- refunds/negative adjustments where valid;
- split payments;
- credit;
- cash tender/change;
- restore;
- canonical reconciliation;
- every money-bearing entity.

**Reject:** any generic serializer that guesses the unit of an integer.

---

## 4.10 Financial semantics — 🟡

Cloud sale logic validates payment totals, paid amount, credit amount, cash tender/change, idempotency, and actor/device context. Financial fidelity SQL tests exist.

**Decision: STRENGTHEN**

Maintain one canonical financial contract:

Sale total = payment legs  
Amount paid = non-credit collected legs  
Balance due = credit leg  
Cash change = tendered - applied

Local and cloud projections must preserve these identities.

---

## 4.11 Restore and recovery — 🔴 BLOCKER

This is the clearest architectural weakness.

Current restore coordination acquires the sync execution lease, checks pending operations/conflicts, restores transactionally, and uses a restart gate.

However, a sync execution lease is not automatically the same thing as a dedicated maintenance fence proving that no active sync runtime can still use the database while restore closes/replaces/reopens it.

**Decision: REDESIGN**

Required lifecycle:

restore requested
-> enter maintenance/restore fence
-> stop new sync work
-> wait for active sync to become idle
-> prove no sync transaction is active
-> close database
-> replace/import database
-> reopen
-> invalidate stale DB-bound services
-> require restart or rebuild all DB-bound services
-> exit maintenance fence
-> resume normal sync

**Mandatory tests:**

- restore while idle;
- restore during foreground sync;
- restore while WorkManager is scheduled;
- restore during canonical apply;
- process death during restore;
- restart after restore;
- verify repositories use the restored database;
- verify no pre-restore outbox mutation is accidentally replayed.

This remains a benchmark blocker.

---

## 4.12 Database invariants — 🟡

Fulus already uses DB-level uniqueness for product SKU/barcode and strong transactional/OCC protections in cloud operations.

Potential remaining application-only races include:

- one active draft per location;
- one open cash drawer shift per location.

**Decision: STRENGTHEN**

Where SQLite can express an invariant with a unique/partial index, use the DB as the final correctness boundary.

Application checks can remain for good UX, but correctness should not depend on SELECT-then-INSERT under concurrency.

---

## 4.13 Security — 🟢/🟡

Fulus has RLS, server permission checks, actor/device binding, business/location authorization, SECURITY DEFINER search-path hardening, legacy RPC execute lockdown, device controls, and authorization contract tests.

**Decision: KEEP / STRENGTHEN**

Continue adversarial object/business/location/device authorization tests and production grant verification.

**Reject:** client-only authorization.

---

## 4.14 Observability — 🟡

Fulus has diagnostic logging, breadcrumbs, error capture, diagnostic rules, persistent diagnostic events, remote upload, and sync status.

Google SRE treats monitoring as foundational and emphasizes actionable signals.

**Decision: STRENGTHEN**

Add user/business outcome measurements:

- local sale commit latency;
- first-frame/navigation latency;
- sync queue age;
- convergence time;
- attention-needed operations;
- restore duration/success;
- financial invariant failures;
- authorization failures;
- background recovery;
- crash/restart recovery.

Alerts should be actionable, not merely noisy.

---

## 4.15 Performance and instant UX — 🟡

Fulus is local-first and has an instant UI contract, indexed navigation, and sync apply logic that avoids network calls while holding SQLite writer transactions.

**Decision: STRENGTHEN / PROVE**

Measure real Android route latency for Home, Sell, Stock, Money, More, complete payment, and back navigation.

A visible splash/flash on a primary route is a user-visible architecture/performance defect even if the underlying operation is technically fast.

---

## 4.16 Change management and migrations — 🟢/🟡

Fulus has ordered Drift migrations, extensive Supabase migration history, production migration workflows, migration verification, and CI.

**Decision: KEEP / STRENGTHEN**

Every schema change should have forward migration, compatibility consideration, representative upgrade testing, and production verification.

**Fitness test:** upgrade a representative previous-release database to current main without data loss.

---

## 4.17 Testing and architecture fitness — 🟢/🟡

Fulus already tests sync queue behavior, retry, process-death replay, cursor boundaries, execution leases, restore gates, canonical reconciliation, financial convergence, location authorization, financial fidelity, and API authorization.

Google SRE recommends testing reliability rather than assuming it. SEI ATAM similarly evaluates architecture through quality-attribute scenarios.

**Decision: KEEP / STRENGTHEN**

Create a permanent architecture fitness suite for:

1. money boundary invariance;
2. offline sale atomicity;
3. durable outbox;
4. process-death replay;
5. multi-device convergence;
6. location isolation;
7. actor attribution;
8. authorization isolation;
9. restore fencing;
10. DB concurrency invariants;
11. release upgrade;
12. user-visible route latency.

---

## 4.18 Scalability — 🟢/🟡

The architecture already uses asynchronous sync, change-feed ordering, batching, indexes, and server transactions.

It is intentionally not decomposed into many services.

**Decision: KEEP / MEASURE**

Measure business/device counts, mutation rate, change-feed growth, retention, sync latency, and database pressure before adding infrastructure.

**Reject:** premature microservice decomposition.

---

## 4.19 Cost efficiency — 🟢

Local-first operation reduces unnecessary network dependency and lets the application perform critical work without repeated cloud calls.

**Decision: KEEP**

Continue batching and incremental synchronization.

---

## 4.20 Sustainability — 🟢/⚪

Efficient local work, bounded synchronization, and reduced unnecessary network activity are favorable.

**Decision: KEEP WITHOUT ADDED COMPLEXITY**

Do not add architecture solely for sustainability scoring without material impact.

---

# 5. Cross-cutting invariants

These are the architectural rules that matter more than individual classes.

### A. Local business continuity
Critical business operations remain usable without network access.

### B. Money magnitude preservation
A monetary value must retain exactly the same meaning through UI, domain, SQLite, queue, wire, cloud, canonical response, SQLite, and UI.

### C. Atomic local mutation
A sale cannot exist without its required dependent effects and durable sync intent.

### D. Durable operation identity
Retrying an operation cannot create a second business mutation.

### E. Canonical convergence
Valid replicas converge on authoritative cloud state.

### F. Location isolation
A mutation created in A cannot execute or project into B.

### G. Actor integrity
A queued employee mutation executes as its recorded actor, not whichever employee is active later.

### H. Authorization boundary
The server independently validates business, location, actor, device, permission, and object ownership.

### I. Restore safety
Restore never races active synchronization and never leaves live services using stale DB references.

### J. User-visible immediacy
Primary interaction does not wait for synchronization or unnecessary reinitialization.

---

# 6. What Fulus should KEEP

1. Local-first/offline-first.
2. SQLite/Drift local source for immediate UI.
3. Durable local outbox.
4. Stable operation IDs and server idempotency.
5. Dependency-aware sync.
6. Change-feed synchronization.
7. Server canonical state.
8. Canonical reconciliation.
9. OCC and explicit conflict handling.
10. Cloud-authoritative membership/permissions.
11. Location-scoped authorization.
12. Transactional financial operations.
13. Integer minor-unit money locally.
14. Automatic background synchronization.
15. Explicit lifecycle gates that protect real invariants.
16. Diagnostics.
17. Migration-as-code and CI.
18. Single-application architecture.

---

# 7. What Fulus should STRENGTHEN

### P0
- dedicated restore-vs-sync maintenance fence;
- strict money wire contract;
- complete money fitness suite;
- physical restore/reopen/restart proof.

### P1
- A->B pending/in-flight location proof;
- WorkManager/process-death proof;
- multi-device convergence proof;
- foreground/background contention proof.

### P2
- database concurrency constraints;
- user/business SLOs;
- release upgrade testing;
- production migration verification.

### P3
- simplify coordination layers and remove redundant state machines.

---

# 8. What Fulus should SIMPLIFY

1. Hide technical sync/cloud concepts from users.
2. Present sync as automatic backup and convergence.
3. Keep one central sync service boundary.
4. Keep one primary backend platform until scale proves otherwise.
5. Use DB constraints instead of duplicated application correctness checks.
6. Use one Money type and explicit conversions.
7. Use one authoritative identity model.
8. Use one canonical financial contract.
9. Remove duplicate readiness/lifecycle state machines.
10. Keep the UI simple and immediate.

---

# 9. What Fulus should REDESIGN

### R1 — Restore lifecycle
Introduce a true maintenance fence and prove it against active foreground/background sync.

### R2 — Money wire contract
Make cloud monetary values explicitly decimal and reject ambiguous integer representations.

### R3 — Architecture fitness suite
Turn benchmark invariants into executable CI gates.

### R4 — Observability
Measure business/user outcomes, not just technical events.

---

# 10. What Fulus should REJECT

Unless a future benchmark proves a real requirement:

- mandatory online checkout;
- generic cloud-first CRUD architecture;
- microservices for their own sake;
- Kubernetes for its own sake;
- a message broker when outbox/change-feed is sufficient;
- client-only authorization;
- ambiguous money serialization;
- screen-level patches for domain/data-integrity defects;
- duplicated local/cloud sources of truth;
- retry without idempotency;
- application-only enforcement where DB constraints are practical;
- UI complexity without a measured user benefit;
- infrastructure built only for hypothetical scale.

---

# 11. Priority architecture backlog

| Priority | Work | Decision | Exit condition |
|---|---|---|---|
| P0 | Restore maintenance fence | Redesign | Restore cannot overlap active sync |
| P0 | Strict money wire contract | Strengthen | No ambiguous monetary integer crosses a boundary |
| P0 | End-to-end money suite | Strengthen | All money-bearing entities preserve magnitude |
| P0 | Physical restore/reopen test | Evidence | Verified on Android |
| P1 | A->B pending/in-flight test | Evidence | Mutation remains in original location |
| P1 | WorkManager/process-death proof | Evidence | Queue survives real process death |
| P1 | Multi-device convergence proof | Evidence | Canonical state converges without duplication |
| P1 | Foreground/background contention | Evidence | One safe sync execution at a time |
| P2 | DB concurrency constraints | Strengthen | Race tests cannot create duplicate active state |
| P2 | User/business SLOs | Strengthen | Critical outcome metrics exist |
| P2 | Release upgrade test | Evidence | Previous release upgrades safely |
| P3 | Coordination simplification | Simplify | Every remaining gate has a documented invariant |

---

# 12. Benchmark scorecard

| Domain | Result | Decision |
|---|---|---|
| Simplicity | 🟢 | Keep |
| Offline-first | 🟢 | Keep |
| Transactional domain | 🟢 | Keep / strengthen |
| Durable outbox | 🟢 | Keep |
| Synchronization | 🟢/🟡 | Keep / prove |
| Canonical convergence | 🟢/🟡 | Keep / prove |
| Source of truth | 🟢 | Keep |
| Identity/access | 🟢/🟡 | Keep / strengthen |
| Location isolation | 🟡 | Strengthen |
| Money representation | 🟡 | Strengthen |
| Financial semantics | 🟡 | Strengthen |
| Restore/recovery | 🔴 | Redesign |
| Database invariants | 🟡 | Strengthen |
| Security | 🟢/🟡 | Keep / strengthen |
| Observability | 🟡 | Strengthen |
| Performance / instant UX | 🟡 | Prove |
| Change management | 🟢/🟡 | Keep / strengthen |
| Testing | 🟢/🟡 | Strengthen |
| Scalability | 🟢/🟡 | Keep / measure |
| Cost efficiency | 🟢 | Keep |
| Sustainability | 🟢/⚪ | Keep without added complexity |

**Overall: STRONG CORE / CONDITIONAL PRODUCTION ARCHITECTURE**

---

# 13. Benchmark exit criteria

The benchmark becomes production-credible when:

- [ ] Money magnitude preservation is enforced across every boundary.
- [ ] No cloud wire monetary integer is ambiguous.
- [ ] Restore has a dedicated maintenance fence.
- [ ] Restore is proven safe against active foreground/background sync.
- [ ] Process-death replay is proven on Android.
- [ ] WorkManager recovery is proven on Android.
- [ ] A->B location switching is proven with pending/in-flight mutations.
- [ ] Multi-device convergence is proven.
- [ ] Authorization isolation is adversarially tested.
- [ ] DB concurrency invariants are enforced at the strongest practical boundary.
- [ ] Release upgrade is tested from a representative previous version.
- [ ] User/business SLOs exist for critical flows.
- [ ] Architecture fitness tests run in CI.
- [ ] Every remaining architectural gate has a documented invariant.
- [ ] No unnecessary infrastructure has been introduced.

---

# 14. How the benchmark changes future debugging

Future defects should be classified by architectural invariant, not only by screen.

Examples:

- ₦300 becoming ₦30,000 is a **money-boundary invariant violation**, not a Sell-screen formatting bug.
- Restore corruption/race is a **lifecycle/maintenance-fencing violation**, not merely a restore-screen bug.
- Employee access crossing a location is an **authorization/location-isolation violation**, not merely navigation.
- Duplicate cloud mutation after retry is an **idempotency violation**, not merely a sync-handler bug.
- A visible splash before a primary screen is a **user-visible latency violation**, not merely a widget issue.

This prevents local patches from hiding root architectural defects.

---

# 15. Architecture change decision rule

Before adding any component, abstraction, service, queue, cache, state machine, or synchronization mechanism, answer:

1. What business requirement does it protect?
2. Which quality attribute does it improve?
3. Which failure mode does it prevent?
4. What simpler alternative was considered?
5. What new failure modes does it introduce?
6. How is it tested?
7. How is it observed in production?
8. Can the guarantee be enforced at a stronger/lower boundary?
9. Does it preserve offline-first operation?
10. Does it reduce or increase total system complexity?

If these questions cannot be answered, the default decision is **do not add it**.

---

# 16. Repository evidence used

- lib/core/money/money.dart
- lib/data/repositories/sale_repository_impl.dart
- lib/data/local/database/database.dart
- lib/data/local/database/tables.dart
- lib/data/remote/fulus_sync_coordinator.dart
- lib/data/remote/cloud_restore_coordinator.dart
- lib/sync/sync_engine.dart
- lib/sync/sync_execution_lease.dart
- supabase/functions/fulus-api/index.ts
- supabase/functions/fulus-sync-state/index.ts
- supabase/tests/financial_fidelity.sql
- test/sync/sync_process_death_replay_test.dart
- test/sync/sync_restore_reconciliation_gate_test.dart
- test/sync/p16_multi_device_financial_convergence_test.dart
- docs/FULL_PRODUCTION_READINESS_AUDIT.md
- docs/INSTANT_UI_CONTRACT.md
- docs/architecture/SYNC_ARCHITECTURE_SIMPLIFICATION.md

---

# 17. Reference standards

- AWS Well-Architected Framework.
- Google Cloud Well-Architected Framework.
- Microsoft Azure Well-Architected Framework.
- Google SRE principles, SLOs, monitoring, release engineering, and reliability testing.
- Android Developers offline-first architecture.
- OWASP API Security Top 10.
- Microsoft Azure Architecture Center guidance for transactional outbox and transient faults.
- Carnegie Mellon SEI Architecture Tradeoff Analysis Method.

This document is a living benchmark. When architecture changes, update the implementation, add/update the relevant fitness test, re-run the affected benchmark domain, and record the decision.

**Last benchmark baseline: 2026-10-05**
