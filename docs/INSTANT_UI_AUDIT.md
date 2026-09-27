# Fulus Instant UI Audit

**Branch:** `audit/instant-ui`  
**Base:** `main`  
**Scope:** investigate why redesigned screens can flash legacy-looking frames and why navigation can show prolonged loading/white states.

## Product invariant

Fulus is local-first. An authenticated workspace screen must not require cloud sync, network availability, or remote acknowledgement before it can render usable local UI.

Target flow:

`tap route -> route paints immediately -> local Drift state hydrates -> background sync updates local state -> UI reacts`

Not:

`tap route -> async prerequisite -> loading/blank -> screen`

## Findings

### IUI-01 — Primary workspace navigation has an animated selected-state transition
**Severity:** Medium, directly visible in slow motion.

`lib/app/app_shell.dart` uses `AnimatedContainer` for the bottom-navigation selected pill. This can expose the old and new selected states during slow-motion capture. Primary workspace navigation should be immediate.

**Evidence:** `_FulusBottomNavigationItem` animates its selected decoration.

### IUI-02 — Sell has an async location gate before the screen can render its workspace
**Severity:** Critical for perceived instant navigation.

`SellScreen` first awaits `activeLocationIdProvider.future`. While unresolved it returns a Sell skeleton. Only after location resolution does it create the `CartCubit` and proceed to the product/cart workspace.

`activeLocationIdProvider` calls `ResolveActiveLocation`, which can perform:
1. local active-location read;
2. local location existence read;
3. settings stream first-value read;
4. get-or-create default location;
5. persist active location.

This is local work, not cloud sync, but it is still on the route-opening critical path.

### IUI-03 — Sell CartCubit initialization waits for durable draft-cart creation before emitting usable state
**Severity:** Critical.

`CartCubit._init()` awaits `getOrCreateDraftCart(...).withFulusLoadingTimeout()` before subscribing to the draft, items, payments, settings, and catalog streams. Until a draft exists, Sell's current UI has no `CartLoaded` state.

This creates a second async gate after location resolution.

### IUI-04 — Home waits for multiple independent local queries before rendering the redesigned dashboard
**Severity:** High.

Current Home starts:
- `getHeroState`
- `getSecondaryNotices`
- `getTransactions`
- `getAvailableBalance`

The redesigned Home wraps these in nested `FutureBuilder`s and returns the entire `_HomeHeroSkeleton` until hero/notices/activity complete.

The underlying DashboardRepository is local Drift-backed, so this is not evidence of cloud blocking. It is evidence that local queries are incorrectly allowed to gate the primary Home content.

The redesign added extra Home data work, especially recent Money activity and balance, making the first useful dashboard frame more dependent on multiple asynchronous operations.

### IUI-05 — Money waits for expensive local aggregation before showing its primary data
**Severity:** High.

Money starts:
- `getAvailableBalance()`
- `getSummaryAndTransactions()`

and displays skeletons until each future completes.

The real Money repository builds transaction feeds by querying multiple repositories and then converting/aggregating them. `getAvailableBalance()` scans the full configured history from 2000-01-01. `getSummaryAndTransactions()` builds the current period and previous period transaction sets.

These are local operations, but they are substantially more work than a simple single-table local read. The redesigned Money screen therefore has a much larger async critical path than the UI shell itself requires.

### IUI-06 — Stock has an async active-location gate before its product workspace
**Severity:** High.

Stock watches `currentLocationIdProvider` and returns `_StockLocationSkeleton` while location resolution is loading. Only then does it watch products/categories/movements.

This duplicates the same perceived delay pattern found in Sell.

### IUI-07 — Multiple secondary/detail screens intentionally use FutureBuilder-driven skeletons
**Severity:** Medium individually, systemic collectively.

Verified examples include:
- Money History
- Receipt History
- Customer Profile
- Supplier Profile
- Transaction Detail
- Daily Closing
- Employee Detail
- Employees/Deactivated Employees
- Stock Categories
- Reports
- Refund Search/Confirm
- Void Sale
- Notifications
- Backup/restore flows
- printer pairing
- receipt preview

These are not all bugs. A detail screen may genuinely need one local read. The audit requirement is to distinguish acceptable local hydration from screens that unnecessarily replace an already-usable shell with loading.

### IUI-08 — Home/Money/Stock/Sell use different loading strategies
**Severity:** Architectural consistency gap.

