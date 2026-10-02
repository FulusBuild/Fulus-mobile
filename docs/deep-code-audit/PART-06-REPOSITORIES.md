# Part 06 — Repository Layer Audit

**Part:** 06 — Repository Layer  
**Baseline SHA:** 9f13ada061f79c2c3e2527de108855302202f9b3  
**Audit branch:** audit/deep-code-part-06-repositories

## Scope

Audited repository interfaces and representative implementations across customer, supplier, category, product, sales and draft carts, employees/access, expenses/income/tax, stock movements, cash drawer, canonical reconciliation, sync queue integration, transaction boundaries, and local-write-first behavior.

## Findings

### No new standalone high-confidence defect

The repository layer consistently uses local-first writes and durable sync enqueueing for primary syncable business mutations. Representative create/update paths place the local row write and queue insertion in one Drift transaction.

Canonical reconciliation methods generally resolve server identities to local identities, persist server-authoritative state, and avoid creating outbound queue work.

Sync completion methods use operation identity plus newer-mutation checks before changing a row from pending to settled, preventing stale network responses from incorrectly settling newer local mutations.

### P06-CROSS-001 — Repository-owned cardinality races

Status: Cross-referenced to P05-002/P05-003; no duplicate finding created.

DraftCartRepositoryImpl.getOrCreateDraftCart() performs a read followed by insert, and CashDrawerShiftRepositoryImpl.openShift() performs an active-row read followed by insert. Part 05 already established that the database lacks uniqueness constraints for these invariants.

Part 06 confirms these are repository-level race surfaces, but the durable fix belongs in the persistence schema plus repository regression tests.

### P06-CROSS-002 — Product uniqueness migration can leave repositories without DB protection

Status: Cross-referenced to Part 05 migration weakness / Part 08 catalog audit.

Product SKU/barcode lookup and import validation are application-level defenses. The schema migration for legacy databases intentionally catches duplicate-index creation failures and continues without the unique index. That preserves legacy data but leaves that installation without the intended DB-level uniqueness guarantee.

No automatic duplicate merge was applied because product identity reconciliation can alter stock/catalog references and must be policy-driven.

### P06-CROSS-003 — Canonical reconciliation concurrency requires broader convergence testing

Status: Deferred to Parts 14/16.

Canonical repository methods are designed as upserts keyed by server identity, but several implementations perform identity lookup before entering their persistence transaction. Correctness therefore depends on the sync engine not concurrently applying the same canonical entity through multiple paths.

This was not converted into a confirmed production defect because server IDs are intended to be stable identities, sync delivery is centrally coordinated, several tables have uniqueness protections, and a complete proof requires tracing all change-feed and push-response reconciliation paths together.

Part 16 should explicitly test duplicate/concurrent canonical delivery and prove that two devices converging on the same server entity cannot produce duplicate local rows.

## Repository correctness checks

### Local write + queue atomicity

Confirmed for representative syncable repositories: Customer, Employee, Category, Supplier, Expense, Income, Sale, and Cash drawer. The common pattern is a Drift transaction containing the local mutation and durable SyncQueue insertion.

### Stale sync completion protection

Confirmed across multiple repositories: markSynced checks the current queue operation and calls hasNewerQueueMutation before settling the row.

### Location-scoped repositories

Confirmed for location-sensitive operational data such as expenses, stock movements, sales, product stock, and cash drawer shifts.

Business-wide data such as customers/categories/suppliers intentionally lacks a location predicate where the domain model defines those entities as business-wide.

### Employee access

EmployeeRepositoryImpl explicitly checks Permission.manageEmployees before roster mutations. Its local identity linkage uses authUserId for the device-local login account and keeps cloudUserId/membershipId separate, consistent with the Part 02 identity separation and Part 03 membership model.

## Important handoffs

- Part 05: enforce one active draft cart and one open cash-drawer shift at the DB layer after safe duplicate-data migration policy is established.
- Part 08: cross-check legacy product SKU/barcode duplicate handling and whether skipping the unique index is acceptable for every supported upgrade path.
- Part 10: resolve all REAL-backed monetary repository/domain boundaries as part of the coordinated integer-money migration.
- Part 14: verify queue/repository atomicity against sync engine failure/retry semantics.
- Part 16: prove concurrent canonical reconciliation cannot duplicate local identities.
- Part 20: cross-check repository-level authorization against server action authorization.

## Definition of done

- [x] Repository inventory and representative implementations inspected
- [x] Local-write-first transaction patterns cross-checked
- [x] Queue atomicity cross-checked
- [x] Stale completion protection cross-checked
- [x] Location/business scoping cross-checked
- [x] Canonical reconciliation boundaries reviewed
- [x] Cross-part findings recorded
- [ ] Full repository-by-repository mutation matrix completed by later targeted parts
- [ ] Concurrency/runtime evidence
- [ ] CI for audit documentation

Conclusion: No new standalone confirmed defect was introduced in the findings ledger by Part 06. The repository audit strengthens and localizes the existing persistence/convergence handoffs rather than justifying another speculative rewrite.
