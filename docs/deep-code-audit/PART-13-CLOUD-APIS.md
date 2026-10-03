# Part 13 — Cloud APIs & Edge Functions

**Status:** In progress; source fixes on branch `audit/deep-code-part-13-cloud-apis`.

## Scope

Audited the authenticated and privileged Edge Function boundary, including:

- `fulus-api`
- `fulus-staff-api`
- `fulus-sync-state`
- `fulus-restore`
- `fulus-provision-business`
- `fulus-diagnostics`
- `fulus-reporting-api`

Checks covered authentication, business membership, permission enforcement, location isolation, device ownership/revocation, service-role boundaries, restore scope, idempotency, canonical reads, diagnostic ingestion, and error exposure.

## Findings

| ID | Severity | Status | Finding | Fix |
|---|---|---|---|---|
| P13-001 | High | Fixed on branch | Reporting API accepted active business members without requiring `reports.read`, and accepted any active business device rather than binding the request to the authenticated user's registered device. | Added `reports.read` authorization and `registered_by = authenticated user` device binding. |
| P13-002 | High | Fixed on branch | `set_inventory_quantity()` is SECURITY DEFINER and lacked an internal `inventory.adjust` permission check. | Recreated the RPC with an internal `public.has_permission(..., 'inventory.adjust')` guard plus existing business/device/product/location checks. |
| P13-003 | Medium | Fixed on branch | Privileged Edge Functions could return raw Postgres/Supabase error messages to clients, exposing implementation details and coupling clients to database error text. | Sanitized client-facing RPC error messages while retaining stable application error codes/statuses. Added a source-contract regression check. |
| P13-004 | Medium | Fixed on branch | Diagnostic ingestion accepted an arbitrary caller-supplied device identifier and stored the complete event payload without a bounded event-size invariant. | When a business is supplied, bind the diagnostic device to the authenticated user's active registered device; reject events whose serialized event exceeds 32 KiB. Added source-contract regression checks. |

## Cross-checks

### Authentication

All inspected externally callable functions that perform privileged work resolve the caller from the bearer access token using Supabase Auth before acting. Service-role clients are used only after the caller identity has been established.

### Business isolation

Authenticated business operations verify active membership for the requested business. The cloud API does not trust a caller-supplied user ID as the caller identity.

### Device isolation

Sync/reporting/recovery paths that require a device bind the supplied device client identifier to the authenticated user. Diagnostic ingestion now follows the same binding when a business context is supplied. Device revocation is delegated to guarded database RPCs.

### Location isolation

The sync and canonical-read paths explicitly compute accessible locations and filter location-scoped entities before returning service-role reads. Admin/owner users receive active business locations; non-admin users are constrained to active location memberships.

### Staff access

Employee management actions are separated from device administration. `employees.manage` is delegated only for roster-management actions; device inventory/revocation remains administrator-only.

### Restore

Owner/admin restore uses the business restore contract. Employee restore uses the location-scoped employee restore contract. Raw database errors are not returned to clients.

### Database authorization

Important service-role mutations were cross-checked against their SECURITY DEFINER database functions. Sales, payments, credit repayment, expenses, income, cash drawer operations, inventory delta adjustment, and absolute inventory setting enforce their respective permissions inside the database boundary.

## Verification

- Supabase migration-chain CI passed for the earlier Part 13 commit; the latest commit is being re-verified after diagnostic hardening.
- Fulus Mobile CI is being monitored for the current branch after the latest source/test changes.
- Production/runtime verification remains separate from source/CI proof and must be recorded before Part 13 is declared fully closed.

## Residual risks / follow-up

- Edge Function runtime tests are still lighter than the database migration regression suite.
- Rate limiting/abuse controls for authenticated diagnostic ingestion are not yet a demonstrated invariant.
- Full production verification of the new inventory permission migration is required after deployment.
