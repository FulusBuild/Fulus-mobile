# Copy-Paste Resume Prompt

Continue Fulus Cloud Sync PR #56 from the repository state. Do not restart completed work.

First read:
- docs/FULUS_CLOUD_SYNC_V1_ARCHITECTURE.md
- docs/FULUS_SYNC_IMPLEMENTATION_STATE.md
- docs/FULUS_SYNC_HANDOFF.md

Current branch: feat/cloud-sync-v1-hardening-v2
Current documented HEAD: fa864f9601966e4b8ee21346e6244b1ce6657b4e
Production fulus-api: v44
Production fulus-sync-state: v4

The 2026-09-22 phase audit found and closed the absolute stock-adjustment sync gap. Stock adjustments now use an authoritative server absolute-target command; never reconstruct an adjustment as a client delta.

Trace every supported syncable feature through:
local mutation -> transaction/outbox -> scheduling -> API -> authorization -> idempotency -> concurrency -> authoritative write -> change feed -> cursor -> canonical read -> reconciliation -> conflict/recovery -> retry/replay -> Sync Health.

Recovery invariant:
410 SYNC_CURSOR_TOO_OLD -> authoritative snapshot -> atomic bootstrap -> durable boundary -> post-bootstrap delta pull -> Sync Ready.

Do not declare V1 complete merely because CI is green. Execute and document the final architecture, client-flow, server-flow, failure/recovery, scale/Sync Health, production, diff, CI, E2E, and multi-device/replay audits. APK remains blocked until those gates pass.

Do not stop to give progress reports. Continue implementation, tests, CI, production verification, and fixes until the release gates are actually satisfied.

If a session ends before completion, update the sync state and handoff docs with exact HEAD, CI, production versions, completed gates, unresolved risks, and the next concrete action.
