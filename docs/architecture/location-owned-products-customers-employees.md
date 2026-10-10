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


## PR #211 implementation status (2026-10-09)

### Implemented and verified on the current PR head

- Added location ownership to local and cloud product/customer records while retaining nullable ownership for unresolved legacy records.
- Added a server-side review table that classifies ambiguous or unassigned historical products/customers without guessing an owner.
- Added location authorization and immutable-owner guards to catalog/customer mutations, plus transaction-reference guards for sales, stock levels, inventory movements, returns, and customer ledger entries.
- Scoped product reads, search, customer reads/credit operations, employee roster reads, and return reads/mutations to the active location. Product, sale, stock-movement, and customer-credit mutations fail closed without a valid active location.
- Preserved durable outbox replay across location switches. Return sync explicitly uses the original queued return, while user-facing return reads remain location-scoped.
- Scoped employee restore to the assigned location. Legacy shared/unassigned customers referenced by a location's historical sales are represented by masked placeholders; sale-linked ledger history is retained only for the sale's location.
- Added regression coverage for active-location read/write guards, historical ledger restore isolation, and migration/authorization contracts.

Current-head verification:
- Fulus Mobile CI passed on the current PR head.
- Supabase Migration Chain passed a clean schema rebuild and its location authorization, repayment, financial fidelity, employee restore, cloud API authorization, and database security contract tests.
- The PR's live production sync and multi-device jobs are skipped in pull-request CI; their success must not be inferred from these green local checks.

### Explicit remaining blockers before merge

1. **Legacy ownership review workflow:** the service-role-only transactional resolution RPC and owner/admin-gated API actions to list and resolve pending reviews are implemented. Regression tests cover denial for a non-admin, rejection of a cross-business location, successful explicit product/customer assignment, reviewer recording, and replay rejection. The in-app review UI and end-to-end API authorization exercise are still missing. Do not assign legacy rows automatically.
2. **Two-location, two-device convergence proof:** add/run an end-to-end scenario proving that a product/customer created offline in Location A remains owned by A after retry, restart, restore, and another device's sync, and that a Location B actor cannot read or mutate it. Pull-request CI has not run the production multi-device workflow.
3. **Employee journey:** SQL restore-isolation contracts pass, but the full invitation/claim, sign-in, reinstall/restore, and role-permission journey still needs end-to-end verification.
4. **Production rollout:** the new migration and Edge Function changes have not been deployed to production from this draft PR. Do not merge or deploy until the remaining acceptance criteria and required runtime evidence are satisfied.

Keep PR #211 as a draft until these blockers are closed and the exact final head has green CI plus the required runtime evidence.


## Follow-up verification note (2026-10-10)

- Fixed a cloud API contract mismatch: the `catalog_list` handler already required `location_id` and applied location authorization/filtering for customers, but the shared entity allowlist rejected `customers` before that path could run. Customer reads are now admitted only for `catalog_list`; generic catalog mutations still reject customers and continue using the dedicated customer mutation RPCs.
- Added a source contract assertion in `supabase/tests/cloud_api_authorization_contracts.sh` so this mismatch is caught by CI.
- The follow-up ownership-review implementation adds owner/admin-gated API actions for listing pending reviews and resolving one to an explicitly selected active location, backed by a service-role-only transactional RPC. The SQL authorization test now covers successful resolution for both products and customers, rejects cross-business assignment and non-admin resolution, records the reviewer, and rejects replay of a resolved review.
- The in-app ownership-review UI, end-to-end API authorization exercise, offline/two-device location convergence, employee journey E2E, and production rollout evidence remain outstanding. PR #211 stays draft.
