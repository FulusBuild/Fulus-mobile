# Fulus Implementation Benchmark

**Status:** Active engineering benchmark  
**Baseline:** `main` at `034a03a7f9325aea8f178e8f5773477512697657`  
**Date:** 2026-10-06  
**Question:** If a strong principal-engineering team were given Fulus from scratch, would they implement the system in substantially the same way?

---

## 1. What this benchmark is asking

The existing **Fulus Architectural Benchmark** asks whether Fulus has the right architectural decisions.

This document asks a harder question:

> **Given the same product requirements and reliability constraints, would an experienced principal-engineering team choose approximately these implementation boundaries, ownership rules, abstractions, data flows, and failure-handling mechanisms?**

This is **not** a code-style comparison and it does not mean Fulus should look literally identical to Google, AWS, Microsoft, Stripe, or another company.

There is no single correct implementation.

The comparison is about engineering judgment:

- responsibility boundaries;
- ownership;
- dependency direction;
- abstraction count;
- state-machine count;
- transaction boundaries;
- data representation;
- failure handling;
- testability;
- observability;
- operational simplicity;
- ease of reasoning by an engineer who did not write the code.

A green result means the implementation is consistent with strong engineering practice.

A yellow result means the implementation is defensible but a greenfield principal team might simplify, consolidate, or move responsibility.

A red result means the implementation creates a material correctness, maintainability, or reasoning problem and would likely be redesigned from scratch.

A white result means the choice is intentionally Fulus-specific and should not be judged by generic convention.

---

## 2. External engineering yardstick

The benchmark uses published engineering guidance rather than personal preference.

### Google engineering practice

Google's code-review guidance explicitly asks reviewers to evaluate design, functionality, and complexity, including whether code could be made simpler and whether another developer could understand and use it later. Google's guidance also emphasizes small, self-contained changes because they are easier to reason about and less likely to introduce bugs.

Google's SRE material treats simplicity as an end-to-end reliability concern: simple software is easier to understand, maintain, test, and repair. It also warns that systems naturally accumulate components and connections as they evolve.

**Benchmark implication:** Fulus should not merely work. The implementation should make its important decisions easy to locate and understand.

### Microsoft Azure Well-Architected

Microsoft's reliability guidance explicitly says to keep the architecture simple, avoid overengineering, keep the critical path lean, use platform capabilities, and develop just enough code. It also warns that excessively granular application code can create unnecessary interdependence.

Microsoft's broader design principles emphasize minimizing coordination and designing for evolution.

**Benchmark implication:** every coordinator, gate, adapter, state machine, cache, and abstraction must have a concrete invariant or business requirement it protects.

### AWS Well-Architected

AWS evaluates systems across operational excellence, security, reliability, performance efficiency, cost optimization, and sustainability. AWS guidance also recognizes that decomposition and distributed architectures introduce additional network, consistency, transaction, and operational complexity.

**Benchmark implication:** sophistication is justified only when it buys a required quality attribute.

### Android offline-first architecture

Android's official architecture guidance recommends a local data source for critical offline functionality, repositories that mediate data sources, local reads that do not wait for the network, and durable handling of writes when network access is unavailable.

**Benchmark implication:** Fulus' local database, repositories, durable outbox, and asynchronous synchronization are structurally appropriate.

### Fowler / established layering patterns

The repository pattern exists specifically to mediate between domain objects and persistence details. Presentation/domain/data separation remains a useful modularization technique when it reduces the scope of reasoning.

**Benchmark implication:** Fulus' separation between domain entities, repositories, local persistence, and remote APIs is directionally correct, but every additional layer must continue to reduce rather than increase cognitive load.

### Evolutionary architecture

Fitness functions are useful because architecture degrades when important characteristics are not continuously protected.

**Benchmark implication:** the implementation benchmark should become executable where possible rather than remaining a one-time review.

---

# 3. Executive result

## Verdict: 🟡 Strong implementation, but not yet what I would call a clean greenfield principal-team implementation

