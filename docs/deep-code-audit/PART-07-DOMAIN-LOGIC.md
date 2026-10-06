# Part 07 — Domain & Business Logic

**Status:** Complete for source-level audit; one concrete cross-layer finding deferred to Parts 09/10.
**Baseline SHA:** 5011b01fe57b728b2635ca9fa61a432b46047093
**Audit branch:** audit/deep-code-part-07-domain-business-logic

## Scope

Audited the pure-domain entities, DTOs, use cases/engines, core business-engine calculations, and their important callers/tests. The review focused on deterministic rules, arithmetic, validation, state transitions, null/default semantics, and consistency with local persistence and the Supabase sale contract.

## Inventory

### Domain entities

Inspected products/catalog; sales, sale drafts, sale payments and canonical sale state; returns; stock movements; customers and ledgers; cash drawer shifts; expenses/income/tax; employees/permissions; locations/business settings; and receipt/report/dashboard/search/import support.

### Domain use cases/engines

Inspected ResolveActiveLocation, SwitchActiveLocation, DashboardEngine, HomeAttentionEngine, EmployeeEngine, ProductImportEngine, ReceiptEngine, ReportsEngine, plus backup/search/import/reporting engines where business rules are domain-owned.

### Cross-system traces

Representative traces covered draft cart → aggregation → SaleDraft → SaleRepositoryImpl.createSale; sale arithmetic → local Drift → durable sync → create_sale_atomic; employee validation → repository; active location → session projection; product import validation → repository; receipt calculations → rendered output.

## Finding P07-001

**Severity:** High  
**Status:** Deferred to Parts 09/10  
**Files:** sale.dart, sale_draft.dart, draft_cart_aggregation.dart, draft_cart_repository_impl.dart, migration 20260913100000_service_role_sale_sync_actor.sql

**Observed behavior**

The local sale model computes total as subtotal - discount + tax without enforcing that discount is no greater than subtotal. The normal draft-cart path prevents negative discounts, but setWholeCartDiscount only checks discount >= 0 and does not cap the whole-cart discount against the current cart subtotal. A sufficiently large whole-cart discount can therefore produce a negative local Sale.total.

Local Sale.amountPaid can also exceed Sale.total. The current receipt/business logic exposes that as changeDue, while the cloud sale transaction clamps the authoritative paid amount to the total and clamps the total itself to zero. Local and authoritative cloud representations can therefore differ after synchronization.

**Expected invariant**

The local business model and authoritative cloud model must agree on the financial meaning of total and amountPaid, or explicitly model the difference, such as tendered cash versus amount applied to the sale. A sale should never expose a negative payable total, and an overpayment/change workflow must not rely on a field whose cloud representation silently clamps it.

**Root cause**

The domain model permits unconstrained double arithmetic while the cloud transaction applies normalization/clamping rules. The checkout path validates individual cart inputs but does not establish one canonical invariant at the domain boundary.

**Impact**

An excessive discount can create an impossible negative local total. Overpayment can show change locally while the synced sale's authoritative amount_paid is capped, creating a local/cloud representation difference that later canonical reconciliation must resolve.

**Evidence**

SaleDraft.total directly computes subtotal - discount + tax. DraftCartRepositoryImpl.setWholeCartDiscount rejects only negative discounts. create_sale_atomic explicitly clamps total to >= 0 and paid to [0,total]. Existing sale tests cover overpayment/change behavior but do not prove local/cloud semantic equivalence.

**Fix**

Do not patch this piecemeal in Part 07. Parts 09 and 10 should first decide whether amountPaid means applied payment or tendered cash, represent change/tender separately if required, define the canonical integer monetary unit, make local and cloud arithmetic follow the same invariant, and add exact regression tests before migration.

## Other audit results

No additional standalone high-confidence domain defect was found.

Verified or cross-referenced: sale payment status/balance/change calculations; stock movement request shapes; return status transitions; employee validation and leave transitions; product-import duplicate/numeric validation; employee location resolution; serialized location switching; dashboard/home attention ordering; receipt formatting; retrospective report insights.

## Cross-part references

P05-001 / X-005: historical REAL monetary storage has been migrated to INTEGER minor units; source invariant is closed and runtime upgrade/convergence evidence remains.
P05-002 / X-006: draft-cart cardinality remains a persistence/repository concern.
P05-003 / X-006: cash-drawer cardinality remains a persistence/financial concern.
P07-001 must be resolved together with Sales & Checkout (Part 09) and Financial & Ledger Integrity (Part 10).

## Tests reviewed

test/unit/sale_test.dart; test/unit/employee_engine_test.dart; test/unit/product_import_engine_test.dart; test/unit/cash_drawer_state_test.dart; draft-cart aggregation tests; sale/draft-cart repository tests; offline sale and sale sync tests.

No production code was changed in Part 07 because the confirmed arithmetic mismatch requires a coordinated checkout/financial design decision rather than a safe isolated patch.

## Remaining uncertainty

Device-level checkout evidence for overpayment/change behavior remains part of the later Sales/Financial audit. Production database/runtime verification remains pending for previously recorded cross-cutting findings. Exact integer-money migration compatibility will be established in Part 10.

## Handoff

Next: Part 08 — Product & Catalog.
Known owner of P07-001: Parts 09 and 10.