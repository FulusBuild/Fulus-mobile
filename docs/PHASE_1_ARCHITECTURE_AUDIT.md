# Phase 1 — Repository & Architecture Audit

Date: 2026-09-27
Base: `main`
Audited commit: `882f02cae912a06cf0bfc0f3151ee5a84a56bebd`

## Scope

This document records the Phase 1 repository and architecture audit required by `PLAN.md`.

Phase 1 covers:

- repository structure and current `main`
- important recent Git history
- obsolete/duplicate/unfinished/unused code
- Flutter/Dart and project configuration
- Android release configuration
- dependencies
- navigation, state management, data access, APIs, authentication, persistence
- canonical implementations
- production blockers

No application behavior was changed as part of this audit pass.

## 1. Repository map

```
Fulus-mobile/
├── .github/workflows/       CI/CD and Supabase automation
├── android/                 Android/Gradle release project
├── assets/                  packaged assets
├── design/                  design artifacts
├── docs/                    documentation
├── lib/
│   ├── app/                 bootstrap, DI, router, shell, gates
│   ├── core/                cross-cutting concerns and business rules
│   ├── data/
│   │   ├── local/           Drift/SQLite persistence
│   │   ├── remote/          Dio/API/Supabase-facing adapters
│   │   └── repositories/    concrete repository implementations
│   ├── device_services/     camera, scanning, printing
│   ├── domain/
│   │   ├── entities/        business/domain models and DTOs
│   │   ├── repositories/    repository contracts
│   │   └── usecases/        domain actions/use cases
│   ├── features/             feature UI/application code
│   ├── shared/               reusable UI/components
│   └── sync/                 durable queue, engine, handlers, retry/conflict logic
├── supabase/                 migrations, functions, tests
├── test/                     unit, repository, feature, sync, device and shared tests
├── tool/                     project/E2E tooling
├── pubspec.yaml              dependency/configuration manifest
├── pubspec.lock              committed dependency resolution
├── PLAN.md                   production engineering plan
└── README.md                 product/architecture documentation
```

## 2. Current architecture

### Application bootstrap

`lib/main.dart` initializes:

1. Flutter bindings and global error capture.
2. Android WorkManager scheduling.
3. device/form-factor configuration.
4. diagnostics.
5. `bootstrap()`.
6. diagnostic upload.
7. background-sync configuration.
8. `UncontrolledProviderScope` with the bootstrap-created Riverpod container.

### Dependency injection / composition root

`lib/app/bootstrap.dart` is the composition root.

It constructs the local database, secure storage, API client, authentication repositories, business repositories, remote endpoints, sync queue, sync handlers, sync engine, sync triggers, device services, and Riverpod provider overrides.

This is a real composition root rather than screen-level service construction for the main application graph.

### Navigation

`lib/app/router.dart` is the canonical GoRouter configuration.

The main product shell uses `StatefulShellRoute.indexedStack` with five top-level destinations:

- Home
- Stock
- Sell
- Money
- More

Authentication/onboarding is gated through `_ShellGate`, with route permissions checked for protected More routes.

There are deliberate imperative `Navigator.push` exceptions for onboarding and some Sell flows. These are currently documented as intentional, but they create two navigation mechanisms that must remain explicitly bounded.

### State management

Two state-management systems are active:

- Riverpod: app-wide dependency injection, session, repositories, settings, streams/futures and many UI providers.
- flutter_bloc: the Sell/cart flow uses `CartCubit`, `BlocProvider`, and BLoC widgets.

This is not merely a dependency left in pubspec: `flutter_bloc` is actively imported by Sell screens/widgets.

### Persistence

The application is local-first.

- Drift/SQLite is the device persistence layer.
- Repositories sit between domain contracts and persistence.
- Sync writes durable outbox/queue state and reconciles with the backend asynchronously.
- Secure storage is used for device/auth-sensitive material.
- SharedPreferences is used for lightweight persisted settings/cursors.

### Remote/backend layer

Remote access is concentrated under `lib/data/remote/`.

The app uses Dio through `ApiClient` and has dedicated endpoint/API adapters for business data and Fulus backend functions.

Supabase functions/migrations/tests are kept under `supabase/`.

### Synchronization

The sync architecture is a separate subsystem:

