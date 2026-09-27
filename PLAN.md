# Fulus — Production Engineering Plan

## Purpose

This is the single working plan for taking Fulus from the current development state to a stable, secure, tested, and production-ready release.

The goal is not simply to add features. The goal is to establish a reliable product, a clean codebase, controlled releases, and evidence that the system works under real conditions.

## Engineering Principles

1. **One canonical implementation** — avoid duplicate screens, competing flows, and legacy UI remaining in the active product.
2. **Understand before changing** — inspect the current architecture and Git history before modifying behavior.
3. **Small, traceable changes** — each change should have a clear purpose and Git history.
4. **Test before declaring success** — a build succeeding is not proof that the feature works.
5. **Security throughout** — authentication, authorization, data protection, dependencies, API access, and secrets are part of normal engineering.
6. **Git is the source of truth** — production decisions must be traceable to code and commits.
7. **No production claim without evidence** — release readiness requires tests, device validation, and documented verification.

---

## Phase 1 — Repository & Architecture Audit

- Inspect the repository structure and current `main`.
- Review important Git history and recent regressions.
- Identify obsolete, duplicate, unfinished, and unused code.
- Review Flutter/Dart versions and project configuration.
- Review Android configuration and release settings.
- Review dependencies and remove unnecessary packages.
- Map navigation, state management, data access, APIs, authentication, and persistence.
- Establish the canonical implementation for every major feature.

**Output:** a clean architecture map and a list of production blockers.

---

## Phase 2 — Stabilize the Application

Prioritize the current runtime issues before adding more features.

### Navigation and startup
- Verify startup flow and `_ShellGate`.
- Verify authentication and route guards.
- Remove transition/rendering behavior that causes stale or legacy UI to flash.
- Verify root tabs and pushed routes.

### Core screens
Test and clean:

- Home
- Sell
- Stock
- Money
- Cart
- Payment
- Sale Success
- Settings
- Authentication

Remove legacy UI that is no longer part of the intended product.

**Output:** stable navigation and a consistent current UI.

---

## Phase 3 — Core Business Logic

Verify the business rules behind the main product loops.

### Products
- Create/edit/delete.
- Pricing.
- Product availability.
- Product search.
- Product validation.

### Stock
- Stock additions.
- Stock reductions.
- Adjustments.
- Low-stock behavior.
- Consistency with sales.

### Sales
- Product selection.
- Cart calculation.
- Discounts/taxes where applicable.
- Payment.
- Sale completion.
- Receipt/history.
- Failure and retry behavior.

### Money
- Income/outgoing transactions.
- Balances.
- Transaction history.
- Relationship between sales and money records.

**Output:** business flows that are correct independently of the UI.

---

## Phase 4 — Data Integrity

Treat data integrity as a production-critical system.

Verify:

- Database schema.
- Constraints.
- Foreign keys.
- Transactions.
- Atomic operations.
- Concurrent updates.
- Retry behavior.
- Duplicate submission handling.
- Partial failure recovery.
- App restart during an operation.
- Network interruption.
- Reconciliation between related records.

Special attention:

**A completed sale must not produce inconsistent stock, payment, or ledger state.**

**Output:** documented data invariants and tested failure behavior.

---

## Phase 5 — Authentication & Authorization

Verify:

- Sign-up/sign-in.
- Session persistence.
- Session expiration.
- Logout.
- Password/account recovery.
- User/business ownership.
- Role-based access where required.
- Protected routes.
- Backend authorization.
- Database row-level security where applicable.

Never rely on the mobile UI alone to enforce authorization.

**Output:** verified access-control model.

---

## Phase 6 — Security Audit

Review:

- Secrets and credentials.
- API keys.
- Authentication tokens.
- Local storage.
- Sensitive data handling.
- Network requests.
- TLS configuration.
- Database permissions.
- Supabase/backend policies.
- Dependency vulnerabilities.
- Debug/release configuration.
- Logging of sensitive information.
- Android permissions.
- Exported components and intent handling.

Use automated security/dependency checks where appropriate and manually review high-risk areas.

**Output:** security findings classified by severity and tracked to resolution.

---

## Phase 7 — Automated Testing

Build a practical test pyramid.

### Unit tests
Business rules, calculations, validation, data transformations.

### Widget tests
Important screens, states, forms, navigation behavior.

### Integration tests
Complete user journeys such as:

