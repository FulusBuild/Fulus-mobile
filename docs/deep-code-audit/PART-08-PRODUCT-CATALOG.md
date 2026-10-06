# Part 08 — Product & Catalog

**Status:** Complete for source-level audit; no new standalone high-confidence production defect requiring a Part 08 code fix.
**Baseline SHA:** ea7adc295e15cff0b776c39f3ca257a149ffa4a7
**Audit branch:** audit/deep-code-part-08-product-catalog

## Scope

Audited products, categories, suppliers, pricing, SKU/barcode identity, stock relationship, archive/delete behavior, image synchronization, imports, canonical reconciliation, and catalog cloud mutation/OCC paths.

## Structural inventory

Reviewed Product/Category/Supplier entities and DTOs; ProductRepositoryImpl, CategoryRepositoryImpl, SupplierRepositoryImpl and mappers; catalog API endpoints; product image API; product/category/supplier sync handlers; canonical reconcilers; product import engine/use case; Drift catalog tables/indexes; catalog migrations; and focused repository/sync/import tests.

## Deep verification

### Product identity and uniqueness
Product SKU and barcode are treated as catalog-wide identifiers on the local device. Create/update checks exclude soft-deleted rows. Schema version 6 adds partial unique indexes for active SKU/barcode, providing database-level protection in addition to repository checks. The existing migration deliberately preserves legacy duplicate data rather than destroying it; this remains cross-referenced with the Part 05 migration-weakness note.

### Category and supplier relationships
Products store category/supplier references separately from per-location stock. Canonical reconciliation resolves server IDs to local IDs before writing the product. Unknown referenced locations in canonical stock state are rejected rather than silently creating an unscoped stock row.

### Pricing
Create/update paths reject selling prices <= 0 and cost prices < 0. The broader financial representation issue remains P05-001/P07-001 and is intentionally owned by Part 10 rather than duplicated here.

### Archive/delete
Product archive is a soft delete: isActive=false, deletedAt is populated, and one durable update is queued. Product sync handles pre-sync archive, already-synced archive, and create-then-archive sequencing. Canonical deletion marks the local product inactive/deleted without generating outbound work.

### Stock relationship
Catalog identity is separated from location stock. Product canonical reconciliation deletes stale local stock-level rows and restores exactly the authoritative stock snapshot inside the same local transaction. Initial stock creation is coupled to the cloud catalog mutation and uses an idempotent inventory movement operation.

### Images
Product image upload is now part of create/update synchronization and the cloud URL is persisted in the canonical product row. Storage policies scope authenticated access to the business prefix. Image lifecycle cleanup is not independently modeled as a catalog invariant; stale storage objects may therefore require later storage-retention work, but source inspection did not establish user-visible catalog corruption from this.

### Imports
CSV validation covers required headers, malformed values, duplicate SKU/barcode cases and row-level errors. Category/supplier name resolution reuses existing entities rather than intentionally creating duplicates in the import path.

### Cloud mutation and concurrency
The catalog mutation function requires catalog.manage, validates active registered device ownership, uses idempotency keys, binds request hashes to operation IDs, and serializes updates to the same catalog row before checking the sync cursor. Product initial-stock location is validated against the target business.

## Cross-cutting findings / known risks

- **P05-001 / X-005:** product cost/selling price are now INTEGER minor units in the current SQLite schema; runtime upgrade/convergence evidence remains.
- **P05 migration weakness:** legacy product SKU/barcode duplicates can leave a device without the DB uniqueness index if the migration intentionally skips index creation. This was already recorded in Part 05 and is not duplicated as a new Part 08 finding.
- **P03/P04/X-003/X-004:** catalog visibility and mutations still depend on the broader employee/business/location authorization chain; no additional catalog-specific bypass was proven in this pass.
- Category and supplier create operations lack server idempotency keys according to the existing endpoint contract. This is a documented backend limitation in the source and is a Part 13/API concern, not a new Part 08 finding.

## Tests reviewed

- test/repository/product_repository_test.dart
- test/sync/fulus_product_canonical_reconciler_test.dart
- test/sync/product_sync_handler_archive_test.dart
- test/unit/product_import_engine_test.dart
- test/unit/import_products_from_csv_test.dart
- category/supplier sync and canonical reconciler tests
- product schema/migration tests
- supplier credit repository tests
- relevant catalog API/sync handler tests

## Fixes

No production-code fix was justified in Part 08. Existing catalog invariants have already received targeted fixes in prior parts/migrations, and the remaining risks require coordinated ownership in Parts 10, 13, and 16 rather than isolated changes here.

## Remaining uncertainty

- Production catalog data should be sampled later for pre-existing SKU/barcode duplicates before relying on the partial unique indexes on every legacy installation.
- Storage-object retention for replaced/archived product images should be addressed if the product-image feature requires strict orphan cleanup.
- Runtime multi-device catalog conflict behavior remains part of Parts 13/14/16.

## Handoff

Next: Part 09 — Sales & Checkout.
P07-001 local/cloud sale arithmetic is the primary known dependency entering Part 09.