- `SyncQueue` for durable work.
- `SyncEngine` for queue draining.
- per-entity sync handlers.
- retry policy.
- conflict resolution.
- execution lease.
- foreground triggers.
- Android WorkManager recovery.
- canonical reconciliation adapters.

This is materially more complex than ordinary CRUD networking and should remain isolated from presentation code.

## 3. Canonical implementation map

| Concern | Canonical implementation found | Audit status |
|---|---|---|
| App entry | `lib/main.dart` | Present |
| DI/bootstrap | `lib/app/bootstrap.dart` | Present |
| App state/DI | Riverpod providers | Present, but BLoC also active |
| Navigation | `lib/app/router.dart` / GoRouter | Present |
| Shell | `lib/app/app_shell.dart` | Present |
| Local DB | Drift `AppDatabase` | Present |
| Repository contracts | `lib/domain/repositories/` | Present |
| Repository implementations | `lib/data/repositories/` | Present |
| Remote HTTP | Dio/`ApiClient` + endpoint adapters | Present |
| Sync queue | `lib/sync/sync_queue.dart` | Present |
| Sync engine | `lib/sync/sync_engine.dart` | Present |
| Background sync | WorkManager scheduler | Present |
| Money repository | `RealMoneyRepositoryImpl` via provider | Canonical real implementation |
| Mock Money repository | `MockMoneyRepository` | Dead/reference code still present |
| Sell/cart transient state | `CartCubit` | Active second state-management system |

## 4. Findings

### F1 — Two active UI state-management systems

**Evidence:** `flutter_bloc` is a direct dependency and is actively imported by `CartCubit`, `SellScreen`, `CartScreen`, `PaymentScreen`, `QuickSaleSheet`, and `CustomerPickerSheet`. Riverpod is simultaneously the application-wide DI/state system.

**Risk:** This creates two lifecycle/ownership models in presentation code. It increases the chance of duplicated state, provider/cubit synchronization bugs, and inconsistent architectural conventions.

**Disposition:** Production architecture blocker for canonicalization, not an immediate runtime failure.

**Recommended Phase 1 action:** Decide whether BLoC remains intentionally isolated to the Sell/cart state machine or migrate it to the canonical state system. Do not perform a broad rewrite until the existing CartCubit lifecycle and tests are mapped.

### F2 — Dead mock Money implementation and production debug hooks remain in source

**Evidence:** `MockMoneyRepository` and `mock_money_data.dart` remain in `lib/features/money/data/`. Current provider construction uses `RealMoneyRepositoryImpl`, and the repository documentation states that the mock is no longer constructed.

Additionally, Money screens still contain `_toggleSimulatedError()` code that checks whether the injected repository is a `MockMoneyRepository`.

**Risk:** Dead production source increases maintenance surface and can preserve obsolete assumptions. Debug simulation paths inside production screens can become accidental behavior if the implementation changes later.

**Disposition:** Production cleanup blocker.

**Recommended action:** Verify all mock references/tests first, then remove or move the mock/debug-only implementation to an explicit test/dev boundary.

### F3 — Navigation has two mechanisms

**Evidence:** GoRouter is canonical for the main application, but onboarding and selected flows deliberately use raw `Navigator.push`/MaterialPageRoute.

**Risk:** Two navigation stacks/ownership models can produce stale-route, back-navigation and transition bugs. The repository already contains defensive code specifically around these interactions.

**Disposition:** Architecture risk requiring explicit boundaries.

**Recommended action:** Map every imperative navigation call. Keep only cases that genuinely must exist outside the GoRouter shell; convert accidental exceptions to named GoRouter routes.

### F4 — Release CI is not equivalent to release validation on the current main commit

The current `main` commit's latest `Fulus Mobile CI` run is successful.

Verified job results:

- dependency resolution: success
- code generation: success
- static analysis: success
- Flutter tests: success
- migration filename integrity: success

However, the same run skipped:

- live sync contract test
- debug APK build
- multi-device convergence test
- release APK build

Therefore, a green CI result on this commit is **not evidence of a verified release artifact**.

**Disposition:** Production blocker to track, although the required full CI/CD gate belongs to Phase 9.

### F5 — Main branch is currently unprotected

GitHub reports `main` as unprotected with required status-check enforcement off.

**Risk:** Changes can reach the production source branch without an enforced review/CI gate.

**Disposition:** Release-process blocker.

**Recommended action:** Define the intended branch/review policy before production release. Do not silently change repository governance during this architecture pass.

