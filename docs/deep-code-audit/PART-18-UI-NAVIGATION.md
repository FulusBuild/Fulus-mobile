# Part 18 — UI, Navigation & Application State

## Scope
This pass audits authenticated workspace rendering, route ownership, navigation state, permission-aware navigation, first-frame behavior, branch preservation, back-stack safety, and local hydration.

## Baseline
- Main baseline: `3f68bcc54907e894fa57ac61962a4cd4b5c5c081`
- Audit branch: `audit/p18-ui-navigation`
- The current main tree already contains the five-branch `StatefulShellRoute.indexedStack` architecture and `NoTransitionPage` route wrapper.

## Structural inventory

### Navigation
- `lib/app/router.dart`
  - `GoRouter` with named routes.
  - `StatefulShellRoute.indexedStack` for Home, Stock, Sell, Money, More.
  - `_fulusNoTransitionPage` removes ordinary transition animation.
  - asynchronous redirect enforces employee permissions for protected routes.
  - `_ShellGate` owns authenticated-shell entry and interrupted onboarding recovery.
  - `_MoreScreen` owns More's secondary navigation.
- `lib/app/app_shell.dart`
  - `FulusAppShell` persistent workspace shell.
  - `_FulusBottomNavigationBar` uses `goBranch` and preserves branch state.
  - offline banner is independent of route rendering.
- `docs/INSTANT_UI_CONTRACT.md`
  - defines the first-useful-frame and progressive-local-hydration invariant.

### Primary branches
The branch order is explicitly:
1. Home
2. Stock
3. Sell
4. Money
5. More

The app-shell branch constants match that order: Home=0, Stock=1, Sell=2, Money=3, More=4.

### Route permission boundary
The router applies permission checks to Money, Stock write/configuration routes, More customers/employees/reports/settings/printers/sync, while the More hub, notifications, and diagnostics remain accessible to signed-in employees. Owner sessions use the owner exemption.

## Pass A — Structural findings

### A-001 — No concrete source defect found
The current route tree does not reproduce the earlier class of incorrect back destinations observed in prior UI work. Customer routes under Money are nested under the Money branch; the More customer routes are separately nested under More. Printer routes exist in both More and Settings with distinct route names.

No speculative route rewrite is justified.

### A-002 — No concrete primary-navigation defect found
The shell uses indexed-stack branches and `goBranch`, so branch state is retained rather than reconstructed on every bottom-nav tap. Primary pages use `NoTransitionPage`, matching the Instant UI contract.

## Pass B — Function/class audit

### `_FulusBottomNavigationBar._select`
- Uses `navigationShell.goBranch(branch, initialLocation: currentIndex == branch)`.
- Selecting another branch preserves that branch's stack.
- Selecting the already-active branch returns it to its branch root, which is standard workspace-tab behavior.

### `_ShellGate`
- Signed-out sessions render `AuthGateScreen`.
- Employee sessions enter the shell after warming active location and resolving permission state.
- Owner setup is held behind a local business-configured check because exposing the business shell before setup completion would violate routing correctness.
- Active-location warming starts as soon as the shell is entered.

### Router redirect
- Protected deep links are permission-checked against the app-scoped permission provider.
- Owner sessions bypass employee permission lookup.
- Failing the permission lookup does not grant access; the provider's non-throwing value is used in UI, while the redirect awaits the provider future for actual navigation enforcement.

## Pass C — First-frame / branch-state audit

The Instant UI contract is already implemented in the current tree:
- primary routes use no-transition pages;
- StatefulShellRoute preserves branch state;
- Home hydrates local dashboard sections independently;
- Sell and Stock show useful workspace structure while authoritative location/cart readiness resolves;
- Money avoids blocking the workspace on full-history aggregation;
- More is a static navigation structure.

A repository-wide search still finds FutureBuilder/CircularProgressIndicator usage in secondary routes. These are not automatically defects: several represent explicit action/device/file operations or content hydration beneath an already-painted route structure. The audit therefore does not replace them wholesale.

## Pass D — Cross-system audit

### Navigation → authorization
Direct/deep-link navigation is checked by the router, but UI visibility is not treated as the security boundary. Repository/cloud authorization remains separately responsible for mutation enforcement.

### Navigation → local state
Workspace rendering is local-first. Sync is not a prerequisite for the primary shell.

### Navigation → location
The shell warms the authoritative active-location provider. Sell/Stock retain the resolver rather than guessing a location to shave a frame.

### Navigation → employee state
Employee sessions receive a permission-filtered shell. Money visibility is derived from `Permission.viewMoney`; protected More routes are checked again by redirect.

## Findings / gaps

### P18-001 — Medium — Runtime evidence gap
**Observed:** Source inspection shows the intended no-transition/indexed-stack/progressive-hydration architecture, but repository tooling does not provide evidence that all cold/warm navigation paths were physically exercised on Android.

**Expected invariant:** Home, Sell, Stock, Money and More should paint their useful structure immediately, branch switching should preserve intended state, and offline/delayed-local-hydration conditions should not introduce blank/white/spinner gates.

**Root cause:** Device/runtime visual behavior cannot be proven from source and Dart unit tests alone.

**Fix:** No speculative source change. Collect Android runtime evidence covering cold start, warm branch switching, offline mode, delayed local hydration, back navigation from More customers/printers/settings, and employee permission-filtered navigation.

**Regression:** Keep existing Instant UI and router tests; add only scenario-specific tests where runtime evidence identifies a concrete defect.

**Verification:** Pending Android runtime execution and final CI.

## Cross-checks

- Reviewed `docs/INSTANT_UI_CONTRACT.md` and `docs/INSTANT_UI_AUDIT.md`.
- Reviewed `lib/app/router.dart` and `lib/app/app_shell.dart`.
- Cross-checked customer and printer route duplication across Money/More/Settings.
- Cross-checked employee permission routing against the shell's permission-filtered navigation.
- No route rewrite made solely from historical bug memory.

## Current conclusion

No new high-confidence UI/navigation source defect is proven in this source pass.

The remaining Part 18 item is runtime evidence, not an excuse to rewrite stable navigation. The audit remains open until the required device/runtime checks and final CI evidence are collected.
