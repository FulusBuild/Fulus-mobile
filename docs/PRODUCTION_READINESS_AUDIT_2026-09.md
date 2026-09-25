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

The audit itself is complete. The core local/cloud/sync architecture and live data invariants were reviewed.

The remaining release gates are validation/remediation items rather than unaudited areas.

## Blockers and disposition

### 1. Android process-death / lease-takeover validation — USER DEVICE TEST REQUIRED

This cannot be proven from repository inspection alone.

The implementation is materially hardened against stale sync finalization, and the Android WorkManager/background path plus durable SQLite lease were reviewed. A physical Android test is still required to prove the real OS lifecycle behavior.

**Required test on a physical Android phone:**

1. Start with a healthy synced business/location.
2. Create a local mutation while offline so it is durable in the sync queue.
3. Force-stop/kill the app process while the operation is pending or while a sync attempt is active.
4. Reopen the app.
5. Confirm the queue is recovered and the operation is eventually applied exactly once.
6. Confirm no operation remains stuck in `processing`.
7. Confirm the same operation is not duplicated in the cloud.
8. Repeat with background WorkManager recovery.
9. Repeat during a business switch boundary and confirm no mutation is attributed to the wrong business.

**Status:** pending physical validation.

### 2. Production migration provenance — REPAIRED IN REPOSITORY/CI PATH

Production history previously stopped at:

`20260925135830_harden_return_sale_idempotency_actor_scope`

while the repository contained later migration files:

- `20260925150000_harden_return_sale_idempotency_actor_scope.sql`
- `20260925160000_enforce_location_membership_on_api_mutations.sql`

Those migrations are now preserved as the repository's authoritative continuation. The production deployment workflow has been hardened so it:

1. waits for the exact commit's mobile + live sync CI to pass;
2. verifies migration history before deployment;
3. applies pending migrations;
4. verifies migration history again;
5. compares the live public schema against the repository migration result and fails on drift;
6. only then deploys Edge Functions;
7. verifies migration history again.

This converts the previous undocumented-schema condition into an explicit, CI-controlled reconciliation path.

**Important:** the existing production project is not modified directly by this audit branch. The pending migrations will be applied by the protected production deployment workflow when this branch is merged to `main`.

### 3. Production CI/deployment gating — HARDENED IN REPOSITORY

The production Supabase workflow now:

- pins the Supabase CLI to `2.117.0`;
- pins the checkout and Supabase setup actions to reviewed SHAs;
- requires the exact production commit's `Fulus Mobile CI` workflow to complete successfully before any production migration or Edge Function deployment;
- therefore gates production deployment on the Flutter test suite, live sync contract test and multi-device convergence test already contained in that workflow;
- verifies the migration chain and live schema after migration application.

This closes the previous gap where production deployment could proceed independently of the mobile/cloud-sync CI.

### 4. GitHub branch protection / required-review setting — ADMINISTRATIVE SETTING

Repository automation cannot safely infer or change organization-level branch protection with the currently available GitHub connection.

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

These items should not be confused with the physical Android validation gate above.

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

## Release gate

The application should be considered **pending final physical-device validation**, not pending another architectural audit.

Once the Android process-death/background recovery test passes and the repository changes are merged through the gated production workflow, the remaining administrative branch-protection setting should be verified before commercial release.