This is an important distinction.

**Fulus is not badly engineered.**

In several of the hardest areas, the implementation is better than a typical startup codebase:

- local-first persistence is real rather than cosmetic;
- business writes are transactionally grouped;
- the outbox is durable;
- sync has operation identity and retry semantics;
- server idempotency exists;
- canonical reconciliation exists;
- optimistic concurrency is considered;
- location/business authorization is enforced server-side;
- financial state is kept locally;
- lifecycle and process-death cases are explicitly considered;
- tests exist for difficult distributed-system invariants;
- the implementation has been repeatedly audited rather than merely feature-tested.

However:

> **The code shows evidence of evolutionary accumulation.**

A greenfield principal team given the requirements today would probably preserve most of the guarantees while changing several implementation boundaries.

The largest difference is not that they would choose a completely different architecture.

It is that they would probably make the same architecture **less historically layered, more type-directed, and more centralized around a small number of explicit domain boundaries.**

---

# 4. What a greenfield principal team would probably keep

## 4.1 Local SQLite/Drift source of truth — 🟢 KEEP

This is exactly the kind of implementation that fits Fulus.

The UI reads local state. Network synchronization is separate.

This follows Android's offline-first model and avoids turning the network into a rendering dependency.

**Assessment:** likely same implementation direction.

---

## 4.2 Repository boundary — 🟢 KEEP

Fulus has domain-facing repository interfaces and data implementations.

That is a normal and defensible boundary for an offline-first application where persistence is part of the product's behavior.

**Assessment:** likely same structural decision.

The warning is not to create repositories that merely forward calls without owning meaningful data behavior.

---

## 4.3 Transactional local business operations — 🟢 KEEP

The sale path correctly treats:

- sale;
- sale items;
- payments;
- inventory mutation;
- credit effects;
- outbox enqueue

as one local transaction.

That is a strong implementation decision.

A greenfield team would almost certainly protect the same invariant.

---

## 4.4 Durable outbox — 🟢 KEEP

Fulus does not treat "call the API after saving" as synchronization.

The durable queue is part of the local business transaction.

This is exactly the kind of implementation needed for process death, offline operation, and retry.

**Assessment:** very likely same design.

---

## 4.5 Stable operation identity and idempotency — 🟢 KEEP

Operation IDs, server-side idempotency, retry classification, and conflict records are appropriate.

A serious offline-first financial application needs these guarantees.

**Assessment:** likely same.

---

## 4.6 Canonical server reconciliation — 🟢 KEEP

The implementation does not assume that local state is automatically authoritative after synchronization.

It has explicit canonical fetch/apply paths and protects cursor acknowledgement from getting ahead of local application.

This is sophisticated but justified.

**Assessment:** likely same guarantee and roughly the same separation.

---

## 4.7 Server-side authorization — 🟢 KEEP

The implementation does not rely solely on local permission state.

Business, location, membership, device, and actor checks are represented on the cloud side.

**Assessment:** same principle and likely same enforcement boundary.

---

# 5. Where the implementation differs from an ideal greenfield implementation

## 5.1 Two state-management systems — 🟡 SIMPLIFY

Fulus uses both:

- Riverpod;
- flutter_bloc/Cubit.

The current split is understandable: most application state uses Riverpod while the Sell cart uses a CartCubit.

But the question is:

> If we started today, would we deliberately introduce two state-management ecosystems?

Probably not.

The CartCubit is legitimate stateful interaction logic. The problem is the **framework boundary**, not the cart itself.

A principal team would likely choose one of two approaches:

### Option A — standardize on Riverpod

Keep the cart as a stateful Riverpod notifier/provider.

### Option B — explicitly isolate Cubit

If Cubit is retained because it materially improves checkout state management, document it as the one intentionally isolated exception and prevent the pattern from spreading.

The current state is not a correctness defect.

It is an implementation-complexity finding.

**Decision: SIMPLIFY, not rewrite immediately.**

---

# 6. Sync implementation: the biggest implementation-level finding

