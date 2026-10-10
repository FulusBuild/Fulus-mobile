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

1. **Legacy ownership review workflow:** the service-role-only transactional resolution RPC, owner/admin-gated API actions, and in-app review UI are implemented. The UI now loads candidate target locations from the server response scoped to the selected business rather than the local location cache, which has no business_id column. Regression tests cover endpoint routing and server-scoped location parsing; SQL tests cover non-admin denial, cross-business location rejection, explicit product/customer assignment, reviewer recording, and replay rejection. A full authenticated UI/API authorization exercise is still required. Do not assign legacy rows automatically.
2. **Two-location, two-device convergence proof:** add/run an end-to-end scenario proving that a product/customer created offline in Location A remains owned by A after retry, restart, restore, and another device's sync, and that a Location B actor cannot read or mutate it. Pull-request CI has not run the production multi-device workflow.
3. **Employee journey:** SQL restore-isolation contracts pass, but the full invitation/claim, sign-in, reinstall/restore, and role-permission journey still needs end-to-end verification.
4. **Production rollout:** the new migration and Edge Function changes have not been deployed to production from this draft PR. Do not merge or deploy until the remaining acceptance criteria and required runtime evidence are satisfied.

Keep PR #211 as a draft until these blockers are closed and the exact final head has green CI plus the required runtime evidence.


## Follow-up verification note (2026-10-10)

- Fixed a cloud API contract mismatch: the `catalog_list` handler already required `location_id` and applied location authorization/filtering for customers, but the shared entity allowlist rejected `customers` before that path could run. Customer reads are now admitted only for `catalog_list`; generic catalog mutations still reject customers and continue using the dedicated customer mutation RPCs.
- Added a source contract assertion in `supabase/tests/cloud_api_authorization_contracts.sh` so this mismatch is caught by CI.
- The follow-up ownership-review implementation adds owner/admin-gated API actions for listing pending reviews and resolving one to an explicitly selected active location, backed by a service-role-only transactional RPC. The SQL authorization test covers successful resolution for both products and customers, rejects cross-business assignment and non-admin resolution, records the reviewer, and rejects replay of a resolved review.
- The in-app ownership-review screen and route are now implemented under Manage Locations. The client derives the ownership endpoint from the configured staff API URL; a regression test verifies the default `/fulus-api` route and an explicit endpoint override. Suggested-location labels compare cloud/server location IDs consistently.
- Code head validated immediately before this documentation update: `de609509b179e95fd94b89c2263e9cf8aac44411`. Fulus Mobile CI passed, including code generation, static analysis, and Flutter tests. Supabase Migration Chain passed its clean schema rebuild and SQL contract suite.
- Live production sync and multi-device convergence jobs were skipped by the workflow because this PR changes cloud code and migrations; those runtime checks have not been proven by this run. The remaining blockers are an end-to-end UI/API authorization exercise, offline/two-device location convergence, the full employee invitation/claim/sign-in/reinstall/restore journey, and production rollout evidence. PR #211 stays draft.


## Follow-up verification note (2026-10-10, business-scoped review targets)

- Closed a client-side scoping gap in the legacy ownership review screen: the local Location entity and table do not contain business_id, so the local location cache was not a safe source for ownership-resolution choices.
- The owner/admin-gated `location_ownership_review_list` response now includes active locations queried by the selected business ID. The review screen uses those server-returned targets and sends their cloud IDs to the transactional resolver; the resolver independently validates business membership and active location ownership.
- Added a Flutter API regression test proving the ownership target list is parsed from the authorized API response. This does not replace the still-required authenticated end-to-end UI/API exercise.
- Code changes were committed to PR #211; re-run Mobile CI and Supabase Migration Chain against the exact new head before treating this fix as verified. Live production sync/multi-device and full employee journey checks remain outstanding. PR #211 remains a draft.


## Follow-up verification note (2026-10-10, PR #211 CI and resolver review)

Verified against PR head `7130e0fe12414824d2728584be4317fba1acfb9a` (base SHA observed: `8b1e9516068ab311551a478daa6fe308799ad9f3`):