### F6 — Dependency surface is large and needs a package-by-package justification

The current direct dependency list includes Riverpod, flutter_bloc, go_router, Drift/SQLite, Dio, WorkManager, camera/scanning, printing, file picking, notifications, secure storage, biometric auth, sharing, device/app metadata and multiple serialization/code-generation packages.

The dependencies are not obviously all unnecessary: many are demonstrably used. However, Phase 1 requires an explicit dependency audit rather than assuming the current manifest is minimal.

**Disposition:** Audit item still open.

**Next verification:** classify each direct dependency as core/runtime, device integration, build/code generation, test-only, legacy, or removable.

### F7 — Android release configuration is explicitly pinned but needs release-artifact verification

Verified:

- compile SDK: 36
- NDK: 27.0.12077973
- Java/JVM target: 17
- AGP: 8.9.1
- Kotlin: 2.1.0
- Gradle wrapper: 8.11.1
- min SDK: 26
- release builds require `android/key.properties`
- release signing is explicitly separated from debug signing

This is a deliberate release configuration, not the untouched Flutter default.

The remaining question is artifact-level proof: the current green main CI run skipped the release APK build.

## 5. Recent history observations

Recent `main` history is heavily concentrated on production hardening, sync reliability, CI/build infrastructure and generated dependency state.

The latest commits include:

- durable sale queue retry testing
- CI lockfile handling
- committed dependency lockfile
- release-gate changes
- live convergence gating
- sale response-loss/idempotency tests
- release API/build-number hardening
- committed Gradle wrapper
- release APK test gating

This indicates the repository has recently undergone substantial production-hardening work. Phase 1 therefore needs to avoid re-litigating already-tested sync fixes unless architecture evidence shows they conflict with the current canonical structure.

## 6. Open work that must be considered during Phase 1

Current open PRs include:

- #86 — prominent Money card icon geometry
- #85 — Home Sell/Reports card refinement
- #71 — location switching/isolation

These branches are not part of the audited `main` commit unless merged. Phase 1 should treat `main` as the source of truth and audit open branches separately before deciding whether any of their changes become canonical.

## 7. Initial production blockers

### Blocker A — Canonical state-management decision

BLoC and Riverpod are both active.

### Blocker B — Dead mock/debug Money code

Mock Money implementation and simulated-error hooks remain in application source even though the real repository is canonical.

### Blocker C — Release validation gap

Current green main CI does not build/validate the release APK on this commit.

### Blocker D — Branch governance

`main` has no enforced branch protection/status checks.

### Risk E — Mixed navigation model

Imperative Navigator usage is intentionally present but must be bounded and audited.

### Open audit item F — Dependency minimization

A complete direct-dependency classification is still required.

## 8. Phase 1 remaining work

The audit is **not declared complete yet**.

Next:

1. Finish direct dependency classification.
2. Enumerate all feature/application directories and identify duplicate/legacy screen implementations.
3. Map every GoRouter route against actual screen ownership.
4. Map every imperative Navigator call.
5. Map Riverpod providers and BLoC/Cubit ownership.
6. Trace the main startup/auth/onboarding path from `main.dart` through `bootstrap.dart`, `app.dart`, router and shell.
7. Verify local persistence boundaries and repository ownership.
8. Review Android release files and CI release conditions together.
9. Cross-check findings against tests and recent Git history.
10. Produce the final Phase 1 blocker list and only then begin Phase 2 or Phase 1 cleanup changes.

## Audit rule

No architectural rewrite is justified merely because a different pattern would be cleaner. Changes must be tied to a verified duplicate, obsolete path, production risk, or missing invariant.


## 9. Completed Phase 1 cross-checks

### Dependency classification

Direct dependencies were checked against repository imports/usages rather than judged from the manifest alone.

**Core application/runtime:** Riverpod, go_router, Drift/SQLite, Dio, secure storage, connectivity, SharedPreferences, path/path_provider, ULID, Equatable, JSON/Freezed annotations, crypto and cryptography.

**Device/platform integrations:** local_auth, WorkManager, camera, mobile_scanner, permission_handler, file_picker, local notifications, share_plus, Bluetooth/USB printing, printing, app_links, package_info_plus and device_info_plus. These have concrete source usage in the current tree.

**Active second state-management dependency:** flutter_bloc is demonstrably used by the Sell/cart flow and is not dead.