## 6.1 The guarantees are strong — 🟢

The sync implementation contains real engineering mechanisms:

- durable queue;
- retry policy;
- dependency ordering;
- operation identity;
- actor attribution;
- execution lease;
- same-runtime serialization;
- cursor persistence;
- canonical reconciliation;
- optimistic concurrency;
- process-death replay;
- background execution;
- readiness handling.

These are not unnecessary in an offline financial application.

---

## 6.2 The number of coordination objects is high — 🟡

The current implementation includes distinct concepts such as:

- SyncService;
- SyncTriggers;
- SyncCycleRunner;
- SyncEngine;
- SyncExecutionLease;
- SyncRestoreReconciliationGate;
- SyncCoordinator;
- CloudSessionBootstrapCoordinator;
- CloudSyncBootstrapCoordinator;
- CloudSyncRecovery;
- EmployeeCloudSessionCoordinator;
- FulusConnectionState;
- additional recovery/readiness mechanisms.

Most of these have a reason.

The problem is the **combined cognitive surface**.

A new principal engineer reading the repository would need to construct a mental model of which object owns:

- lifecycle;
- readiness;
- bootstrap;
- execution;
- restore;
- recovery;
- exclusion;
- cursor state;
- cloud identity;
- business context.

The existing simplification audit correctly rejected indiscriminate extraction. That decision should remain.

However, the implementation benchmark says:

> **Do not add another coordinator unless it owns a genuinely different invariant that cannot naturally live inside an existing owner.**

This is a permanent guardrail.

**Decision: STRENGTHEN ownership documentation, then gradually simplify where real overlap is demonstrated.**

---

# 7. SyncEngine has one implementation smell that a greenfield team would likely remove

## 7.1 Entity-specific database knowledge inside the generic sync engine — 🟢 FIXED / VERIFIED

The historical sync engine contained legacy queue actor backfill logic that knew about:

- sales;
- cash drawer shifts;
- returns;
- customer ledger entries.

That knowledge was moved behind the injected `repairLegacyQueueActors` boundary in PR #164. The current `SyncEngine` invokes the callback but no longer contains the entity-specific repair implementation.

This is not a synchronization correctness failure.

But it is a boundary leak.

A greenfield implementation would more likely put legacy queue repair into:

- a migration;
- a SyncQueue repair component;
- or entity-specific queue metadata resolution.

The engine should primarily answer:

> "How do I execute durable synchronization?"

It should not increasingly answer:

> "How do I know the schema of every business entity?"

**Decision: KEEP. The generic engine boundary is now revalidated.**

Do not change behavior until equivalent tests are in place.

---

# 8. Money implementation is the clearest place where the greenfield answer is different

## 8.1 Current direction — 🟢

Local money as integer minor units is correct.

Explicit cloud conversion is correct.

The recent money-boundary work fixed the actual magnitude bug rather than patching Sell.

That is the right direction.

---

## 8.2 `typedef Money = int` remains a type-safety limitation — 🟡

The current type is:

`typedef Money = int`

This provides naming but not type safety.

More importantly, the boundary accepts:

- int;
- double;
- num;
- String.

That means a caller can still present monetary data in several representations and the parser decides what it means.

A principal team designing a financial domain from scratch would likely prefer something closer to:

- one canonical `Money` value object;
- integer minor-unit storage;
- explicit arithmetic;
- explicit formatting;
- explicit wire conversion;
- strict decimal wire parsing;
- no generic `num`/double acceptance at financial boundaries.

The important lesson is:

> **Money should be difficult to misuse, not merely documented correctly.**

This is directly relevant to the ₦300 → ₦30,000 defect.

**Decision: STRENGTHEN later with a value object if it materially reduces misuse; do not reopen the already-correct integer/wire architecture.**

---

# 9. The remote API adapter is more procedural than ideal

## 9.1 `FulusSyncApi.submitOperation()` — 🟡 STRENGTHEN

The operation submission method currently contains a substantial operation-type dispatch:

