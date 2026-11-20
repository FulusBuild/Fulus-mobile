# Part D — Catalog and Products

**Status:** Source fixes and focused local automated checks complete; device walkthrough, live mutation/convergence, and migration execution remain open
**Audit date:** 2026-11-19  
**Repository:** FulusBuild/Fulus-mobile  
**PR baseline:** current main at e7f8ccad6c89877fb68a5b8edfdbce693d760414  
**Audit checkout:** codex/part-d-catalog-products, initially based at f2d9424; catalog/product files were compared with current main and had no intervening changes.  
**Runtime:** Flutter 3.44.9, Windows; physical Android device was not attached for this audit.

## Scope and evidence

Reviewed product/category creation and editing, list/search/detail, SKU and barcode generation/lookup, archive, prices and units, initial stock, stock tracking, CSV import and review, photo capture/upload/clear, local Drift constraints and transactions, outbox handlers, catalog Edge Function/RPC, Postgres policies/indexes, and canonical reconciliation. Traced:

add/edit/import → validation/use case → repository transaction → product + stock projection + outbox → product/photo sync handler → fulus-api → cloud_catalog_mutate → products/stock/storage → canonical pull → local projection

Categories remain business-wide, while products and product SKU/barcode identity are location-scoped. Stock quantity is a separate per-location projection. Product photos use a device path while pending upload, then a public Supabase Storage URL in the canonical product row.

Evidence layers are kept separate below. No real product, inventory, category, or image was created or changed.

## Findings and changes

### D-001 — CSV SKU validation disagreed with uniqueness constraints

**Severity:** Medium
**Status:** Fixed in source; regression tests pass.

CSV prevalidation compared SKU strings case-sensitively, while the local repository and both local/cloud unique indexes compare SKU case-insensitively within a location. A CSV row such as rice-5kg could pass review against existing RICE-5KG, then fail during persistence. Case-variant duplicates within one file could also pass preview.

**Fix:** Normalize existing and in-file SKUs for validation and generated-SKU collision checks. Barcode matching stays exact to match the stored barcode constraints.

**Regression evidence:** Tests cover an existing case-variant SKU and case-variant duplicates within a single CSV.

### D-002 — Product stock-tracking choice was not canonical

**Severity:** Medium
**Status:** Mobile source and migration prepared; production migration not applied.

tracks_stock already existed in Postgres and the local schema, but product create/update payloads and canonical reconciliation omitted it. Disabling stock tracking on one device could therefore revert to the server default on another device or after a pull.

**Fix:** Carry tracks_stock through product drafts, create/update payloads, repository writes, DTOs, and canonical reconciliation. Add 20261119091000_sync_product_stock_tracking_flag.sql to extend the catalog RPC and supabase/tests/catalog_invariants.sql to assert create and update support.

**Regression evidence:** Local create/update repository tests, product sync serialization, and canonical reconciliation tests cover false. The SQL invariant script has not been run against a local Supabase stack or production.

### D-003 — Cloud barcode uniqueness was not enforced

**Severity:** Medium
**Status:** Migration prepared; production migration not applied.

The local repository and SQLite enforce one nonblank barcode per active product/location. The deployed Postgres schema had only a non-unique barcode lookup index, so two devices could concurrently create products with the same barcode and both cloud writes could succeed.

**Fix:** Add 20261119090000_enforce_location_scoped_product_barcode_uniqueness.sql, a partial unique index on (business_id, location_id, barcode) for active, assigned-location, nonblank values. A read-only production aggregate check on 2026-11-19 returned zero duplicate groups / zero products in duplicate groups; no barcode values or product rows were selected.

**Verification gap:** The index has not been applied. The SQL invariant script checks its presence and definition after migration reset. Run the migration and SQL check in CI/local Supabase before merging; production remains unchanged.

### D-004 — Invalid optional product numbers silently became defaults

**Severity:** Medium
**Status:** Fixed in source; widget validation regression passes.

The add/edit screen turned an invalid cost into zero, an invalid threshold into 10, and invalid starting stock into zero. This could silently save a different catalog or inventory value than the user entered. The form also accepted a non-finite selling-price parse as valid.

**Fix:** Reject non-finite/negative cost and selling prices, and invalid/negative whole-number thresholds or starting stock with field errors. When stock tracking is disabled, starting stock is not seeded.

**Verification:** A widget test enters invalid cost, threshold, and starting stock values and verifies field errors. Targeted Flutter analysis reports no issues.

### D-005 — Replacing or clearing photos leaves old public objects

**Severity:** Medium; cleanup implementation remains open.

Uploads use immutable timestamped object paths. Product edits can replace/clear photo_path, but the client does not delete the previous object; the current Storage policy permits catalog-manager inserts, not deletes. The bucket is public for reads. Old objects can accumulate and remain accessible at their previous URLs. **Decision:** keep the insert-only client policy and implement a server-authorized collector that deletes only unreferenced product images older than a 30-day grace period. Keep soft-deleted product references protected. No server cleanup path was added because the local Supabase stack is unavailable for validation.

### D-006 — Product catalog had no export path

**Severity:** Medium
**Status:** CSV export implemented; automated serialization regression passes.

**Fix:** Stock actions now export the current location's products as a CSV containing catalog identifiers, price, stock, unit, threshold, and stock-tracking flag. Monetary values use major-unit decimal representation and the existing CSV serializer handles spreadsheet formula escaping. The export uses the existing platform share service.

