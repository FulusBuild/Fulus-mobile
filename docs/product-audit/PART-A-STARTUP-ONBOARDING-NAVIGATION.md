# Part A — Startup, Onboarding, and Navigation

**Status:** Source review and focused automated checks complete; Android runtime cases remain open.
**Audit date:** 2026-11-19
**Baseline:** `b76a0d9a47cd80e46dc0e53b6a508a2093109527` plus the Part A fix in the working tree
**Scope:** App bootstrap, initial route, owner/employee auth gate selection, business setup resumption, onboarding walkthrough progression, shell entry, and route/permission guard structure.

## Evidence reviewed

Source files:

- `lib/main.dart`
- `lib/app/bootstrap.dart`
- `lib/app/router.dart`
- `lib/app/app_shell.dart`
- `lib/app/providers.dart`
- `lib/core/onboarding/onboarding_routing.dart`
- `lib/core/onboarding/onboarding_state.dart`
- `lib/features/auth/presentation/screens/auth_gate_screen.dart`
- `lib/features/auth/presentation/screens/get_started_screen.dart`
- `lib/features/auth/presentation/screens/fulus_account_screen.dart`
- `lib/features/auth/presentation/screens/owner_setup_screen.dart`
- onboarding walkthrough screens and their state transitions

Automated evidence:

- `flutter test test/core/onboarding` — passed, 29 tests.
- `flutter analyze lib/core/onboarding/onboarding_routing.dart test/core/onboarding/onboarding_routing_test.dart` — no issues found.

Device evidence for this pass: unavailable. `flutter devices --machine` could not start `adb.exe` because the sandbox denied creation of `\.android`; a direct check also found no ADB server listening on `127.0.0.1:5037`. A prior campaign observed the welcome screen and Create Account navigation on TECNO KI5k / Android 12, but did not exercise account completion or post-setup onboarding. Treat those observations as historical, not closure evidence for this fix.

## Startup and routing trace

`main()` initializes Flutter, installs error capture, awaits local bootstrap/session restoration, then calls `runApp`. Cloud sync and WorkManager scheduling start afterward so network and scheduler setup do not gate the first Flutter frame. The authenticated workspace uses a `StatefulShellRoute.indexedStack`; the shell gate distinguishes signed-out, employee, unconfigured owner, configured owner walkthrough, and normal shell states. Route redirects check employee permissions for protected Money, Stock, and More paths; owners use the owner exemption.

The signed-out auth gate checks local owner/business/identity state and performs bounded backup discovery. The guided owner path records `businessSetup` before opening account/setup UI. Once the business is configured, the next durable stage must be Essential Settings; later screens advance through first product, navigation intro, first sale, verification, and completion.

## Finding A-001 — New-business walkthrough skipped after setup

**Severity:** Medium
**Status:** Fixed in the working tree; focused regression tests pass.
**Affected code:** `lib/core/onboarding/onboarding_routing.dart`, `test/core/onboarding/onboarding_routing_test.dart`

**Observed behavior:** `GetStartedScreen` persisted `OnboardingStep.businessSetup`. After `OwnerSetupScreen` or the cloud account creation flow successfully created the business, `resolvePostSignInStage` did not handle that step. With the cloud path's default `firstRunPromptSeen == true`, it selected `enterShell`, skipping the guided onboarding screens. With the local path's first-run flag armed, it selected the generic first-run prompt instead of the intended Essential Settings step.

**Expected invariant:** Completing required business setup resumes the same guided walkthrough at Essential Settings, regardless of whether the owner created the business locally or through cloud account provisioning. If setup is incomplete, resume business setup first.

**Fix:** The post-sign-in resolver now maps a configured business with the durable `businessSetup` step to `showEssentialSettings`, before evaluating the generic first-run prompt. The unconfigured-business check remains first, preserving interrupted setup recovery.

**Regression evidence:** Added tests for the configured and unconfigured `businessSetup` cases. The complete onboarding test directory passes (29 tests), and targeted Flutter analysis reports no issues.

**Runtime still required:** Complete a fresh owner signup and local/offline setup on Android. Confirm each enters Essential Settings, force-stop/reopen during setup, and verify the correct step resumes. No real account or data was changed for this source/test fix.

## Observation A-002 — Backup discovery uncertainty could look like “no backup”

**Status:** Mitigated in source; cold-start timing remains unmeasured.

The first-use gate waits for bounded backup discovery. Previously a timeout/error could be treated as an empty result, making the new-account path appear available even though the app could not confirm whether a backup existed. The gate now shows a checking state and, if discovery fails, an explicit retry or “Continue without restoring” choice. A pure routing regression verifies the failure state. This avoids silently equating an unknown result with no backup; it does not reduce the maximum discovery wait or establish physical cold-start performance.

## Other checks and gaps

- Root route is `/`; signed-out users receive `AuthGateScreen` from the shell route. Protected employee routes redirect to `/` when the permission is absent.
- Owner shell entry waits for the local business-configured check. Employee shell entry warms active location and defaults protected tab visibility closed while permissions resolve.
- Primary branches use an indexed stateful shell and no-transition pages; source review supports branch-state retention but does not prove physical frame timing.
- No router/widget integration test was found for signed-out deep links, role-filtered direct navigation, or tab-stack restoration. Add focused widget/device coverage if runtime testing reveals a defect or if route behavior changes.
- Cold/warm startup latency, app restoration from interrupted account creation, device back behavior, and physical deep-link handling remain unverified.

## Handoff

Continue with physical Android verification when ADB is available. Use a QA account/business for new-account mutation tests. Record app SHA/build, phone/API, network state, exact route, screenshot/log evidence (redacted), and whether the step survived process death. Part B owns credential/session correctness; Part C owns role enforcement; Parts O/P own Android lifecycle and device behavior. Do not duplicate those findings here unless a startup/navigation boundary is involved.