- sale;
- customer;
- repayment;
- expense;
- return;
- stock movement;
- location;
- income;
- cash drawer;
- employee;
- product;
- category;
- supplier;
- etc.

This is understandable because Fulus has one cloud sync endpoint.

However, as the operation list grows, this becomes a central switchboard.

A greenfield principal team would likely move toward typed operation commands or a registry/adapter table so that:

`operation type -> serializer -> endpoint contract`

is explicit and independently testable.

The goal is **not** to create one class per operation just for ceremony.

The goal is to prevent the central API client from becoming the place where every domain's wire contract accumulates.

**Decision: STRENGTHEN when touching this area; no emergency rewrite. Typed sync-operation serialization is already present, so the remaining procedural surface is narrower than the historical audit baseline.**

---

# 10. Raw SQL inside application coordinators — 🟡 STRENGTHEN

The employee cloud-session implementation uses direct `customStatement()` SQL for identity projection and permission/session reconstruction.

This can be justified for a cross-device restore boundary.

But from a greenfield perspective, raw SQL embedded in a high-level coordinator is a warning because it combines:

- authentication;
- authorization projection;
- cloud membership;
- database schema knowledge;
- restore;
- session reconstruction.

A cleaner implementation would put the database-specific projection behind a dedicated local identity/session repository or transactional importer.

**Decision: MOVE TOWARD A DEDICATED PERSISTENCE BOUNDARY.**

Do not replace working SQL merely to satisfy a style preference.

---

# 11. Bootstrap is doing a lot — 🟡 ACCEPTABLE BUT WATCH

`lib/app/bootstrap.dart` is a large composition root.

A large composition root is not automatically bad.

In fact, a single composition root is often preferable to dependency construction being scattered throughout the application.

The problem begins when the composition root starts containing business policy.

The current implementation has already moved significant lifecycle policy into dedicated coordinators.

That is the correct direction.

**Decision: KEEP the composition-root concept.**

Do not split bootstrap into dozens of artificial modules simply to reduce file length.

The benchmark rule is:

> Composition should be centralized; policy should not.

---

# 12. SharedPreferences as synchronization state — 🟡 REVIEW

Production sync cursors are persisted through DatabaseSyncCursorStore in SQLite. SharedPreferences remains only as a legacy migration/test adapter.

That is thoughtful.

But a greenfield principal team would likely ask whether critical synchronization acknowledgement belongs in the same durable transactional database as the outbox and local projections.

The strongest argument for SQLite is that:

- business state;
- outbox state;
- reconciliation state;
- synchronization acknowledgement

then share one durable persistence boundary.

This does **not** mean SharedPreferences is currently wrong.

It means it is a place where the implementation is more complicated because state is split across persistence mechanisms.

**Decision: KEEP. The production cursor now shares the SQLite durability boundary with local projections and the outbox.**

---

# 13. Domain/data separation — 🟢 STRONG

The domain entities are plain Dart and avoid Flutter/Drift/Dio dependencies.

That is exactly the kind of boundary a principal team would usually want.

It makes:

- domain testing;
- persistence replacement;
- remote protocol changes;
- UI changes

less coupled.

**Assessment: KEEP.**

---

# 14. Presentation layer — 🟡 MIXED

The UI is deliberately simple, but implementation state management is not completely uniform.

The primary screens combine:

- Riverpod providers;
- local streams;
- FutureBuilder;
- Cubit for Sell;
- repository calls;
- route-level lifecycle;
- permission projections.

The Instant UI contract is correct, but the implementation still has places where a developer must understand several asynchronous mechanisms.

A greenfield team would likely push toward:

`UI -> one local state abstraction -> repository -> local DB`

with background sync completely outside the rendering dependency graph.

Fulus is close, but not completely there.

**Decision: STRENGTHEN.**

---

# 15. Comments and documentation — 🟡 TOO HISTORICAL IN PLACES

One of the strongest signs of evolutionary code is comments that explain the history of how a bug was discovered.

