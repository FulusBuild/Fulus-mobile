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


## Implementation pass 2 — Instant UI Contract established

The project now has an explicit engineering contract in `docs/INSTANT_UI_CONTRACT.md`. The contract defines first useful frame, progressive local hydration, navigation immediacy, sync separation, location correctness, state reuse, loading/error rules, and completion criteria.

Pass 2 also removes the remaining Home hero future as a first-useful-frame gate. Home now paints the complete dashboard structure immediately and uses `—` for values whose local data has not hydrated yet; those values replace in place as their local futures complete. This avoids showing a full dashboard skeleton merely because the hero query is still running.

The Money, Sell, and Stock screens already expose their destination structure while their local data is loading. Their remaining work is optimization of the data-bearing hydration path, not hiding the workspace behind a generic spinner.


## Verification pass 3 — shell preservation and secondary-route classification

The router was re-checked on the Instant UI branch. Primary Home/Stock/Sell/Money/More routes are `StatefulShellRoute.indexedStack` branches and use `NoTransitionPage`; this confirms the navigation architecture already provides branch preservation and immediate primary route pages. The remaining work is therefore screen initialization/hydration, not replacing the shell architecture.

Secondary FutureBuilder routes were reclassified: report tabs, customer/supplier profiles, transaction/refund detail, employee detail, and similar screens already expose their route/header structure and use shaped loading or section-level states. These should be improved selectively where they unnecessarily replace useful content, rather than through a blanket FutureBuilder rewrite. Action/restore/hardware routes remain legitimate async-operation cases.

The contract is now the governing rule for future fixes: no speculative global loading-framework rewrite; fix only proven critical-path gates and preserve business/location/financial correctness.


## Implementation pass 4 — Sell local workspace hydration

- **IUI-03 reduced:** Sell no longer waits for the durable draft cart before subscribing to safe local workspace data. The product catalog and business settings now hydrate immediately after the verified location is known.
- Added CartHydrating: the Sell workspace can render the real local product catalog while the durable draft cart is being resolved.
- Cart mutations remain gated behind CartLoaded, so no product/payment write can occur without a verified durable draft cart.
- Location isolation is unchanged: ResolveActiveLocation remains the prerequisite for creating the location-scoped CartCubit.
- Draft/cart streams still begin only after getOrCreateDraftCart returns, preserving durable-cart correctness.
- This is a targeted hydration change, not a replacement of the existing cart repository or location architecture.


## Verification pass 5 — Money and full-route loading sweep

The Money workspace was re-inspected before changing its financial aggregation path.

Findings:
- The visible Money structure already paints immediately; balance, summary, and recent activity hydrate independently through shaped skeletons/section states.
- The real repository is local/Drift-backed. There is no cloud/sync prerequisite in the Money rendering path.
- `getAvailableBalance()` is still the main data-performance hotspot: it builds the unified transaction feed from 2000-01-01 and therefore loads substantially more data than the first useful Money frame requires.
- `getSummaryAndTransactions()` similarly performs several independent local reads and aggregation.
- A direct replacement with approximate/cached financial values would violate the contract. No speculative financial projection or correctness shortcut was introduced.
- The next Money optimization must be measured and repository-level: preferably a maintained/reactive local projection or targeted aggregate queries, with tests proving exact financial semantics.

A repository-wide FutureBuilder sweep also reconfirmed that secondary routes fall into two different classes:
1. legitimate action/device/file flows where waiting is inherent to the operation;
2. local detail/report/history routes where the route/header already paints and only the content hydrates.

The second class remains the focus for selective improvements. A blanket FutureBuilder rewrite is explicitly rejected because it would change behavior without proving a performance benefit.

Current remaining Instant UI work:
- **Sell:** location resolution is still a safe local prerequisite; continue only if a verified cached/bootstrapped location can be introduced without weakening isolation.
- **Stock:** same location-resolution question; its header and workspace skeleton already paint while location resolves.
- **Money:** measured/proven optimization of expensive local aggregation.
- **Secondary routes:** finish selective first-frame checks on the remaining detail/history/report routes and action-vs-hydration classification.
- **Navigation-wide verification:** cold/warm navigation, branch switching, offline state, delayed local hydration, and error isolation across all normal routes.
- **Final CI verification:** no Instant UI completion claim until the final implementation is green.

This pass intentionally makes no speculative financial or location architecture change.


## Implementation pass 6 — semantic refresh continuity

A review of the progressive-refresh changes found one subtle correctness/UX issue: preserving the previous result is correct during an ordinary refresh, but it is misleading when the user changes the query itself.

For Money History, changing search text, type, category, or period now starts a fresh visible-data state. The destination structure remains painted, but the previous query's transactions are not shown underneath the new query while it hydrates. Ordinary pull-to-refresh and app-wide data-refresh signals continue to preserve the current list and show an inline refresh notice.