1. Sign in.
2. Create/select product.
3. Add to cart.
4. Complete sale.
5. Verify stock.
6. Verify money/ledger state.
7. Verify sale history.

Also test failure paths.

**Output:** repeatable automated verification for the critical product loops.

---

## Phase 8 — Real Device Testing

Test release builds on real Android devices.

Verify:

- Fresh install.
- Upgrade from previous version.
- Login/session persistence.
- Slow network.
- Offline/interrupted network where supported.
- App background/foreground.
- App restart.
- Rotation/configuration changes where relevant.
- Keyboard/input behavior.
- Back navigation.
- Long lists.
- Empty states.
- Error states.
- Payment/sale flow.
- Performance.
- Crash behavior.

Do not treat an emulator-only pass as production validation.

**Output:** device regression checklist with recorded results.

---

## Phase 9 — CI/CD

Create a reproducible build pipeline.

Verify:

- Formatting.
- Static analysis.
- Unit tests.
- Widget/integration tests where practical.
- Dependency checks.
- Release build.
- APK/AAB generation.
- Artifact retention.
- Versioning.
- Signing configuration.
- Secret management.

A production build should be reproducible from a known commit.

---

## Phase 10 — Production Observability

Before launch, establish enough visibility to diagnose real failures.

Track where appropriate:

- Crashes.
- Failed network operations.
- Authentication failures.
- Important business-operation failures.
- Sync/reconciliation errors.
- App version.
- Device/OS context.

Do not collect sensitive user data unnecessarily.

**Output:** a practical production monitoring and incident-response process.

---

## Phase 11 — Release Candidate

Create a release candidate from a known Git commit.

Run:

1. Full automated tests.
2. Static analysis.
3. Dependency/security checks.
4. Release build.
5. Installation test.
6. Upgrade test.
7. Real-device regression.
8. Critical business-flow test.
9. Backend/database verification.
10. Final Git diff review.

Only unresolved issues with explicit risk acceptance may remain.

---

## Production Release

Release only after the release candidate passes the production gate.

Record:

- Git commit.
- App version/build number.
- Build artifact.
- Environment.
- Database/backend version.
- Known issues.
- Rollback/recovery procedure.

---

## Post-Production

After release:

- Monitor crashes and critical failures.
- Monitor business-flow errors.
- Review user-reported issues.
- Reproduce production bugs locally.
- Fix through small, traceable commits.
- Retest before release.
- Maintain a clear changelog.

Do not immediately stack large changes on top of an unstable release.

---

## AI Engineering Rules

AI is an engineering tool, not the authority.

For every AI-assisted change:

1. Understand the existing implementation.
2. State the intended behavior.
3. Make the smallest appropriate change.
4. Inspect the resulting diff.
5. Run relevant tests.
6. Review security-sensitive changes manually.
7. Build and test on a real device when behavior is user-facing.
8. Commit with a clear message.
9. Do not declare production readiness from compilation alone.

AI-generated code is accepted only after verification.

---

## Definition of Production Ready

Fulus is production-ready when:

- Critical user journeys work reliably.
- Core business rules are tested.
- Data remains consistent during normal and failure conditions.
- Authentication and authorization are verified.
- Security risks are reviewed and controlled.
- Dependencies are reviewed.
- Critical automated tests pass.
- Release builds install and operate correctly on real devices.
- CI can reproduce the release.
- Production monitoring exists.
- A rollback/recovery path exists.
- The final release is traceable to a known Git commit.

---

## Current Priority

The immediate work sequence is:

1. Clean the repository documentation.
2. Establish this plan as the working engineering reference.
3. Audit current `main`.
4. Stabilize startup and navigation.
5. Resolve the stale/legacy UI transition issue.
6. Verify Sell, Stock, Money, Cart, Payment, and Sale Success.
7. Audit data and business logic.
8. Audit authentication/security.
9. Build the automated test foundation.
10. Establish the production CI/CD gate.
11. Run the release-candidate process.

No major feature expansion should take priority over unresolved production blockers.

---

## Working Rule for Every Future Change

Before changing Fulus, answer:

1. What is the current implementation?
2. What behavior are we changing?
3. Why is the change needed?
4. What existing behavior could it break?
5. How will we test it?
6. What Git commit contains the change?
7. What evidence shows the change is safe?

This keeps Fulus moving toward production instead of accumulating disconnected AI-generated changes.
