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
