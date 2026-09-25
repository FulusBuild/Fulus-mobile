# Fulus Production Readiness Audit — 2026-09

## Scope

This record covers the production-readiness audit of the Fulus Mobile application, including:

- Flutter/mobile application and local Drift/SQLite ledger
- Durable offline sync queue, retries, leases, cursors, idempotency and reconciliation
- Supabase/Postgres cloud schema, RLS, authorization, SECURITY DEFINER boundaries and RPCs
- Edge Functions and cloud API wrappers
- Sales, payments, returns, inventory, customer ledger, finance and cash-drawer invariants
- Cross-business and per-location isolation
- Production migration and deployment controls
- CI, live sync E2E and multi-device convergence coverage
- Live production database integrity checks

The audit was read-only with respect to production business data.

## Audit result

The architectural audit is complete. The core local/cloud/sync architecture and live data invariants were reviewed.

The physical Android process-death/recovery test has now been completed successfully.

Repository production-deployment hardening has been merged to `main` in PR #74.

The remaining release gates are deployment verification and administrative configuration rather than another architectural audit.

## Blockers and disposition

### 1. Android process-death / recovery validation — PASS

A physical Android recovery test was completed.

Test sequence:

1. Internet was disabled.
2. A sale was created while offline.
3. The app/process was interrupted.
4. Internet was restored.
5. The app was uninstalled and reinstalled.
6. The app was reopened and the sale was recovered from the cloud.
7. The sale appeared only once in recent activity.

**Status:** PASS for the tested offline-sync, process-interruption, cloud-recovery and duplicate-prevention scenario.

This test does not claim that an unsynced local database survives Android app uninstallation; app-local data is expected to be removed on uninstall.

### 2. Production migration provenance — REPAIRED IN REPOSITORY/CI PATH; PRODUCTION DEPLOYMENT PENDING VERIFICATION

Production history previously stopped at:

`20260925135830_harden_return_sale_idempotency_actor_scope`

while the repository contained later migration files:

- `20260925150000_harden_return_sale_idempotency_actor_scope.sql`
- `20260925160000_enforce_location_membership_on_api_mutations.sql`

Those migrations are preserved as the repository's authoritative continuation. The production deployment workflow has been hardened so it:

1. waits for the exact commit's mobile + live sync CI to pass;
2. verifies migration history before deployment;
3. applies pending migrations;
4. verifies migration history again;
5. compares the live public schema against the repository migration result and fails on drift;
6. only then deploys Edge Functions;
7. verifies migration history again.

The hardening changes have now been merged to `main`.

**Important:** the migration history observed immediately after the merge still ended at `20260925135830`. The production migration workflow must complete before the repository's later migrations can be considered deployed and verified.

### 3. Production CI/deployment gating — MERGED; DEPLOYMENT RUN PENDING/TO BE VERIFIED

The production Supabase workflow now:

- pins the Supabase CLI to `2.117.0`;
- pins the checkout and Supabase setup actions to reviewed SHAs;
- requires the exact production commit's `Fulus Mobile CI` workflow to complete successfully before any production migration or Edge Function deployment;
- therefore gates production deployment on the Flutter test suite, live sync contract test and multi-device convergence test already contained in that workflow;
- verifies the migration chain and live schema after migration application.

The changes were merged in PR #74 as commit:

`c82a346de20954b9cc914290912a5f12e51875fa`

Production deployment success has not yet been independently verified from the available GitHub workflow status interface.

### 4. GitHub branch protection / required-review setting — ADMINISTRATIVE SETTING

Repository automation could not safely verify or change organization-level branch protection with the available GitHub connection.

The repository should have `main` configured so that:

- direct pushes are blocked;
- pull requests are required;
- at least one review is required;
- required status checks include the mobile CI and relevant Supabase checks;
- stale approvals are dismissed when new commits are pushed;
- force pushes and branch deletion are disabled.

This is a GitHub repository setting, not an application-code defect.

## Other hardening findings

The following were identified but are not demonstrated production data-corruption vulnerabilities:

- refund semantics should become server-authoritative and represent refund legs explicitly;
- cloud representation of split payments should become first-class rather than aggregate-only;
- draft carts should have an explicit business boundary or deterministic switch/restore handling;
- the business-switch check/switch sequence should eventually be replaced with a DB-backed mutation/context barrier;
- `diagnostic_events` has RLS enabled with no policy, which currently defaults to deny but should be intentional/documented;
- Supabase reported multiple permissive-policy and unused-index findings requiring separate performance cleanup;
- `income_records.amount` should use the same explicit monetary precision/scale convention as the rest of the financial schema;
- leaked-password protection remains a Supabase Auth hardening recommendation.

These items should not be confused with the completed Android recovery test.

## Cloud and sync audit coverage

Cloud and sync were explicitly audited, including:

- durable queue lifecycle
- retry/backoff
- operation identity and idempotency
- optimistic concurrency
- foreground/background sync serialization
- SQLite lease behavior
- change-feed sequence/cursor handling
- cursor recovery
- canonical reconciliation
- stale-handler finalization
- device-scoped authorization
- business/location isolation
- server-side mutation authorization
- SECURITY DEFINER execution boundaries
- RLS
- live database invariants
- multi-device convergence test coverage

## Live integrity snapshot

The live production database was checked for the audited invariants covering:

- sale totals and line-item arithmetic
- payment totals
- inventory and stock/movement consistency
- return quantity bounds
- customer balances
- duplicate/idempotency operation keys
- sync sequence integrity
- cross-business relationships
- cross-location relationships
- sale/payment/return relationships
- current refund/cash-ledger consistency
- stale processing sync operations

The tested invariants returned no violations at audit time.

## Current release gate

### Completed

- [x] Architectural production-readiness audit
- [x] Physical Android offline-sync test
- [x] Process interruption/recovery test
- [x] Reinstall/cloud recovery test
- [x] Duplicate check for recovered sale
- [x] Production CI/migration hardening merged to `main`

### Still required

- [ ] Verify the production GitHub Actions deployment completes successfully
- [ ] Verify production migration history reaches the repository's expected migration tip
- [ ] Verify post-migration public-schema drift check passes
- [ ] Verify all production Edge Functions deploy successfully
- [ ] Re-run live financial/inventory/sync integrity checks after deployment
- [ ] Verify `main` branch protection and required status checks in GitHub repository settings

Until those deployment and administrative checks pass, the release should remain in the final verification stage.
