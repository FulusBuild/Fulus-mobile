# Fulus Instant UI Contract

**Status:** Active engineering contract  
**Scope:** Authenticated Fulus workspace navigation and local-first UI rendering  
**Applies to:** Home, Sell, Stock, Money, More, and their secondary/detail routes

## Core invariant

An authenticated Fulus workspace must become visually usable immediately after navigation.

**Required flow**

`tap -> destination structure paints -> local state hydrates -> UI updates in place -> background sync updates local state`

**Forbidden flow**

`tap -> network/sync prerequisite -> async initialization gate -> blank/spinner -> destination`

Fulus is local-first. Supabase/cloud sync is never a prerequisite for rendering an already-authenticated local workspace.

## 1. First useful frame

Every workspace route must have a deterministic first useful frame.

The first useful frame means the user can see the destination's real structure and understand where they are, even if some local data has not finished loading.

- Do not wait for cloud sync, network connectivity, or remote acknowledgement.
- Do not wait for unrelated secondary queries.
- Do not replace the whole destination with a generic loading indicator.
- A shaped skeleton is acceptable only when the missing local value genuinely cannot be shown yet.
- Prefer an existing cached/local value over a fresh asynchronous calculation.

## 2. Navigation is immediate

Primary navigation must not visually animate the old and new workspaces together.

- Selected navigation state changes immediately.
- Ordinary primary route transitions must not expose the previous route underneath the destination.
- `StatefulShellRoute` branch preservation should be used so switching branches does not unnecessarily reconstruct the workspace.
- Transition polish must never become a perceived loading delay.

## 3. Local hydration is progressive

Local asynchronous work is allowed. It must not unnecessarily gate the entire screen.

Prefer:

`screen shell -> section A local value -> section B local value -> section C local value`

over:

`screen shell -> await A+B+C -> render everything`

Each independent section should hydrate and update in place.

A slow local query must not hold unrelated content hostage.

## 4. Primary workspace rules

### Home

Home may render its dashboard structure before activity, cash, notices, or other secondary local reads finish.

- Hero state should use the fastest safe local source available.
- Activity, cash, notices, and reports hydrate independently.
- A slow balance aggregation must not block the rest of Home.

### Sell

Sell must show the selling workspace without waiting for remote state.

- Active location resolution must not unnecessarily block the first useful Sell frame.
- Draft-cart creation must not be required before the Sell structure is visible.
- Existing durable cart state should hydrate into the visible workspace.
- Cart/product streams should update the workspace in place.
- A local initialization failure should affect the relevant content, not expose a generic blank screen.

### Stock

Stock must show the stock workspace without waiting for remote state.

- Active location resolution must not unnecessarily block the first useful Stock frame.
- Existing local product/category state should hydrate progressively.
- Product loading must not hide the entire workspace when a useful shell can already be shown.

### Money

Money must show the money workspace without waiting for expensive full-history aggregation.

- Existing local summary/projection values should be preferred.
- Expensive historical aggregation must not unnecessarily block the first useful frame.
- Balance, transactions, summaries, and secondary metrics should hydrate independently where safe.
- Financial correctness takes priority over speculative caching or approximation.

### More

More should render its navigation structure immediately. Individual destination data can hydrate when that destination opens.

## 5. Secondary/detail routes

A detail screen may require a local read before its content is meaningful, but it still needs an immediate structural frame.

Acceptable:

`header/body structure -> local read -> content`

Avoid:

`route -> full-screen spinner -> local read -> entire screen appears`

If no local value exists, use a deliberate empty state or shaped skeleton rather than a generic loading surface.

## 6. Loading states

Loading indicators remain valid for an explicit action the user is waiting on, including:

- saving a mutation;
- importing/exporting;
- restoring a backup;
- scanning hardware;
- printer/hardware operations;
- unavoidable file operations;
- explicit submission flows.

They are not valid as a default substitute for an authenticated workspace that is merely hydrating local data.

