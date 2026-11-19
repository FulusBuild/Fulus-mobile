# Fulus Product Verification and Audit Master Plan

**Status:** Active working plan
**Last reviewed:** 2026-11-19
**Purpose:** A repeatable protocol for auditing Fulus features, testing the Android app, validating backend behavior, and keeping project documentation trustworthy.

This is the canonical coordination document for product verification. [`deep-code-audit/MASTER_PLAN.md`](deep-code-audit/MASTER_PLAN.md) remains the detailed source-audit method and is subordinate to this plan for scope, evidence, safety, and release conclusions. [`../PLAN.md`](../PLAN.md) tracks engineering priorities; it is not evidence that work has passed.

## 1. Mission and completion standard

Verify that Fulus works for its small-business workflows, including on a real Android phone and under offline, restart, retry, and authorization conditions. Combine product behavior, source, local storage, sync/backend behavior, and documentation into one findings ledger and final report.

A feature is not “tested” just because its screen opens, source code exists, a unit test passes, or an APK builds. Record the exact evidence layer. The final conclusion must distinguish verified behavior from code-only confidence and open runtime gaps. Completion may include known findings, but must not conceal them behind a blanket pass.

## 2. Product invariants

- Accepted local business actions are durable and usable without internet.
- Sales, returns, stock movements, customer balances, payments, and cash records agree under defined accounting rules.
- Retrying or syncing an action does not duplicate its effects.
- Users can access only data permitted by their business, location, and role.
- Cloud sync is not reported as successful while required work is pending or failed.
- Process death, app restart, connectivity changes, and session expiry do not silently lose accepted work.
- Restore does not report success or permit normal work until the restored data is complete and usable.
- Users can tell a local save from a cloud backup and receive actionable errors.
- Hardware-dependent functions fail safely and explain unavailable permissions or devices.
- Documentation describes the current repository and labels time-sensitive evidence with date, environment, and code baseline.

If a product rule is unclear, document the ambiguity. Do not invent accounting or permission semantics to make a test pass.

## 3. Audit parts and boundaries

Assign each part its own checklist and findings. Cross-cutting privacy/security, money correctness, data integrity, errors, and documentation hygiene apply to all parts.

| Part | Boundary | Main scenarios and risks |
|---|---|---|
| A. Startup, onboarding, navigation | Bootstrap, welcome, create/join business, shell, route guards | Cold/warm launch, incomplete onboarding, deep links, empty/loading/error states |
| B. Authentication and sessions | Sign-up, sign-in, recovery, local/cloud identity, logout | Session persistence/expiry, offline behavior, account switching, credential safety |
| C. Staff, roles, business/location | Employees, invitations, roles, locations, ownership | Join/revoke, role restrictions, tenant/location isolation, switching locations |
| D. Catalog and products | Product forms, categories, search, import/export | Validation, duplicate SKU/barcode, edits, archive/delete, import errors |
| E. Inventory and suppliers | Stock-in/out/adjustments, low-stock, movements, supplier ledger | Stock conservation, negative stock policy, atomicity, concurrency, retries |
| F. Sales and checkout | Quick sale, cart, discounts, split tender, payment, history | Totals, rounding/change, duplicate taps, stock/payment/ledger consistency |
| G. Returns, refunds, voids | Return/refund search, approval, voids | Partial/full reversal, refund method, exactly-once effects, stock and finance |
| H. Customers and credit | Customer profile, credit ledger, repayment, archive | Balance math, repayment allocation, history, concurrency, privacy |
| I. Money and cash close | Income, expenses, supplier payments, cash count | Sign/units, cash reconciliation, dates/timezones, sale linkage |
| J. Reports and exports | Sales, inventory, finance, CSV/PDF | Filters, totals vs source data, empty/error states, privacy |
| K. Offline storage and migrations | Drift/SQLite, repositories, transactions, upgrades | Constraints, migrations, durability, corruption/full disk, restore compatibility |
| L. Cloud APIs and Supabase security | Edge Functions, SQL/RPC, RLS, grants, Auth | Authentication, authorization, isolation, validation, least privilege, parity |
| M. Sync and multi-device | Outbox, pull, conflicts, idempotency, cursors, device setup | Offline replay, concurrent changes, ordering, retries, convergence |
| N. Backup, restore, provisioning | Local/cloud backup, restore, new device/business setup | Snapshot completeness, identity mapping, atomicity, restart, recovery |
| O. Android runtime and performance | Permissions, background work, lifecycle, responsiveness | Install/upgrade, force-stop, Doze, WorkManager, startup/navigation, memory |
| P. Device integrations and accessibility | Camera/barcode, Bluetooth/USB printer, notifications, semantics | Permission denial, unavailable hardware, reconnect, print layout, text scaling |
| Q. Release and operations | Build flavors, signing, CI, migrations, diagnostics | Correct environment, reproducible artifact, failure handling, rollback |

