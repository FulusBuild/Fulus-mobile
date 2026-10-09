# Location-Owned Products, Customers, and Employees

## Requirement

Products, customers, and employee roster records belong to one location. Switching the active location must switch the records available for browsing, selection, mutation, restore, and synchronization. This is an ownership boundary, not a presentation-only filter.

## Source-backed baseline (main, 2026-10-09)

- `lib/data/local/database/tables.dart`: Products has no `locationId`; stock is separately keyed by product and location. Its comments explicitly define catalog fields as business-wide.
- `lib/domain/entities/product.dart`: ProductDraft carries `locationId`, but Product does not. `lib/sync/handlers/product_sync_handler.dart` chooses one initial stock row to send during product creation.
- `lib/data/repositories/product_repository_impl.dart`: product streams join the business-wide catalogue to stock for the selected location. That can expose another location's product with a zero/missing stock projection.
- `lib/data/local/database/tables.dart` and `lib/domain/entities/customer.dart`: customers have no location field and are explicitly documented as business-wide.
- `lib/data/repositories/customer_repository_impl.dart`: customer list/get/create/update/archive paths have no active-location constraint.
- `lib/features/sell/presentation/widgets/customer_picker_sheet.dart`: checkout obtains customers without a location argument.
- `lib/data/repositories/employee_repository_impl.dart` and `lib/features/more/employees/presentation/screens/employees_list_screen.dart`: employee streams are not scoped by active location.
- `supabase/migrations/202609120007_core_business_domain_baseline.sql`: cloud products/customers have business_id but no location_id; stock and sales are location-scoped.
- `supabase/migrations/20260930100000_employee_roster_sync.sql`: cloud employees have nullable location_id; employee RLS/change-feed handling permits null-location roster rows.
- `supabase/functions/fulus-api/index.ts`: catalog list and sync change-feed currently treat product/customer records as global/business-wide.

## Non-negotiable data-safety rules

1. Never assign a legacy product or customer to a location based on an arbitrary row, current active location, timestamp guess, or first-match result.
2. Preserve existing sale, sale-item, customer-ledger, repayment, refund, stock-movement, and audit references. Historical records must not be silently reparented or deleted.
3. A migration must classify legacy rows as uniquely attributable, shared/ambiguous, or unassigned before applying ownership. Ambiguous rows must be surfaced and handled explicitly; do not pretend the migration can infer intent.
4. The API must validate that a requested location belongs to the selected business and that the actor/device is allowed to access that location. Client filtering alone is not isolation.
5. A location switch must not mutate stock or silently transfer ownership. Location ownership and stock quantity are separate concepts.
6. Employee account authentication and business membership remain separate from the location-owned employee roster row. Do not break invite/claim, role permissions, or employee restore.
7. Keep offline-first/outbox behavior, operation idempotency, money wire conversions, and snapshot consistency intact.

## Implementation sequence

1. **Inventory and contract tests:** map every read/write/sync/restore/RPC/change-feed path for products, customers, and employees; identify product and customer foreign-key/ledger dependencies and current legacy-data shapes.
2. **Local domain and persistence:** add explicit location ownership to Product and Customer; make employee location required for active roster records; implement a versioned SQLite migration that preserves history and safely classifies old rows. Update generated Drift/JSON code via the repository's normal build_runner workflow.
3. **Repository/UI scoping:** require location context for list, get-by-id, barcode/SKU lookup, create/update/archive/restore, checkout customer picker, product picker, employee list, and any customer-credit/history surface. Ensure ID-based operations cannot mutate a record owned by another location.
4. **Cloud contract:** extend catalog/customer mutations and responses with location_id; add server-side location validation; enforce unique/idempotent location-owned records; update RLS/service-role wrappers, sync feed visibility, and restore snapshots. Do not make a client-only filter the security boundary.
5. **Historical compatibility:** retain existing IDs where safely possible. For legacy shared products/customers referenced by records from multiple locations, preserve historical foreign keys and use an explicit migration/reconciliation strategy rather than unsafe automatic reassignment.
6. **Regression proof:** test two-location isolation, location switching, offline create/retry/replay, two-device convergence, employee invite/claim/restore, historical sales and credit ledger references, and denied cross-location API operations.
7. **Verify and record:** run formatting, code generation, static analysis, unit/widget/integration tests, Supabase migration tests, multi-device E2E, and CI. No merge while required checks are red.

## Acceptance criteria

- Location A cannot list, search, select, update, archive, restore, or sell Location B's product/customer records.
- A product/customer created offline in A remains owned by A after retry, restart, restore, and another device's sync.
- Employee roster views and employee-specific restore include only the assigned location's roster records; account/membership authorization continues to work.
- Location-scoped cloud reads and writes reject unauthorized location IDs even if a client bypasses UI filters.
- Historical sales, returns/refunds, credit ledger, stock movements, and audit history remain readable and internally consistent.
- No money conversion, sync cursor, idempotency, or restore-snapshot invariant is weakened.