There is no single instant-screen contract. Screens currently mix:
- full-screen loading indicators
- skeleton replacement
- section-level skeletons
- FutureBuilder
- Riverpod AsyncValue
- BLoC initialization

This makes perceived performance inconsistent and makes it easy for redesign work to accidentally introduce a blocking gate.

### IUI-09 — Primary navigation is correctly a StatefulShellRoute, but route preservation must be verified
**Severity:** Medium.

The app uses `StatefulNavigationShell`, which is the correct foundation for persistent workspace branches. However, individual screens still perform their own async initialization when their branch becomes active.

The shell preserves branch navigation; it does not automatically make screen data instant. The audit therefore needs to verify state reuse and initialization behavior for each primary branch.

### IUI-10 — Route-transition behavior is separate from local-data hydration
**Severity:** Important diagnostic distinction.

The old-looking UI flash and the loading/white delay are two different classes of issue:

1. route transition/stack rendering can expose a previous route;
2. async screen initialization can replace the destination with a loading surface.

They must be fixed independently.

## What the redesign changed

The repository history confirms that the UI redesign increased the amount of data required by some primary screens.

For Home, the redesign introduced additional activity, notice, and money data into the dashboard and nested multiple FutureBuilders around the redesigned presentation.

For Money, later redesign commits changed the presentation hierarchy while retaining FutureBuilder-based balance/summary/transaction loading.

This does **not** mean the redesign made the database cloud-dependent. It means the redesigned UI made more local asynchronous work part of the first-frame experience.

## What is NOT a finding

- There is no evidence from this audit that normal Home/Sell/Money/Stock display intentionally waits for Supabase sync.
- The underlying Money and Dashboard implementations inspected here are repository/local-data backed.
- Loading indicators used for an actual action (saving, importing, restoring, scanning, submitting a sale) are not inherently wrong.
- Authentication/onboarding gates are legitimate special cases because the user has not yet entered the authenticated workspace.

## Target architecture

### Primary workspace
Home / Sell / Stock / Money / More:

`shell -> immediate screen structure -> cached/local state -> reactive local hydration`

### Secondary/detail screen

`route -> immediate header/body structure -> local read -> content`

If there is no existing local value, use a designed skeleton/empty state. Do not make network/sync a prerequisite.

### Actions

`tap -> immediate local mutation -> UI update -> durable outbox -> background cloud sync`

Action-level spinners remain acceptable where the user is explicitly waiting for a local mutation, file operation, hardware operation, or other unavoidable action.

## Next audit pass

Before changing code, inspect and classify every primary/secondary route for:

1. what must exist before the first frame;
2. whether that prerequisite is local, remote, or device-only;
3. whether an existing local value can be displayed first;
4. whether the screen is destroyed/replaced by loading;
5. whether the route/branch is recreated;
6. whether the same data is queried repeatedly by multiple widgets;
7. whether expensive local aggregation can be converted to reactive Drift streams or incremental projections;
8. whether sync/network/auth state accidentally enters the rendering dependency graph.

Only after this classification should we implement the instant-screen architecture.

## Implementation pass 1

The first safe architecture pass now closes the most direct perceived-performance regressions:

- **IUI-01:** primary bottom-navigation selection is now immediate.
- **IUI-10:** ordinary imperative route transitions no longer fade the previous route underneath the destination.
- **IUI-04:** Home no longer withholds the entire redesigned dashboard until activity, notices, balance, and hero futures all complete. Sections can hydrate progressively once the primary hero state exists.
- **IUI-03:** Sell no longer replaces its workspace with a generic spinner while the local CartCubit is hydrating. It keeps a Sell-shaped skeleton visible.
- **IUI-02/IUI-06:** location resolution remains a local prerequisite for the data-bearing Sell/Stock bodies; this is intentionally not hidden behind a fake timeout. The next pass should remove this prerequisite from the first useful frame where a safe cached/bootstrapped location value is available.
- **IUI-05:** Money's local aggregation remains the main performance hotspot and has not been rewritten speculatively. It needs measurement/targeted repository optimization rather than changing financial semantics.

No cloud operation was added to the rendering path. No sync or business behavior was changed.

## Current conclusion

**The screenshots are consistent with a real architecture/performance regression introduced or exposed by the redesigned presentation layer.**

The core problem is not "cloud sync is slow."

The verified problem is:

> **Too much asynchronous local initialization has been placed between navigation and the first useful UI frame.**

The route-transition flash is a separate rendering problem.

No production business logic or sync behavior was changed during this audit.
