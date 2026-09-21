# Copy-Paste Resume Prompt

Continue the Fulus Cloud Sync implementation from the repository state. Do not restart completed work.

First read:
- docs/FULUS_CLOUD_SYNC_V1_ARCHITECTURE.md
- docs/FULUS_SYNC_IMPLEMENTATION_STATE.md
- docs/FULUS_SYNC_HANDOFF.md

Then independently verify the current branch, HEAD, PR, diff against main, latest CI, relevant client/server code, and production Supabase state. Treat the repository as the source of truth if any handoff statement is stale.

Find the first genuinely incomplete architectural invariant and implement it completely. Do not stop to give progress reports. Iterate through implementation, focused tests, broader tests, CI, review, and fixes continuously.

For every syncable feature trace:

local mutation
-> transaction/outbox
-> scheduling
-> API
-> authorization
-> idempotency
-> concurrency
-> authoritative write
-> change feed
-> cursor
-> canonical read
-> reconciliation
-> conflict/recovery
-> retry/replay
-> Sync Health

Do not call a feature complete if only one side of this lifecycle exists.

The current priority is Phase 4 recovery/bootstrap. The server already has machine-readable stale-cursor detection; implement the actual client bootstrap/recovery lifecycle, including safe cursor boundaries, preservation/reconciliation of pending local work, interruption safety, retry safety, and eventual Sync Ready.

After that continue through batch canonical reads, crash/replay recovery, token/device recovery, scale/retention, authoritative Sync Health, and the final five audits.

The five final audits are mandatory:
1. architecture
2. client flow
3. server flow
4. failure/recovery
5. final diff/CI/integration/production

Do not declare completion merely because CI is green. Do not build or release an APK until the five audits and integration verification pass.

If the session ends before completion, update docs/FULUS_SYNC_IMPLEMENTATION_STATE.md with the exact HEAD, phase, completed checks, CI state, production state, unresolved risks, and the next concrete action.