This establishes the required distinction:

- **same query, refresh:** preserve visible local data and hydrate in place;
- **new query/filter/period:** keep the route structure, but hydrate the new result rather than displaying semantically stale data.

The change does not alter repository queries, financial semantics, authorization, or location isolation.

## Remaining closure items after pass 6

The audit is not yet declared complete.

1. **Sell/Stock location path:** still requires authoritative `ResolveActiveLocation`; no safe synchronous cached-location source has been proven, so the resolver has not been bypassed.
2. **Money aggregation:** still requires measured repository-level optimization. Exact financial semantics must be preserved.
3. **Secondary routes:** remaining detail/history/report screens need selective verification of post-action reload continuity and semantic refresh behavior.
4. **Runtime verification:** cold start, warm branch switching, offline rendering, delayed local hydration, and isolated local errors still need device/runtime validation.
5. **CI:** completion requires verification of the final Flutter CI run for the final implementation head.

Vercel deployment status is intentionally not treated as UI correctness or Flutter CI evidence.


## Implementation pass 7 — secondary report semantic refresh

Reports had the same subtle refresh-continuity issue previously found in Money History: the shared report tab builder correctly preserves visible data during ordinary refresh, but changing the report period also replaced its future while retaining the previous period's report data. That could temporarily show semantically stale numbers under the newly selected period.

Report tabs are now keyed by the resolved report period. A period change creates a fresh tab data state while retaining the already-painted report structure and loading skeleton; ordinary data-refresh signals keep the existing report visible while the new local report hydrates. This preserves the distinction between same-query refresh and a new semantic query without changing repository queries, permissions, location isolation, or financial calculations.


## Implementation pass 8 — re-audit fixes

A second implementation audit checked the actual branch rather than relying only on the audit notes.

### Fixed

- Removed Home's unused activity query. Home no longer performs a money-history read that is not consumed by the current dashboard.
- Home local hydration now distinguishes loading/error from valid zero values. Hero, notices, and cash failures no longer silently become misleading dashboard metrics such as zero low-stock items or zero customer credit.
- Money now starts summary and recent-activity reads independently and concurrently. Recent activity no longer waits for the summary aggregation to finish before it can render.
- Reports Cash Flow no longer falls back to a generic spinner; it uses the same shaped loading treatment as the surrounding report workspace.

### Deliberately preserved

- Sell and Stock authoritative active-location resolution remains intact. Their useful workspace/skeleton is shown while the resolver completes; the resolver is not bypassed without a proven safe cached-location source.
- Exact all-history Money balance semantics remain intact. No approximate cache or financial shortcut was introduced.
- Secondary FutureBuilders that represent route-local detail hydration, explicit file/device/action work, or already-painted report/detail sections remain selective rather than being replaced wholesale.

### Re-audit findings

The previous audit incorrectly described Home activity as an active dashboard dependency even though the current dashboard did not consume it, and it treated failed Home section futures as harmless null state. Both were corrected.

The current target remains:

**tap -> screen immediately -> local data hydrates -> UI updates -> cloud sync independently**

Final closure still requires CI green and runtime/cold-warm verification.


## Implementation pass 9 — Settings workspace first-frame isolation

The Settings route was re-audited against the strict secondary-route contract: route/header/body structure should paint immediately, while profile-dependent content hydrates locally inside its own section.

Previously, the entire Settings body was gated by the business-profile FutureBuilder. A delayed or failed business-profile read therefore replaced the whole settings workspace with a loading/error state, even though Account & Backup, Fulus Cloud, Security, and Account sections did not depend on that profile read.

The gate is now narrowed to the Business section only:

- Settings list structure and all independent action tiles paint immediately.
- The Business section header paints immediately.
- Business profile data hydrates inside that section with a shaped skeleton/error state.
- A profile read failure no longer blocks unrelated settings actions.
- No authorization, persistence, or business-settings semantics were changed.

This closes the identified Settings first-frame architecture issue without introducing a global loading abstraction.

## Remaining closure items after pass 9

1. **Sell/Stock location path:** authoritative active-location resolution remains intentionally intact until a synchronous cached-location source is proven safe.
2. **Money aggregation:** exact all-history balance calculation remains the main repository performance hotspot; optimize only with proven exact invalidation/projection semantics.
3. **Secondary routes:** continue selective runtime verification of post-action reload continuity and semantic refresh behavior.
4. **Runtime verification:** cold start, warm branch switching, offline rendering, delayed local hydration, and isolated local errors still require device/runtime evidence.
5. **CI:** final closure requires the CI run for the latest implementation head to complete green.