This inventory is a starting point, not a cap. Expand it when route/code discovery finds more product surfaces.

## 4. Required workflow for every part

### Establish the baseline

1. Read this plan, assigned part notes, `FINDINGS.md`, `CROSS-CUTTING.md`, relevant feature documentation, and current repository status.
2. Record branch, commit, pre-existing modifications, app version/configuration, device, account role, and backend environment. Never clean or overwrite user changes.
3. Inventory routes/screens, services, repositories, tables, APIs/functions, permissions, tests, and docs in scope.
4. List inaccessible paths and why. Missing device access is an evidence gap, not a pass.

### Trace implementation

For each important workflow trace:

`screen/action → state/controller → use case/domain rule → repository → local transaction → outbox/sync → API/Edge Function/RPC → Postgres/RLS → canonical state → UI`

Inspect normal, validation, error, retry, concurrency, cancellation, and lifecycle branches. Compare local/remote representations, monetary units, timezones, identity keys, and transaction boundaries. Review test assertions, not just test names.

### Test in distinct evidence layers

1. **Source:** what implementation inspection supports.
2. **Automated:** exact command, platform/tools, result, duration, failures/skips.
3. **Local integration:** actual SQLite/repository/API contract behavior.
4. **Physical Android:** device/API, build/SHA, steps, screen/result, redacted logs.
5. **Backend/production:** read-only checks by default; authenticated mutations only in an explicitly designated QA project/business with cleanup.

Never call unit/widget tests end-to-end. They cannot prove camera, printer, Android background, or process-death behavior. A successful debug build is not release verification.

### Close or hand off

Record a finding or a bounded “no issue observed in tested scope.” Update the part file, central ledger, test/evidence links, and relevant product docs. Another person must be able to reproduce the observation.

## 5. Physical-device test protocol

Record date/time/timezone, phone model, Android API, app version/build/SHA, install/upgrade path, network state, relevant battery/power state, account role/business pseudonym, and whether the backend is QA or production. Never include passwords, OTPs, tokens, customer identities, or sensitive financial payloads in shared reports.

### Safe data rules

- Prefer a dedicated QA business with synthetic data. Prefix created records `Codex QA <run-id>`.
- On a real business account, begin with read-only navigation. Mutations may use clearly labeled reversible QA records only. Verify and safely clean those records. Never edit/delete/void/refund existing records as a shortcut.
- Do not send real staff invitations, customer messages, payments, tax filings, or third-party printer/network actions. The user enters passwords/OTPs directly on their device, never in chat.
- Do not run destructive restore, reset, delete, ownership transfer, or production migration tests on a real business. Use isolated fixtures/QA data.
- AWS remains paused; this plan does not authorize AWS provisioning or paid migration work.
- Simulate irreversible external/financial actions or record them as test gaps.

### Scenario matrix

For every applicable feature, cover:

- First use, normal success, invalid input, boundary values, empty state, and repeated action.
- Offline start/mutation; local visibility and persistence after restart.
- Reconnect/sync; exactly one remote effect and matching canonical state.
- Slow/interrupted network, timeout, expired session, and retry where safe.
- Back navigation, background/resume, and process death for high-value workflows.
- Related views/reports and, with QA identities, another authorized device.
- Permission granted, denied, and restored for hardware paths.
- Role/business/location enforcement in both UI and backend.

Mark inapplicable cases `N/A` with a reason. Do not silently omit them. For financial/inventory actions, capture QA before/after balances and verify reversals.

## 6. Execution and findings

Inspect repository guidance before commands. Run focused checks before broad suites when useful. Record exact commands, commit/working-tree state, tool versions, exit code, pass/fail/skip counts, duration, and relevant failure excerpts. Separate environment failures from product defects, but report both. Do not change global configuration/timezone merely to force green results without documenting it.

Severity: **Blocker** (unrecoverable business data loss, cross-business exposure, or widespread core failure); **Critical** (major money/stock corruption, unauthorized access, or key workflow failure without safe workaround); **High** (serious correctness/security/reliability issue); **Medium** (limited workflow defect or misleading state); **Low** (minor usability/maintenance/docs issue); **Observation** (verified behavior or uncertainty without demonstrated defect).

