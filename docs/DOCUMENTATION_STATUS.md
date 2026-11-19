# Fulus Documentation Status

**Inventory date:** 2026-11-19
**Canonical upkeep rules:** [`QA_MASTER_PLAN.md`](QA_MASTER_PLAN.md), section 7.

This index prevents point-in-time audits from being mistaken for current verification. Historical records remain available because they contain unique evidence; no document was deleted in this review because exact duplication and lack of unique evidence were not established.

| Document(s) | Classification | Required handling |
|---|---|---|
| `../README.md` | Current entry point, updated 2026-11-19 | Feature descriptions still need ongoing comparison with the current UI; readiness claims now defer to evidence. |
| `QA_MASTER_PLAN.md` | Current protocol | Update the campaign status and link the latest report at each handoff. |
| `product-audit/PART-A-STARTUP-ONBOARDING-NAVIGATION.md` | Current Part A audit, 2026-11-19 | Update after physical Android cases and any follow-up fixes. |
| `product-audit/PART-B-AUTHENTICATION-SESSIONS.md` | Current Part B audit, 2026-11-19 | Source and focused automated checks pass; complete listed Android and live-auth scenarios before closing runtime evidence. |
| `product-audit/PART-C-STAFF-ROLES-BUSINESS-LOCATION.md` | Current Part C audit, 2026-11-19 | Source and 67 focused automated tests pass; physical-device, QA mutation, and local Supabase SQL fixture scenarios remain open. |
| `product-audit/PART-D-CATALOG-AND-PRODUCTS.md` | Current Part D audit, 2026-11-19 | Source and 105 focused automated tests pass; local Supabase migration tests, phone walkthrough, live QA sync, and product-export requirement remain open. |
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
- Added: product verification master plan and this status index.
- Next sweep: revalidate the historical full readiness/instant UI/benchmark documents against the current commit, then update, supersede, or retain each with explicit evidence and links.
