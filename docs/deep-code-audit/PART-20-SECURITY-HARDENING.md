# Part 20 — Security & Production Hardening

## Scope
This pass audits Supabase RLS, SECURITY DEFINER exposure, Edge Function authentication, business/location isolation boundaries, grants, production advisors, and security configuration.

## Evidence source
Production Supabase project was inspected directly on 2026-10-03:
- Project: Fulus backend
- Postgres 17.6.1.166
- All listed public business-domain tables report RLS enabled.
- Production Edge Functions and migration history were inspected.
- Supabase security and performance advisors were queried.

## Pass A — Structural inventory

### Database boundaries
The production public schema contains the business, membership, location, device, sync, audit, catalog, financial, inventory, customer, employee, invitation and diagnostic tables. The inspected business-domain tables all report RLS enabled.

### SECURITY DEFINER boundary
Production contains numerous SECURITY DEFINER functions, including service RPCs, access-control helpers, snapshot/restore helpers and change-feed helpers.

A direct database query verified:
- SECURITY DEFINER functions in public have no anonymous EXECUTE privilege in the inspected result.
- SECURITY DEFINER functions in public have no authenticated EXECUTE privilege in the inspected result.
- No inspected SECURITY DEFINER function was missing an explicit function-level `search_path` configuration.

This is important because service-definer functions must not become public RPC endpoints merely by existing in `public`.

### Edge Functions
Production currently has:
- `fulus-api`: JWT verification enabled.
- `fulus-reporting-api`: JWT verification enabled.
- `fulus-restore`: JWT verification enabled.
- `fulus-provision-business`: JWT verification enabled.
- `fulus-sync-state`: JWT verification enabled.
- `fulus-diagnostics`: JWT verification enabled.
- `fulus-staff-api`: JWT verification disabled, but its source implements explicit bearer-token authentication before every authenticated action; only invite inspection and first-device preparation intentionally bypass authentication and require a high-entropy invitation token.

The staff function was specifically cross-checked because disabled platform JWT verification can otherwise create an accidental public endpoint. The source performs `auth.getUser()` for all post-invite actions and checks active business membership and staff permissions before service-role reads/writes.

## Pass B — Authorization/function audit

### RLS
RLS is enabled across the inspected public business-domain tables. Existing policies use business/member/location access helpers rather than treating authentication alone as authorization.

### Service-definer RPCs
The production query showed the SECURITY DEFINER functions are not directly executable by anon/authenticated roles. API access therefore flows through the intended Edge Function/service boundaries and explicitly granted RPCs.

### Search-path hardening
No SECURITY DEFINER function was found without a configured function-level `search_path` in the production query.

### Diagnostic boundary
The diagnostic Edge Function requires a bearer token, verifies the user, validates active business membership for business-scoped events, optionally validates the active registered device, bounds payload size, and upserts by event ID.

## Concrete production finding

### P20-001 — Medium — Leaked-password protection disabled

**Observed:** Supabase's production security advisor reports `auth_leaked_password_protection` as WARN: leaked-password protection is disabled.

**Expected invariant:** Account password creation should reject passwords known to be compromised, reducing credential-stuffing/reuse risk.

**Evidence:** Production Supabase security advisor on 2026-10-03 returned one security lint with this warning.

**Fix:** Enable Supabase Auth leaked-password protection in the project's Auth/password security configuration. This is a hosted Auth configuration change rather than a repository migration, so it should not be simulated with SQL or a speculative code change.

**Verification:** Re-run the Supabase security advisor after enabling and confirm the warning disappears. Also verify normal sign-up/password-reset flows remain functional.

**Current status:** Open; production configuration change and post-change verification required.

## Performance advisor findings

The performance advisor reports many unused indexes and multiple permissive RLS policies. These are not automatically security defects:
- unused-index reports need workload/context before removal;
- multiple permissive policies can be valid when combining member/admin access paths.

No index or policy was removed speculatively during the security audit.

## Pass C — Cross-system security checks

### Identity chain
Auth user → business membership → role/permission → location membership → device registration is enforced in the principal cloud boundaries inspected.

### Edge Function → database
Privileged Edge Functions use the service role only after application-level authentication/authorization checks. The inspected staff API explicitly resolves the authenticated user before business access and delegates sensitive mutations to hardened RPCs.

### RPC → RLS
SECURITY DEFINER functions are treated as privileged code paths and are not directly executable by anon/authenticated roles unless intentionally exposed through a wrapper. Function-level search paths are hardened.

### Diagnostics
Diagnostic payloads are redacted on-device before remote upload; remote storage additionally enforces authenticated business/device access at ingestion.

## Pass D — Production evidence gaps

### P20-RUNTIME-001
A full unauthorized-access matrix still requires active test accounts/devices to exercise cross-business, cross-location, revoked-member, revoked-device, and direct-RPC attempts against production.

### P20-CONFIG-001
Leaked-password protection remains a production dashboard/configuration task.

### P20-PROD-001
Final release hardening still requires the complete Android runtime matrix from Parts 15, 17 and 18 plus final CI.

## Conclusion

The inspected production database shows strong RLS and SECURITY DEFINER hardening evidence. One concrete production security configuration warning remains: leaked-password protection is disabled. No speculative database or authorization rewrite was made.