Each finding records: stable ID/part/severity/status; baseline and environment; exact reproduction; observed behavior; expected invariant; impact; evidence; proven root cause; recommended fix; regression/verification needed; related parts and docs. Use `A-001`…`Q-999` per part or existing `Pxx-xxx` deep-code IDs. Cross-cutting IDs use `X-xxx`. Never reuse IDs; link duplicates to the canonical entry.

Evidence must be minimal, timestamped, reproducible, and redacted. Store screenshots/logs in the approved audit artifact location, not source assets. Label it `SOURCE`, `AUTOMATED`, `DEVICE`, `BACKEND`, or `CI`, and state if it is current, historical, or inferred. An advisor warning alone does not prove exploitability; check grants, access paths, and intended service-only use.

## 7. Documentation governance

Documentation maintenance is part of each audit, not a final optional sweep.

1. `README.md` is the concise current product/setup entry point; remove unsupported completion/readiness claims.
2. `PLAN.md` tracks engineering work, not verification results or audit methodology.
3. This file is the canonical product/code/runtime audit protocol.
4. `docs/deep-code-audit/MASTER_PLAN.md` defines detailed source-audit mechanics and links here.
5. Preserve historical audits as evidence. Add a visible `Historical / requires revalidation` notice with original date, branch/SHA/environment, and current-status link. Do not silently rewrite old results as current.
6. Inventory every project document and classify `Current`, `Historical—revalidate`, `Superseded—see <path>`, or `Archive candidate`. Check dates, branches, versions, service state, “complete” language, commands, feature descriptions, and links against the current code/runtime.
7. Remove a document only if it is an exact duplicate, has no unique finding/evidence, and all inbound references are updated. Otherwise mark it historical or superseded.
8. Record every update, supersession, retention, or removal with its reason in the audit report. Add `As of` dates to changed time-sensitive claims.

## 8. Rules for AI handoffs

Every new AI session reads this plan first, then its part file, findings ledger, cross-cutting register, relevant source/docs, and current Git status. State scope and baseline before editing. The repository outranks remembered narrative.

Parallel work is allowed only for non-overlapping parts. Each agent gets a unique part/ID range and owns its own document. A coordinator resolves duplicates, shared changes, and conflicting conclusions. Never have agents mutate the same file independently or run destructive production tests.

```markdown
## Audit handoff
Part / owner:
Baseline branch + SHA:
Build, role, device, backend environment:
Scope and routes/source/docs inspected:
Scenarios and evidence IDs:
Findings opened / updated / closed:
Commands and results (including failures/skips):
Device/backend actions and cleanup:
Docs classified and changes made:
Unverified scenarios and why:
Risks/dependencies:
Next exact action:
```

## 9. Release gates

Recommend release only after all parts have a disposition; no unexplained core coverage gaps remain; no Blocker/Critical finding is open; High findings have an owner, mitigation, and product-owner decision; analyzer, relevant full tests, and release build are recorded against candidate SHA; physical Android install/upgrade and key sales/inventory/money flows are verified; offline mutation → process death/restart → reconnect → one canonical remote effect is observed; backup/restore and isolation are demonstrated on QA data; Supabase policies/grants/functions/Auth match the reviewed baseline; known hardware/OS/cost/plan limits are explicit; and docs/links are current.

Use one of: `Not ready`, `Conditionally ready with listed gaps`, or `Evidence supports readiness for the tested scope`. Scope readiness by version, platform, account type, and scenarios. One phone/account cannot establish readiness for millions of users.

## 10. Current campaign status — 2026-11-19

- Automated baseline observed: `flutter analyze` passed; `flutter test` had 1,083 passed, 1 skipped, 2 failed. Failures were a timezone-assumption assertion and a Windows subprocess invocation of `flutter`; recheck before closure.
- Android: debug APK built and launched on TECNO KI5k / Android 12. A read-only smoke test on the persisted Muhammed owner session was observed; ADB wireless disconnected during further navigation.
- Supabase production was inspected read-only; no live business rows were changed. The Sync & Backup screen showed a possible status mismatch (“Everything is backed up” while no successful backup was recorded); recheck against current source/runtime.
- Authenticated core workflows, safe QA mutations, offline/reconnect sync, restore, multi-device/role boundaries, hardware integrations, and complete route coverage remain unverified.
- Part A source audit found and fixed the `businessSetup` → Essential Settings routing gap; 29 onboarding tests pass. Physical confirmation remains open. See [`product-audit/PART-A-STARTUP-ONBOARDING-NAVIGATION.md`](product-audit/PART-A-STARTUP-ONBOARDING-NAVIGATION.md).
- AWS is paused; no AWS provisioning is in scope.

These are dated observations, not claims about later builds. Update this section and link the detailed audit report at each campaign handoff.
