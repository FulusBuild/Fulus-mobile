# Fulus Runtime & Production Evidence Track

**Status:** Active  
**Purpose:** Keep runtime/production proof separate from the main Mobile CI workflow.

This track exists because source-level correctness and CI success are not the same thing as Android/runtime/production evidence. It is intentionally a separate manually triggered GitHub Actions workflow so the normal PR/main workflow stays focused and fast.

## Automated evidence

The workflow runs:

1. **Money boundary contract**
   - integer minor-unit arithmetic
   - strict decimal-string wire contract
   - regression for the reported ₦300 -> 30,000 failure mode

2. **Live account creation contract**
   - production Supabase signup boundary

3. **Live sync contract**
   - authenticated cloud sync/idempotency contract

4. **Live multi-device convergence**
   - independent device identities
   - concurrent financial operations
   - idempotent replay
   - canonical feed visibility
   - final authoritative financial invariants

5. **Production migration history**
   - remote migration history must be an exact prefix of the repository migration chain

## Manual Android evidence

A green workflow does **not** close these gates:

- offline mutation -> Android process death/force-stop -> WorkManager/headless recovery -> reconnect -> exactly one remote financial effect
- fresh-install local restore -> restart/reopen -> continued business use and sync convergence
- location A -> B while A has pending/in-flight work
- signed APK install/upgrade using representative existing financial data
- cold/warm first-frame and primary navigation behavior
- diagnostic capture during offline/auth/database/function failure

These require a real Android runtime and must be recorded as evidence, not inferred from Dart tests or GitHub Actions.

## Completion rule

The architectural benchmark remains **conditionally production-ready** until the manual Android evidence above is observed and recorded. This workflow is evidence collection, not a replacement for the benchmark or for the main CI gate.

## Relationship to main CI

- Do **not** add these jobs to `.github/workflows/ci.yml`.
- Run this workflow manually when a release candidate or major sync/money change needs runtime/production revalidation.
- Main CI remains the required code-quality/regression gate.