Fulus contains many comments such as:

- "bug fix...";
- "round 2...";
- "this used to...";
- "new in schema...";
- "merge note...";
- detailed explanations of previous audit stages.

These comments are useful during active remediation.

But a greenfield principal team would generally prefer production code comments to explain:

> **why this invariant exists**

rather than:

> **what happened during the development history.**

Historical context belongs in architecture decision records, audit documents, or commit history.

The source should stay focused on the current invariant.

**Decision: GRADUALLY CLEAN UP.**

Do not delete important "why" documentation.

---

# 16. Test architecture — 🟢 STRONG, but should become more architectural

Fulus has unusually strong tests for difficult scenarios:

- process death;
- restore;
- multi-device convergence;
- cursor transaction boundaries;
- synchronization;
- financial fidelity;
- location behavior;
- canonical reconciliation.

This is a strong sign.

The next step is to turn the benchmark into **fitness tests** so future changes cannot quietly degrade the architecture.

Examples:

- domain layer cannot import Flutter;
- sync engine cannot directly depend on entity tables;
- money wire boundary accepts only canonical representations;
- UI routes cannot await cloud sync for first frame;
- server authorization remains mandatory;
- local business mutations enqueue durable outbox work atomically.

**Decision: STRENGTHEN.**

---

# 17. What I would NOT change

This benchmark specifically rejects several tempting rewrites.

### Do not replace SQLite/local-first with cloud-first CRUD.

That would make Fulus worse for its requirements.

### Do not introduce microservices.

The application does not need them merely to appear "enterprise."

### Do not introduce Kubernetes.

No requirement justifies it.

### Do not replace the durable outbox with direct network calls.

That would destroy offline/process-death guarantees.

### Do not remove execution leases.

Cross-runtime exclusion is a real invariant.

### Do not collapse all sync classes into one giant class.

That would reduce file count while increasing responsibility concentration.

### Do not remove repositories simply because they add a layer.

Repositories are useful when they isolate persistence and compose local/cloud behavior.

### Do not standardize state management blindly.

The goal is one coherent state model, not ideological purity.

---

# 18. Greenfield reconstruction

If I were designing Fulus today from a blank repository with the same requirements, I would probably build approximately this:

```
UI
 |
 | local state only
 v
Application / feature operations
 |
 v
Domain + typed business operations
 |
 v
Repository boundary
 |
 +-------------------+
 |                   |
 v                   v
SQLite / Drift     Sync Outbox
 |                   |
 +---------+---------+
           |
           v
     Sync Runtime
           |
     +-----+-----+
     |           |
   Push        Pull
     |           |
     v           v
 Fulus API   Change Feed
     |           |
     +-----+-----+
           |
           v
 Canonical reconciliation
```

With these explicit rules:

1. Money is a real domain type.
2. Local DB is the immediate business source.
3. Every business mutation has one transaction boundary.
4. Outbox intent is committed with the mutation.
5. Sync has one public application boundary.
6. Cross-runtime exclusion is one explicit primitive.
7. Restore has one maintenance boundary.
8. Server is authoritative for shared canonical state.
9. Authorization is enforced remotely.
10. UI never waits for cloud sync.
11. Feature state uses one primary state-management model unless a deliberate exception exists.
12. Wire contracts are typed and strict.
13. Domain code does not know infrastructure.
14. Sync infrastructure does not know individual business table schemas unless an adapter explicitly owns that translation.
15. Critical architectural guarantees are fitness-tested.

That is **very close to where Fulus is heading**.

The difference is that Fulus currently has more historical seams around this core.

---

# 19. Principal-team similarity score

This is not a mathematical industry score. It is an engineering assessment of structural similarity to what I would expect from a strong greenfield implementation.