## 7. Error isolation

An error in one local section must not unnecessarily turn the entire workspace into an error screen.

Prefer:

`working workspace + section-level error/retry`

over:

`entire workspace replaced by error`

unless the missing value is genuinely required for the route to function safely.

## 8. Sync separation

Rendering dependencies must not include cloud sync completion.

The intended dependency graph is:

`UI <- Local DB / local state`

and independently:

`Local DB <-> Sync <-> Cloud`

A sync status indicator may describe sync state, but sync state must not determine whether the authenticated workspace can render.

## 9. Location separation

Location identity is business-critical and must remain correct.

Instant UI does **not** mean skipping location authorization or silently guessing a location.

Instead:

- use a safely known active location immediately when available;
- resolve/validate location in the background where possible;
- never allow an A-scoped operation to become B-scoped;
- when no safe location exists, show an explicit location-required state rather than rendering data for the wrong location.

Location correctness is higher priority than shaving an unsafe frame.

## 10. State reuse

When a user switches:

`Home -> Sell -> Home`

the existing Home branch/state should be reused where the navigation architecture supports it.

Do not recreate controllers, cubits, repositories, or expensive local queries solely because the branch became visible again.

Any intentional recreation must have a documented reason.

## 11. Query discipline

Before adding a FutureBuilder, AsyncValue loading gate, or initialization await to a primary workspace, answer:

1. What data is required for safe rendering?
2. Is it local, device-only, or remote?
3. Is an existing local value available?
4. Can the query run after the first useful frame?
5. Can the result be exposed as a reactive local stream?
6. Is the same query being repeated by multiple widgets?
7. Is the operation an expensive aggregation that belongs in a maintained local projection?

Do not optimize by weakening business or financial correctness.

## 12. Measurement and acceptance

A change is not considered complete merely because the code has fewer loading widgets.

Verify:

- no old-frame flash during navigation;
- no avoidable white/blank period;
- destination structure appears before slow local work completes;
- primary workspace remains usable while secondary data hydrates;
- branch switching preserves state where intended;
- offline operation still renders local workspace;
- cloud sync can be delayed without blocking rendering;
- CI/analyzer/tests remain green.

Where possible, test in slow-motion and with cold/warm local state because both route rendering and local hydration regressions can be visually subtle.

## 13. Non-goals

This contract does not authorize:

- bypassing authorization;
- using stale data when correctness requires validation;
- inventing approximate financial values;
- removing durable persistence;
- weakening sync guarantees;
- hiding genuine errors;
- replacing correct location isolation with convenience;
- broad architecture rewrites without evidence.

## Current implementation gaps

The Instant UI audit currently tracks these remaining areas:

- **IUI-02:** Sell active-location resolution remains on the first useful-frame path.
- **IUI-03:** Sell draft-cart initialization remains an async gate before full cart state.
- **IUI-04:** Home hero still has a first-useful-frame dependency on its hero future.
- **IUI-05:** Money still performs expensive local aggregation on entry.
- **IUI-06:** Stock active-location resolution remains a first-frame gate.
- **IUI-07:** Secondary/detail screens have inconsistent loading replacement.
- **IUI-08:** Loading architecture is not yet standardized.
- **IUI-09:** StatefulShellRoute branch state reuse still needs explicit verification.

These are engineering work items, not permission to rewrite the architecture speculatively.

## Completion definition

The Instant UI work is complete only when the primary workspace routes satisfy this contract, the highest-impact secondary routes have been classified and corrected, and the resulting implementation has been tested with CI green.

The target remains:

**tap -> screen immediately -> local data hydrates -> UI updates -> cloud sync independently**


## Current implementation note
Sell now separates safe local workspace hydration from durable cart readiness: catalog/settings may render during CartHydrating, while cart mutations remain unavailable until a verified durable draft reaches CartLoaded. Location resolution remains authoritative and is not bypassed.
