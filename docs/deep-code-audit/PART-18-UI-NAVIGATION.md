# Part 18 — UI, Navigation & Application State

**Status:** In progress  
**Baseline:** `main` after Part 16 merge `7eecdd59ca0218a2e980dd9b06368543d684efae`

## Pass A — Structural inventory

Inspected:

- `lib/app/router.dart`
- `lib/app/app.dart`
- `lib/app/app_shell.dart`
- `lib/features/home/presentation/screens/home_screen.dart`
- More navigation and settings/customer/printer route definitions
- shell permission projection and session-change refresh
- first-frame/shell gating and active-location warming
- no-transition route pages
- home dashboard hydration/state refresh paths

## Pass B — Navigation correctness

The five primary workspaces are implemented as a `StatefulShellRoute.indexedStack` with persistent bottom navigation. Each branch keeps its own navigation stack.

Route transitions use `NoTransitionPage`, avoiding artificial page animations during primary navigation.

The shell re-runs router authorization when the active session identity or role changes. Protected routes use the same permission provider as the shell instead of relying on a previously-rendered screen to warm permissions.

More subroutes use push navigation where returning to More is the expected behavior, including Customers and Printers. Settings, Employees, Reports and Locations use their intended workspace-level navigation.

## Pass C — Application state and lifecycle

The shell warms the active location before the user begins switching between primary destinations. Home reloads user-sensitive dashboard futures when the session identity, role, or permissions change, preventing a StatefulShellRoute branch from retaining another employee's dashboard state.

Home also refreshes from the shared data-refresh signal and keeps independent dashboard reads concurrent rather than serializing them behind nested FutureBuilders.

### P18-001

**Severity:** Medium  
**Status:** Fixed in source; CI pending.

**File:** `lib/features/home/presentation/screens/home_screen.dart`

**Observed behavior**

The home dashboard rendered six cards for a fully authorized owner:
1. Today's Sales
2. Business Balance
3. Low Stock
4. Customer Credit
5. Reports
6. Sell

Sell was therefore represented twice conceptually: once as the bottom primary navigation destination and once as a separate home card. The Business Balance card also triggered an additional local balance read solely to populate a secondary card.

This conflicted with the product's simplified five-card home contract: each screen should expose only the most important actions/state and avoid unnecessary scanning.

**Fix**

The Business Balance card was replaced by the primary Sell card. The duplicate bottom Sell card was removed, leaving five home cards in the owner view:

- Today's Sales
- Sell
- Low Stock
- Customer Credit
- Reports

The now-unused business-balance hydration was removed from Home, reducing unnecessary local work and state.

**Verification**

Source structure now produces five cards for the fully authorized owner path. CI will verify analyzer/test integrity; visual Android verification remains part of final UI/runtime evidence.

## Pass D — Cross-system trace

```
session identity
  → router redirect / permission projection
  → StatefulShellRoute branch
  → screen state
  → active location
  → repository reads
  → UI refresh signal
```

The critical UI invariant is that navigation and visible state must follow the current authorized identity/location, while primary navigation should not wait on cloud synchronization or unrelated secondary hydration.

## Remaining evidence

- Android visual verification is still required for the five-card Home layout and back-stack behavior.
- Employee/location switching should be physically exercised after the Part 03/04 access model is finalized.
- Instant-navigation evidence should include cold start, branch switching, back navigation, and session switching.