| Area | Similarity | Assessment |
|---|---:|---|
| Offline-first architecture | 95% | Very likely same |
| Local database/source of truth | 95% | Very likely same |
| Repository boundary | 90% | Very likely same |
| Transactional sales | 95% | Very likely same |
| Durable outbox | 95% | Very likely same |
| Idempotent sync | 95% | Very likely same |
| Canonical reconciliation | 90% | Very likely same |
| Authorization boundary | 95% | Very likely same |
| Location isolation | 90% | Very likely same |
| Sync execution fencing | 85% | Same guarantees, possibly fewer surrounding objects |
| Restore implementation | 70% | Likely redesigned |
| Money implementation | 65% | Likely stronger typed boundary |
| State management | 70% | Likely standardized |
| API operation dispatch | 75% | Likely more typed/registry-driven |
| Raw SQL/application boundary | 70% | Likely better isolated |
| Sync engine/domain coupling | 75% | Likely cleaner |
| Bootstrap/composition | 85% | Similar, but possibly cleaner |
| Documentation/comments | 70% | Less historical detail in source |
| Overall implementation | **~82%** | Strong, but evolutionary |

The number should **not** be interpreted as "82% of the code is good."

It means the implementation's **engineering shape** is substantially aligned with what a strong team could plausibly build, with identifiable areas where a greenfield team would make different choices.

---

# 20. Most important conclusion

The audit does **not** say:

> "We built Fulus the wrong way."

It says:

> **We built most of Fulus the right way, but we built it through evolution rather than from a perfectly clean greenfield implementation.**

That distinction matters.

The hardest guarantees are largely in the right places.

The remaining problem is **implementation entropy**:

- multiple state mechanisms;
- many coordination boundaries;
- historical comments;
- some infrastructure knowledge leaking upward/downward;
- permissive money boundaries;
- mixed persistence for sync state;
- central protocol dispatch;
- some direct SQL in orchestration.

These are exactly the kinds of things a principal team would periodically remove.

---

# 20.5. Product location hydration boundary

The location-switch path previously called `ProductRepository.syncFromServer()`, which directly upserted both product catalog fields and stock levels from the inventory listing endpoint. That created a second authority for canonical product state outside the change-feed reconciliation path.

The implementation has now been narrowed:

- the operation is explicitly named `hydrateActiveLocationStockFromServer()`;
- it only hydrates the active location's stock projection;
- canonical product/catalog fields remain owned by `FulusSyncCoordinator` and `FulusProductCanonicalReconciler`;
- products absent from canonical local state are not created by the hydration path;
- pending local stock projections are never overwritten;
- regression tests prove the projection-only and pending-state behavior.

This is the preferred greenfield boundary: a targeted read-model hydration may exist when a location switch needs a snapshot, but it must not become a second synchronization authority.

# 21. Implementation benchmark priority list

## P0 — correctness and boundary integrity

1. **Money as a strict domain type**
   - eliminate ambiguous numeric wire representations;
   - reject integer monetary wire values;
   - keep explicit major/minor conversion at adapters;
   - expand end-to-end money fitness tests.

2. **Restore maintenance boundary**
   - make restore-vs-sync exclusion a true lifecycle invariant;
   - prove foreground/background/process-death behavior.

## P1 — implementation structure

3. **Remove domain knowledge from generic SyncEngine**
   - move legacy actor repair into SyncQueue/migration/entity adapter.

4. **Make sync operation serialization typed**
   - reduce central operation-type branching without introducing dozens of pointless classes.

5. **Isolate employee identity projection**
   - keep raw SQL inside a dedicated persistence boundary.

6. **Review sync cursor persistence**
   - decide whether SQLite should own acknowledgement state.

## P2 — simplification

7. **Decide the long-term state-management model**
   - standardize on Riverpod or explicitly constrain Cubit to checkout.

8. **Reduce overlapping coordination concepts**
   - only after ownership is proven through call-path analysis.

9. **Move historical explanations out of production source**
   - retain invariant/why comments.

10. **Turn implementation rules into automated architecture fitness tests.**

---

# 22. Permanent greenfield rule

Before adding any new implementation layer, answer:

