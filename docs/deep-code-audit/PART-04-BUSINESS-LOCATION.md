# Part 04 — Business & Location Isolation

**Status:** Fix implemented; CI/runtime verification pending  
**Baseline SHA:** `ff0c8d8f97a40f9a5801a3023aa5d21bd46058fc`  
**Audit branch:** `audit/deep-code-part-04-business-location`

## Scope

Business IDs, location IDs, memberships, active location selection, location-scoped local queries/mutations, cloud restore, incremental sync filtering, and cross-device employee provisioning.

## Inspection evidence

### Structural inventory

Inspected:

- `lib/data/remote/fulus_business_context.dart`
- `lib/data/remote/fulus_connection_state.dart`
- `lib/data/remote/employee_cloud_session_coordinator.dart`
- `lib/data/remote/cross_device_employee_restore.dart`
- `lib/data/remote/cloud_restore_api.dart`
- `lib/data/remote/endpoints/locations_api.dart`
- `lib/data/repositories/location_repository_impl.dart`
- `lib/data/repositories/customer_repository_impl.dart`
- `lib/data/repositories/product_repository_impl.dart`
- `lib/sync/handlers/location_sync_handler.dart`
- `lib/sync/handlers/product_sync_handler.dart`
- `lib/sync/handlers/sale_sync_handler.dart`
- `lib/app/providers.dart`
- `lib/app/router.dart`
- `lib/features/more/settings/presentation/screens/manage_locations_screen.dart`
- `lib/features/sell/presentation/cubit/cart_cubit.dart`
- `supabase/functions/fulus-api/index.ts`
- `supabase/functions/fulus-restore/index.ts`
- relevant location authorization, employee, restore, and sync migrations
- active-location and cart-isolation tests

### Proven boundaries

1. Product catalog identity is business-wide while stock is keyed by product/location.
2. Customer identity is deliberately business-wide; customer queries do not have a location predicate by design.
3. Sales, expenses, income, cash drawer shifts, stock movements, returns, and employees carry location context.
4. The normal incremental sync feed explicitly derives employee location access and filters location-scoped change types before returning changes to the client.
5. Active-location switching is serialized and rejects employee identities from changing their assigned location.
6. Router/settings access gates location management through the settings permission; server mutation authorization remains authoritative.
7. Business selection only accepts active server memberships.

## P04-001

**Severity:** High  
**Status:** Fixed; required CI/runtime verification pending  
**Files:**
- `supabase/functions/fulus-restore/index.ts`
- `supabase/migrations/20261002095000_employee_location_scoped_restore.sql`
- `supabase/tests/employee_restore_location_isolation.sql`

### Observed behavior

Employee cross-device provisioning calls the restore endpoint through `EmployeeCloudSessionCoordinator.establish()`. The endpoint previously delegated every caller to `build_fulus_restore_snapshot`. That RPC only authorizes owner/admin membership, while the employee coordinator explicitly rejects owner/admin accounts and expects non-admin employee provisioning.

The full restore snapshot is business-wide, so simply broadening the existing RPC to employees would also violate the location-isolation invariant.

### Expected invariant

An employee can bootstrap a device only from their authoritative business membership and assigned active location. A non-admin employee must not receive another location's operational data merely because the device is being restored.

### Root cause

The restore transport had one full-business snapshot contract but two different authorization/data scopes:

- owner/admin: full business restore
- employee: assigned-location restore

The Edge Function did not distinguish those contracts.

### Fix

Added `build_fulus_employee_restore_snapshot`, restricted to active non-admin business members with an active location membership. Its snapshot:

- includes exactly the employee's active location;
- includes location-scoped sales, stock movements, stock levels, expenses, income, returns, and cash-drawer shifts only for that location;
- keeps business-wide catalog/customer identity where the product model intentionally defines those as business-wide;
- includes only the signed-in employee in the employee roster projection;
- does not expose staff invites, devices, audit events, role/permission tables, or other staff identities;
- preserves the business sync boundary so the normal change feed can resume safely.

The restore Edge Function now chooses the full snapshot for owner/admin and the scoped snapshot for non-admin members.

The new SECURITY DEFINER function pins an empty search path and schema-qualifies database objects, matching the repository's existing hardened function pattern and current Supabase guidance.

### Regression test

Added `supabase/tests/employee_restore_location_isolation.sql` proving:

- the employee snapshot contains exactly the assigned location;
- an unassigned same-business location is absent;
- only the signed-in employee is restored;
- owner/admin cannot use the employee-only RPC;
- an employee without an active location membership is rejected.

## Cross-checks

- Incremental `fulus-api` pull already filters location-scoped change types using server-resolved location memberships.
- Sale/return changes derive location through authoritative sale rows when the change payload does not contain a direct location.
- Product/catalog changes remain business-wide by design.
- Customer identity and customer ledger are business-wide by design.
- Local active-location resolution is tied to the signed-in identity.
- Employee location projection is resolved from the authoritative claim before the local session is established.

## Remaining uncertainty

- Production employee fresh-device restore must be exercised against the deployed Edge Function and production migration state.
- Android process-death between restore completion and the first incremental pull remains cross-cutting runtime evidence for Parts 15/17.
- Full multi-device employee location convergence remains Part 16/20 verification.

## Verification

Relevant existing unit tests cover active-location resolution, serialized location switching, and cart location isolation. The new SQL regression test is intended for the repository's local Supabase test/reset environment.

CI status will be recorded after the branch validation run.

## Next recommended step

Part 05 — Local Database & Persistence.
