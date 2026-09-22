# Fulus Cloud Sync V1 — Current Handoff

This document supersedes the older Batch 1/Batch 2/Batch 3 planning notes in this file. Cloud Sync V1 is now tracked by docs/FULUS_SYNC_IMPLEMENTATION_STATE.md.

## Verified repository state

- Repository: FulusBuild/Fulus-mobile
- Branch: main
- HEAD at audit merge: 41ded8faf08d8d4b407eb95afc1310b8ad86ff05
- Audit fix PR: #59
- Supabase project: bejcuvoxemwomcatgyxz

## What the second-pass audit changed

The prior completion claim was re-tested from source and production rather than accepted.

The audit fixed:
- customer repayment outbox atomicity;
- initial seeding of pre-cloud archived products/categories/suppliers/customers;
- stale-cursor reuse during pre-sync product create -> archive;
- a stale conflict-resolution documentation claim.

## Completion evidence

All five Cloud Sync V1 phases are independently verified:

1. Correctness — local transaction/outbox, queue lifecycle, pull/cursor semantics, canonical reconciliation and startup seeding.
2. Contract completeness — supported client mutations traced to server commands/RPCs/change feed/reconciliation.
3. Concurrency — optimistic conflicts, idempotency, cash drawer serialization and absolute stock target locking.
4. Recovery/scale — stale-cursor restore, atomic bootstrap, boundary/delta sequencing, business isolation, pagination and retention.
5. Production integration — production schema/functions/RLS/indexes/retention/Edge Functions, CI and live E2E.

## Production

Current active Edge Function versions verified during the audit:
- fulus-api v44
- fulus-sync-state v4
- fulus-restore v7
- fulus-provision-business v7

The production migration history was rechecked and reconciled with the final repository migration set, including the absolute-stock atomic-target migration.

## Final CI gate

Run #1480 / 35711931991 passed:
- dependency resolution;
- generated-code build;
- static analysis;
- Flutter tests;
- live Fulus sync contract E2E.

APK jobs were skipped intentionally.

## Important scope boundary

Stock transfers are not a V1 sync mutation because no current mobile write path constructs a transfer. Sale stock movements are server-derived by sale.create. Sale payment legs are part of the sale transaction rather than independent cloud commands.

## Recovery / crash-proofing boundary

No literal physical device-kill test is claimed. Crash safety is proven by transaction rollback, durable outbox semantics, cursor acknowledgement ordering, recovery safety gates, and automated tests.

## Final state

Cloud Sync V1 has passed the independent completion audit after the second-pass fixes. Do not use the older historical Batch 1 checklist in this file as the current implementation state; use docs/FULUS_SYNC_IMPLEMENTATION_STATE.md.