**Verification:** `product_catalog_csv_test.dart` verifies the stable header and row values. Android share-sheet behavior remains unverified on a physical phone.

## Trace notes

- **Create:** Product and initial ProductStockLevels row are written in a local transaction with a product-create outbox task. The cloud create carries one owner location and initial quantity; the RPC inserts the product and seeds stock/movement under the same idempotent operation. Photo upload is a separate low-priority task.
- **Edit:** Product changes are local-first and enqueue an update. SKU/barcode prechecks are location-scoped; schema constraints close local concurrent-write races. The cloud RPC locks the product row and uses optimistic concurrency for stale updates.
- **Archive:** Local archive sets deleted_at and is_active=false, queues an update that becomes catalog delete; cloud soft deletion is returned canonically. Soft-deleted identifiers are reusable.
- **Stock tracking:** Fixed by this Part D change; existing server column had been omitted from mutation and reconciliation contracts.
- **Search/scan:** Local search covers name, SKU, and barcode. Barcode lookup is location-scoped. Scanner and camera behavior were source-inspected only.
- **Import:** Fixed-header CSV parser validates rows, resolves/creates category/supplier names, then creates each product independently and queues normal sync. A category or supplier created for a row can remain if a later product write for that row fails; the import is intentionally row-partial, but these ancillary writes are not atomic with the product. Import uses the current active location.
- **Money:** Product prices are stored locally in integer minor units and serialized to major-unit cloud strings through the existing money wire contract.

## Supabase production inspection — read-only

Project bejcuvoxemwomcatgyxz (“Fulus backend”, eu-west-1) was active and inspected through deployed migration metadata, index/policy/bucket metadata, advisory summaries, and an aggregate duplicate-barcode check. No business rows were returned and no production data/schema was changed.

- Product and category RLS policies exist; catalog writes flow through fulus-api and the service-role catalog RPC, which binds user/device/business and checks catalog.manage plus product location access.
- The deployed product indexes included the location-scoped case-insensitive SKU unique index and a non-unique barcode index. The new barcode unique index is source-only until its migration is applied.
- product-images is public-read with a 5 MiB object limit. The live Storage policy permits catalog-manager inserts; no product-image deletion policy exists.
- Security Advisor returned the two existing service-only/no-client-policy INFO notices for unrelated tables and a WARN for disabled leaked-password protection. Performance Advisor reported unused indexes, including the non-unique product barcode lookup index; no Health notices were returned. These general advisories were not treated as Part D defects.

## Automated verification

**Tool:** Flutter 3.44.9, Windows host. Repository package configuration was used with --no-pub; build_runner generated ignored local source outputs needed by this clone. Git safe-directory was configured for the Flutter SDK only in the test process; no global Git configuration was changed.

Exact command (PowerShell; Git safe-directory environment variables scoped to the process):

    flutter test --no-pub test/unit/product_import_engine_test.dart test/unit/import_products_from_csv_test.dart test/repository/product_repository_test.dart test/repository/product_photo_repository_test.dart test/sync/product_sync_handler_archive_test.dart test/sync/product_photo_sync_handler_test.dart test/sync/fulus_product_canonical_reconciler_test.dart test/sync/fulus_category_canonical_reconciler_test.dart test/data/local/database/products_schema_test.dart

**Result:** 105 tests passed; 0 failed; 0 skipped; approximately 20 seconds. This is local automated evidence, not end-to-end, phone, or live backend mutation evidence.

**Follow-up UI regression coverage:** `test/features/stock/add_edit_product_validation_test.dart` verifies invalid cost, threshold, and initial-stock errors; `test/domain/usecases/product_catalog_csv_test.dart` verifies product CSV header/row values. Both passed in the 63-test expanded suite recorded in [Part E](PART-E-INVENTORY-AND-SUPPLIERS.md).

**Generation:** flutter pub run build_runner build succeeded (519 outputs on the incremental run). Drift emitted existing duplicate-reference-name warnings for stockMovementsRefs and userPermissionsRefs. Generated outputs are ignored and not part of the change.

## Remaining verification

- Run supabase/tests/catalog_invariants.sql after a clean local Supabase migration reset and validate the migration chain. Do not apply schema changes to production as part of this audit.
- No local Supabase CLI, Docker, or psql executable was available in this environment, so migration-chain execution was not possible here.
- Verify cloud product create/update and two-device canonical convergence with a designated QA business, including barcode uniqueness rejection and tracks_stock=false.
- Walk the product/category/import/photo flows on a physical Android phone; record Android/API/build and permission outcomes. Camera, barcode scanner, file picker, offline/restart, and upload retry were not device-tested.
- Exercise import/export against synthetic data on Android, including the platform share sheet and duplicate/race/failure cases.
- Implement the decided 30-day server-side orphan-photo collection and verify it against a local Supabase stack; preserve objects still referenced by active or archived products.
- This evidence does not establish release readiness or suitability for millions of users.

## Documentation disposition

- Added this current Part D report and linked it from the canonical campaign/index.
- Retained docs/deep-code-audit/PART-08-PRODUCT-CATALOG.md as historical evidence. Its business-wide SKU/barcode description and photo-local-only statements are explicitly superseded by current source and this report; no unique historical evidence was deleted.
- Retained other historical Part 08 cross-references and ledgers; no unrelated historical document was removed.
