# Fulus Production Readiness Audit — 2026-09

## Final status

Production-readiness closure is complete for the application architecture, database, offline/sync system, deployment pipeline, and live production verification.

Physical Android offline/process-death/reinstall recovery validation passed.

PR #74 established production migration provenance and deployment controls. PR #76 closed the remaining application/database fidelity gaps: business-switch mutation fencing, server-authoritative split payments and refunds, financial precision, explicit diagnostic-events RLS, and financial contract tests.

Final production deployment: main commit b2657fcce6c436cb5e23ea7c2ff4bbb0cd4b281b; GitHub Actions production run 36225334620 — success.

## Verified production evidence

- Exact production migration history matches the repository: 126 migrations, ending at 20260926043000_close_financial_fidelity_gaps.
- Production schema drift check: PASS.
- Edge Function deployment: PASS.
- Post-deploy live sync contract E2E: PASS.
- Post-deploy multi-device convergence E2E: PASS.
- Catalog optimistic-concurrency serialization: PASS.
- Stale cursor rejection, restore boundary, device scoping, idempotency, credit-sale/payment/repayment, inventory, cash-drawer, tombstone and conflict-handling checks: PASS.
- Live snapshot: 196 sales, 199 sale-payment legs, 73 returns, 73 return items, 2,351 idempotency keys.
- Live sale-total and payment-total integrity checks: 0 violations.
- Live negative-refund check: 0 violations.
- diagnostic_events now has an explicit client-deny RLS policy.
- income_records.amount is numeric(14,2).

## Closed architectural gaps

### Business-switch mutation barrier
Durable sync enqueueing is fenced while business context is switching, and the final switch decision occurs under the barrier. Draft carts are intentionally transient/local and are deterministically cleared on business switch.

### Split-payment fidelity
Completed sales now send explicit payment legs. The server-authoritative sale RPC validates the legs against the server-calculated sale total and persists individual payment legs with idempotent operation identity.

### Refund accounting
Returns now use a server-authoritative RPC that calculates returned merchandise value from canonical sale items, validates refund amount and method, separates credit reversal from external refund legs, and enforces authorization/idempotency. The production E2E identity correctly fails the return operation at the permission boundary; authorized return behavior is covered by the financial contract tests.

### Migration/deployment governance
Production deployment is gated on the exact commit's CI, migration history is verified before/after deployment, schema drift fails deployment, Edge Functions deploy only after schema verification, and post-deploy live sync/convergence tests run before the deployment is considered successful.


## Remaining platform controls

### Supabase Auth leaked-password protection — PLAN-BLOCKED
The Supabase security advisor still reports leaked-password protection disabled. The production environment was tested through the Supabase Management API; the API returned HTTP 402 with the explicit response that HaveIBeenPwned leaked-password protection is available on Pro Plans and up. Therefore this control cannot be enabled on the current project plan. No application or database workaround can legitimately substitute for the managed Auth feature. Upgrade the project to a supported Supabase plan, enable password_hibp_enabled, then re-run the security advisor.

### GitHub main branch protection — NOT VERIFIED/CONFIGURED
The available GitHub connection could not safely verify or change repository branch-protection rules. Recommended controls remain: pull-request requirement, review requirement, required CI/Supabase checks, stale-approval dismissal, and disabled force-push/branch deletion.

### Supabase performance advisor — OPTIMIZATION BACKLOG
The current advisor reports 44 unused-index findings and 30 multiple-permissive-policy findings. These are performance optimization notices, not demonstrated authorization or data-integrity failures. They were not changed blindly during the production closure pass.


## Release gate

- [x] Architecture audit
- [x] Physical Android recovery validation
- [x] Migration provenance repair
- [x] Production CI/deployment hardening
- [x] Business-switch mutation fencing
- [x] Split-payment fidelity
- [x] Refund accounting
- [x] Financial precision
- [x] Diagnostic-events RLS
- [x] Production deployment
- [x] Schema verification
- [x] Edge Function deployment
- [x] Live sync E2E
- [x] Multi-device convergence E2E
- [x] Live integrity verification
- [ ] Upgrade to a Supabase plan supporting leaked-password protection, enable it, and clear the security advisor warning
- [ ] Configure and verify GitHub main branch protection/required reviews