1. What invariant does it own?
2. Why cannot an existing owner own it?
3. What failure does it prevent?
4. What complexity does it add?
5. What simpler design was rejected?
6. How is it tested?
7. How is it observed?
8. Can the database enforce the invariant instead?
9. Can an existing boundary enforce it instead?
10. Would we create this component if Fulus were a blank repository today?

If the answer to #10 is no, the default action is:

**Do not add it. Simplify instead.**

---

# 23. Final verdict

### Architecture
🟢 **Strong**

### Implementation correctness
🟢/🟡 **Strong, with P0 boundary work remaining**

### Implementation simplicity
🟡 **Good but historically accumulated**

### Greenfield similarity
🟢 **High**

### Would a principal team rewrite Fulus?
**No.**

### Would a principal team refactor parts of Fulus?
**Yes.**

### Would they preserve the core architecture?
**Almost certainly.**

### Would their code be literally identical?
**No, and that is not the right standard.**

### Would their code have roughly the same major boundaries and invariants?
**Yes.**

### Biggest difference
A greenfield team would likely arrive at essentially the same system with **fewer accidental seams and stronger types at the most dangerous boundaries.**

That is the implementation work Fulus should do next.

---

## Benchmark sources

- Google Engineering Practices — code review, design, complexity, small changes.
- Google SRE — simplicity and complexity as reliability concerns.
- Microsoft Azure Well-Architected — simplicity, minimizing coordination, business-driven design, failure analysis.
- AWS Well-Architected — operational excellence, reliability, security, performance, cost, sustainability.
- Android Developers — official offline-first architecture guidance.
- Martin Fowler — Repository and presentation/domain/data layering patterns.
- Thoughtworks — evolutionary architecture and fitness functions.

This document is an engineering benchmark, not a claim that any external organization would implement Fulus exactly this way.


## PR #179 — 2026-10-06 benchmark-hardening record

### Current disposition

| Priority | Finding | Disposition | Proof |
|---|---|---|---|
| P0 | build_runner syntax blocker in product repository | Fixed | Generated-code CI stage passed after removing the orphaned source tail |
| P0 | strict money validator missed flattened submit-operation sale tendered cash | Fixed in source; live proof added | `tendered_amount` is covered by the request validator, normalizers, migration, and live contract assertion |
| P0 | SQLite maintenance lease did not itself survive physical DB replacement | Fixed in source; cross-process proof added | Sidecar filesystem lock survives pathname replacement; child-process regression verifies blocked/unblocked states |
| P1 | active-location stock hydration could cross a lease-loss/network boundary | Fixed in source; regression added | Lease checked before page fetch and inside stock write transaction; test forces expiry during network wait |

This PR follows: **Inventory → Trace → Inspect → Prove → Classify → Fix → Test → Cross-check → CI → Record**.

The remaining Android/runtime evidence is explicitly not converted into a source-level green claim.


2026-10-06 — PR #179 cardinality hardening continuation

| P1 | Local cardinality invariants were repository-only | Fixed in source; CI proof pending | Schema v21 adds unique draft-cart-per-location and partial unique open-shift-per-location indexes with duplicate preflight; sequential/concurrent persistence regressions added |
| CI | Final fatal analyzer warning in restore regression | Fixed | Removed redundant `restoredDb!` assertion |

The benchmark now treats P05-002/P05-003 as source-fixed. Physical Android/runtime and production-configuration gates remain separate evidence items.


## 2026-10-07 — P3 readiness coordination revalidation

P3 was re-applied to the current `main` baseline after PR #183. The source-level change removes the redundant `SyncReadinessGate` state machine and makes `SyncService.ensureReady()` the explicit readiness-bootstrap boundary.

The remaining coordination objects are retained because each protects a distinct invariant: cycle serialization, connectivity-attempt coalescing, cross-runtime leasing, restore reconciliation fencing, or deferred recovery timing. This is a controlled simplification, not a coordinator-count reduction exercise.

**P3 result: 🟢 source simplification for the readiness cluster, pending CI verification.**