- Fulus Mobile CI run [38028276295](https://github.com/FulusBuild/Fulus-mobile/actions/runs/38028276295) completed successfully. Its dependency, migration filename integrity, change-scope, Dart code generation, static analysis, and Flutter test jobs completed successfully.
- Fulus Supabase Migration Chain run [38028276195](https://github.com/FulusBuild/Fulus-mobile/actions/runs/38028276195) completed successfully, including clean schema rebuild and SQL authorization, repayment, financial fidelity, employee restore isolation, and cloud API contract tests.
- The earlier `LocationOwnershipTarget.serverId` compile/analyzer failure is resolved: the ownership review screen now compares candidate IDs against `LocationOwnershipTarget.id`.
- Source inspection confirms the ownership-review list endpoint checks active business membership and owner/admin role before returning review rows and active locations filtered by the requested business. The resolver RPC independently checks owner/admin membership, locks the pending review and target entity, verifies that the selected location is active and belongs to the same business, rejects already-owned/missing entities, assigns only a null location_id, and records reviewer/time. The RPC is executable only by service_role.
- These CI results establish local build/test and migration-contract status only. They do not establish authenticated UI/API end-to-end behavior or production/two-device convergence.

### Remaining acceptance blockers (unchanged)

1. Run an authenticated owner/admin UI/API workflow, including non-admin denial, cross-business target rejection, duplicate/concurrent resolution, missing/already-owned records, reviewer audit, and post-resolution refresh.
2. Prove two-location isolation across offline create/mutation, durable outbox replay/retry, process restart, snapshot restore, location switching, and two-device convergence. Include denied cross-location reads/writes for products, customers, roster, stock, and related financial/history projections.
3. Verify the full employee invitation/claim/password/sign-in/logout/reinstall/restore and role-permission journey in the combined PR set, preserving inactive historical cashiers without granting access.
4. Recheck all four PR heads and their CI against the current base before integration. Previously observed green results for #208, #209, and #214 apply only to their exact recorded SHAs.
5. Production-backed verification requires explicit rollout approval. No deployment or production mutation was performed as part of this review.

PR #211 remains a draft. Do not infer ownership for legacy records or treat green CI alone as runtime acceptance.


## Current verification checkpoint (2026-10-10, PR head `e489246617b306457b3830421dd577f7523ce4fe`)

- Fulus Mobile CI passed on this PR head: run [38028786185](https://github.com/FulusBuild/Fulus-mobile/actions/runs/38028786185).
- Supabase Migration Chain passed the clean-schema migration rebuild and SQL contract suite: run [38028786241](https://github.com/FulusBuild/Fulus-mobile/actions/runs/38028786241).
- The four-PR review also confirmed that PR #208's legacy ledger mapper/test change overlaps this PR in `test/repository/customer_credit_repository_test.dart`. The changes are additive in the current patches, but the combined behavior still needs a single integration run before merging either branch.
- PR #214's restore normalizer optimization is not deployed to production. The successful production multi-device run on that PR therefore does not close this PR's location-isolation acceptance criteria.
- Remaining blockers are unchanged: authenticated ownership-review UI/API exercise; offline two-location/two-device isolation through retry, restart, restore and convergence; full employee invite/claim/sign-in/reinstall/restore and permission journey; and explicit production rollout approval. This PR remains draft and unmerged.


## Employee ownership review follow-up (2026-10-10)

A review of the location-filtered roster found that employees with a null `location_id` were hidden from every location roster, while the original review queue accepted only products and customers. That left no explicit path to reconcile legacy unassigned employees.

The location ownership change now:
- Allows `employee` review rows and backfills existing employees without a location into the pending owner/admin review queue.
- Creates or reopens a pending review whenever a legacy/API write leaves an employee unassigned.
- Resolves an employee only when the target location is active and belongs to the same business; the resolver locks the employee row, assigns only a null owner location, aligns active `location_memberships`, leaves inactive employees inactive, publishes a canonical employee change, and records reviewer/time.
- Prevents ordinary roster update calls from clearing or changing an established employee location. Unassigned employee updates must wait for explicit ownership resolution.
- Refreshes the normal connectivity-gated sync path after a successful review so the local employee canonical reconciler can apply the server-assigned location.
- Adds disposable SQL regression coverage for auto-queueing a null-location employee, resolving it, membership alignment, canonical change publication, and rejection of a regular cross-location employee update.

Verification on exact code head `56af744ef9a3bfc8fc5d45d34871a4536f389e65`:
- Fulus Supabase Migration Chain passed: [run 38038467443](https://github.com/FulusBuild/Fulus-mobile/actions/runs/38038467443).
- Fulus Mobile CI passed: [run 38038467462](https://github.com/FulusBuild/Fulus-mobile/actions/runs/38038467462).

These are local migration-contract and Flutter CI results. They do not replace authenticated live owner/admin UI/API testing or offline two-location/two-device convergence. No production migration or deployment was performed.


## Migration sequence reconciliation (2026-10-10)

The location-ownership candidate must be tested with the repository's current migration chain, not only against the older branch snapshot. The integration candidate restores the exact source files for these versions in order:

1. `20261009150000_optimize_restore_money_wire_object_rebuild.sql`
2. `20261009170000_optimize_money_wire_row_aggregation.sql`
3. `20261009190000_optimize_restore_snapshot_array_traversal.sql`
4. `20261009200000_optimize_restore_known_money_sections.sql` (already recorded as applied in production; restored from the migration-history reconciliation PR)
5. `20261010230000_complete_restore_money_allowlist_and_large_snapshot_contract.sql` (follow-up from PR #216; must come after location migrations ending at `20261010220000`)

The first three files are byte-for-byte copies of the versions on `main`; the fourth is copied from PR #214's verified migration file; the fifth is copied from PR #216's verified candidate. The location-ownership migrations must remain between versions `20261009200000` and `20261010230000`. The candidate still requires clean-schema migration-chain CI and review of the final ordered SQL. Do not merge this validation candidate independently, and do not dispatch or trigger a production deployment without explicit approval.