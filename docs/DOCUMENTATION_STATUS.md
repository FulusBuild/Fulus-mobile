# Fulus Documentation Status

**Inventory date:** 2026-11-20
**Canonical upkeep rules:** [`QA_MASTER_PLAN.md`](QA_MASTER_PLAN.md), section 7.

This index prevents point-in-time audits from being mistaken for current verification. Historical records remain available because they contain unique evidence; no document was deleted in this review because exact duplication and lack of unique evidence were not established.

| Document(s) | Classification | Required handling |
|---|---|---|
| `../README.md` | Current entry point, updated 2026-11-19 | Feature descriptions still need ongoing comparison with the current UI; readiness claims now defer to evidence. |
| `QA_MASTER_PLAN.md` | Current protocol | Update the campaign status and link the latest report at each handoff. |
| `product-audit/PART-A-STARTUP-ONBOARDING-NAVIGATION.md` | Current Part A audit, 2026-11-19 | Backup-discovery failure now has explicit retry handling; update after Android and cold-start timing cases. |
| `product-audit/PART-B-AUTHENTICATION-SESSIONS.md` | Current Part B audit, 2026-11-19 | Source and focused automated checks pass; complete listed Android and live-auth scenarios before closing runtime evidence. |
| `product-audit/PART-C-STAFF-ROLES-BUSINESS-LOCATION.md` | Current Part C audit, 2026-11-19 | Source and 67 focused automated tests pass; physical-device, QA mutation, and local Supabase SQL fixture scenarios remain open. |
| `product-audit/PART-D-CATALOG-AND-PRODUCTS.md` | Current Part D audit, updated 2026-11-19 | CSV export and product validation widget coverage added; local migration tests, phone walkthrough, live QA sync, and safe orphan-image cleanup remain open. |
| `product-audit/PART-E-INVENTORY-AND-SUPPLIERS.md` | Current Part E audit, updated 2026-11-19 | Stock rejection compensation is implemented and regression-tested; canonical supplier-ledger cloud support, local Supabase invariants, QA convergence, and phone walkthrough remain open. |
| `product-audit/PART-F-SALES-AND-CHECKOUT.md` | Current Part F audit, updated 2026-11-20 | Focused mobile tests, isolated Supabase financial-fidelity SQL, and Flutter CI passed on merged PR #231; Android checkout/offline-to-sync evidence and production deployment remain outstanding. |
| `product-audit/PART-G-RETURNS-REFUNDS-VOIDS.md` | Current Part G audit, merged in PR #232 and updated 2026-11-20 | G-001–G-008 source/cloud findings are fixed; 61 focused Flutter tests, 1,112 full Flutter tests (1 skipped), targeted Dart analysis, and disposable Supabase migration/SQL CI pass. Deferred handler recovery is directly tested; successful compensation and device/runtime/concurrency/multi-device evidence remain open. |
| `product-audit/PART-H-CUSTOMERS-AND-CREDIT.md` | Current Part H audit, follow-up merged in PR #235 on 2026-11-20 | H-001–H-003 source findings are fixed; focused repository/sync tests, warning widget test, Supabase Migration Chain #878, full Flutter CI, live sync, and multi-device CI pass. Android refresh timing and offline/live-QA authorization evidence remain pending. |
| `product-audit/PART-M-SYNC-AND-MULTI-DEVICE.md` | Current Part M audit, deep pass 2026-11-20 | M-002 feed commit ordering and M-003 filtered cursor pagination fixes are in PR #237; disposable migration CI is pending. Full sync suite: 278 passed, 1 skipped, 1 known Windows subprocess-harness failure. Physical two-phone convergence remains pending. |
| `product-audit/PART-N-BACKUP-RESTORE-PROVISIONING.md` | Current Part N audit, deep pass 2026-11-20 | N-001 honest copy status and N-002 interrupted-restore startup recovery are fixed in PR #237; restore unit suites pass. Android MediaStore/process-death/fresh-install and QA authorization evidence remain pending. |
| `product-audit/PHYSICAL-DEVICE-UX-UI-AUDIT-2026-11-20.md` | Current physical-device UX/UI walkthrough, source fix pass, and full-screen-recording follow-up | UX-001–UX-012 source fixes are merged; 10 baseline focused tests pass. The recording follow-up adds two onboarding widget tests and fixes inaccurate “first product/first sale” claims; updated-build physical-device verification remains pending. |
| `../PLAN.md` | Engineering work plan; historical status text may be stale | Track engineering priorities here; verify each item against current code before execution. |
| `testing/RUNTIME_PRODUCTION_EVIDENCE.md` | Active evidence process; individual workflow evidence is time-sensitive | Recheck the workflow and latest run before citing a pass. |
| `INSTANT_UI_CONTRACT.md`, `architecture/FULUS_RELIABILITY_SLOS.md` | Current intended contracts/targets, not proof of implementation | Keep targets distinct from measured production behavior. |
| `FULL_PRODUCTION_READINESS_AUDIT.md` | Historical snapshot: 2026-09-28, old branch/SHA | Revalidate each open/closed status against the current baseline before relying on it. |
| `INSTANT_UI_AUDIT.md` | Historical branch audit; no current baseline recorded | Reproduce findings on current code/device before calling them open or fixed. |
| `architecture/FULUS_ARCHITECTURAL_BENCHMARK.md`, `FULUS_IMPLEMENTATION_BENCHMARK.md`, `FULUS_BENCHMARK_SOURCE_REVALIDATION.md` | Historical source/benchmark snapshots from Oct 2026 | Update baseline and revalidate conclusions before using as current engineering decisions. |
| `architecture/FULUS_BENCHMARK_HANDOFF.md` | Historical PR handoff | Do not use its PR-open/status statements as current GitHub state. |
| `architecture/location-owned-products-customers-employees.md`, `SYNC_ARCHITECTURE_SIMPLIFICATION.md` | Historical requirement/source audit snapshots | Check current schema, code, and product decisions; retain as design history. |
| `deep-code-audit/PART-01` through `PART-20`, `FINDINGS.md`, `CROSS-CUTTING.md`, `FINAL-REPORT.md` | Historical audit evidence, with mixed branches/SHAs and explicit runtime gaps | Read the deep-audit master; revalidate every status against current branch/SHA. Part numbers are source-audit partitions, not proof all user-facing flows passed. |
| `deep-code-audit/PART-08-PRODUCT-CATALOG.md` | Historical / superseded for current source by Part D | Retained for its unique historical evidence. Its catalog-wide SKU/barcode and local-only photo-sync descriptions no longer match current code; use the current Part D report for 2026-11-19 findings. |
| `ui/modern_workspace_mockup.html` | Design artifact; not an implementation contract | Compare with current product before treating it as intended UI. |

