# Fulus backend

Fulus is **local-first and server-optional**. The server is authoritative when a business is connected, but the mobile app must remain fully usable with the server disabled or unreachable.

## Phase 0

This directory starts the server foundation without changing the mobile app's offline behavior.

Phase 0 establishes:

- business tenancy
- authenticated user profiles
- business memberships and roles
- permission vocabulary
- location memberships
- device registration
- server-side idempotency records
- sync operation records
- monotonic sync change feed
- business audit events
- PostgreSQL RLS and membership helpers

## Important boundary

Do **not** connect Flutter directly to generic Supabase table CRUD for business operations.

The intended path is:

```text
Flutter repository/API
    -> authenticated Fulus API / Edge Function
    -> authorization + business rules
    -> PostgreSQL transaction
    -> acknowledgement / sync change
```

RLS is defense-in-depth. It is not a replacement for application-level authorization.

## Migration order

The migrations will be added in this order:

1. `phase_0_foundation` — tenancy, identity, authorization, devices, sync and audit
2. `catalog` — products, categories, suppliers
3. `inventory` — balances, movements, adjustments and transfers
4. `sales` — sales, items and payments
5. `customers_credit` — customers and immutable credit ledger
6. `returns` — full and partial returns
7. `purchases` — purchasing and receiving
8. `cash` — drawers, shifts and cash movements
9. `finance` — expenses, income and financial categories
10. `sync_api` — upload/download contracts and transactional handlers
11. `reports_audit` — authoritative reports and extended audit queries
12. `migration` — standalone-to-connected enrollment and verification

## Standalone -> connected

Connecting an existing offline installation must never wipe its local database.

The eventual flow is:

```text
Standalone
  -> authenticated server account
  -> business created/selected
  -> device registered
  -> local backup created
  -> local data uploaded
  -> local IDs mapped to server IDs
  -> counts/checksums verified
  -> connected mode activated
```

The local database remains intact throughout the process and continues to be the offline working copy.

## Supabase project

The Supabase project currently connected to the account is the existing **wholesale-plastic-site** project. It is the website backend, not the Fulus Mobile business backend, so Phase 0 is intentionally committed to GitHub first rather than applying this schema to that unrelated project.

A dedicated Fulus Supabase project should be provisioned before these migrations are applied to a live database.