**Potential cleanup candidate:** cupertino_icons appears in the manifest/lockfile but repository search did not identify an application source import. Verify with a final generated/import check before removal.

### Navigation audit

GoRouter remains the canonical application router. Imperative navigation is present in deliberate boundary cases: onboarding/auth flows outside the shell branch tree; Sell/cart flows that preserve an active CartCubit; shared barcode/photo capture utilities that return a value; and restore/account flows.

The conclusion is not that all Navigator usage is accidental. The current boundary is: GoRouter owns durable application destinations, while imperative Navigator is used for transient/value-returning and some pre-shell flows. The codebase contains defensive helpers because both mechanisms coexist.

**Disposition:** keep the boundary explicit for now; do not perform a mass navigation rewrite. The Sell/cart state-machine flow needs lifecycle tests mapped before changing ownership.

### State ownership audit

Riverpod is the canonical application dependency/state layer. BLoC is a contained exception for the Sell/cart state machine: CartCubit, BlocProvider, and cart/payment/quick-sale/customer-picker consumers. No evidence justifies declaring BLoC globally obsolete, but the bounded exception should be documented before further feature growth.

### Startup/auth/onboarding path

Verified ownership: main.dart → bootstrap() → bootstrap-created Riverpod container → FulusApp → canonical appRouter → _ShellGate → authenticated shell or onboarding/auth gate.

main.dart also reconciles WorkManager with persisted sync configuration after bootstrap. Diagnostics start after the authenticated API client and cloud connection state exist. Router-level permission checks use the app-scoped session permission provider, so hidden navigation controls are not the only access boundary.

### Persistence ownership

The local-first boundary is coherent: Drift/SQLite owns durable business data and sync queue state; repositories provide domain-facing access; secure storage holds sensitive local/auth material; SharedPreferences holds lightweight non-sensitive settings; remote adapters remain separate; sync handlers coordinate durable local changes with backend reconciliation. No second general-purpose database layer was found in the audited paths.

### Legacy/duplicate implementation findings

The clearest verified obsolete production-source candidates are:
1. MockMoneyRepository plus generated mock Money data, because the real provider uses RealMoneyRepositoryImpl and current source documentation says the mock is no longer constructed.
2. Money-screen simulated-error hooks tied specifically to MockMoneyRepository.
3. cupertino_icons as a direct dependency with no application import found by repository search.

These should be cleaned in a separate controlled change after tests and references are explicitly checked. They should not be mixed into this documentation-only audit commit.

## 10. Final Phase 1 blocker/risk classification

### Production blockers

**P1 — Release artifact validation is incomplete on green main CI.** The latest successful main CI run does not execute release APK, debug APK, live sync contract, or multi-device convergence jobs.

**P2 — Main branch has no enforced protection/status checks.** This is a repository governance/release-control issue rather than an application runtime defect.

**P3 — Canonical state-management policy is undocumented.** Riverpod is the application-wide system while BLoC is active for Sell/cart. The implementation is bounded, but the boundary should be explicit before further feature growth.

### Cleanup blockers

**C1 — RESOLVED.** The obsolete Money mock repository/data and production debug hooks were removed after verifying the real repository is the canonical provider.

**C2 — RESOLVED.** `cupertino_icons`, `freezed_annotation`, and the unused `freezed` generator dependency were removed after repository usage verification; the lockfile was synchronized.

### Architecture risks

**R1 — Mixed navigation mechanisms.** The coexistence is intentional in several places, but every imperative flow should remain limited to transient/value-returning/pre-shell cases.

**R2 — Large composition root.** bootstrap.dart constructs a substantial application graph. This is appropriate for explicit DI, but changes should preserve ownership boundaries rather than moving construction into feature widgets.

## 11. Phase 1 conclusion

The repository has a recognizable production architecture with a real composition root, canonical GoRouter shell, repository/data boundaries, durable local persistence and an isolated sync subsystem.

The audit did not find evidence that a broad architectural rewrite is required.

The highest-value Phase 1 outcomes are instead: close verified dead/obsolete source (now completed); document the bounded BLoC exception; keep GoRouter canonical while preserving legitimate transient Navigator flows; classify/remove unused dependencies (completed for the verified candidates); and strengthen release validation and branch governance in the appropriate later production-readiness phase.

No application behavior was changed by the audit itself.