## Review outcome

- Removed: none. No exact duplicate with no unique evidence was proven.
- Updated: README readiness language and generated-code setup wording; engineering-plan relationship; deep-audit master-plan coordination; Part 20 production evidence warning.
- Updated: QA master campaign status and documentation index with Part D; marked Part 08 catalog's superseded statements while retaining its historical evidence.
- Updated: QA master campaign status and documentation index with Part E; clarified in README that supplier ledgers are device-local; retained historical Part 11/Part 10 findings and linked the current inventory report.
- Updated: Part F report and campaign index; added an exact-cent payment equality guard migration, then recorded the successful isolated SQL/CI runs. Android checkout/offline-to-sync evidence and production deployment remain outstanding.
- Updated: Part G report with G-008 duplicate-sale stock idempotency fix, passing disposable Supabase workflow #873 and full Flutter CI #5090; merged in PR #232. Added deferred-handler recovery coverage while retaining successful compensation and device/runtime/concurrency/multi-device evidence gaps. Corrected the Part F report/index to reflect merged PR #231's successful isolated Supabase and Flutter CI runs.
- Updated: A-002 backup-discovery failure UX; D-004 widget coverage and D-006 CSV export; E-001 canonical stock reconciliation and the chosen business-wide supplier-ledger direction. D-005 and E-002 remain backend implementation gaps.
- Updated: Part H report and campaign status; H-001–H-003 source/widget findings are fixed. Follow-up PR #235 and CI run #44741737242 pass full Flutter tests, live sync, and multi-device convergence; APK jobs were skipped, so device/runtime evidence remains pending.
- Added: current Part M and Part N reports based on `main` at `65ef6460f5ed6d20306b34ba509623cd028118c3`. Revalidated sync fencing, financial convergence, owner restore identity, transactional import, and snapshot request behavior. Recorded the Windows nested-Flutter test harness failure, passing Linux CI, and remaining physical-device/QA gaps.
- Added: physical-device UX/UI walkthrough dated 2026-11-20. Recorded confirmed visual/interaction findings separately from source observations and listed unexercised flows. No source changes, automated tests, or business-record writes were made for the UX walkthrough.
- Updated: physical-device UX report with source fix UX-017 for employee invite lifecycle fencing and bounded auth loading. The complete join/login flow still needs isolated-device verification. UX follow-up PR #240 is merged; its earlier CI does not cover this new change.
- Added: product verification master plan and this status index.
- Next sweep: revalidate the historical full readiness/instant UI/benchmark documents against the current commit, then update, supersede, or retain each with explicit evidence and links.

- Updated in deep follow-up: Part M/N reports and campaign status against `main` at `04403935748d3c36894480d62655a0b06585ddf0`. M-002/M-003 source fixes and tests cover same-business feed commit order and filtered cursor pagination. N-001/N-002 source fixes and tests cover truthful Downloads-copy messaging and startup recovery from interrupted restore rename. Corrected stale `DatabaseLifecycle`, backup repository, and X-001 lock-mechanism documentation. Committed as `16ebd722` in PR #237; GitHub checks are pending and the migration contract has not been run locally.
