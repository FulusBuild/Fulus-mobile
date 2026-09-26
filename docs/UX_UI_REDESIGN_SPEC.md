# Fulus UX/UI Redesign Specification

**Status:** Active  
**Reference:** Fulus visual mockup provided for the UX/UI redesign  
**Scope:** Mobile application UX/UI, interaction design, visual system, accessibility, and consumer-grade polish  
**Repository:** `FulusBuild/Fulus-mobile`

---

## 1. Purpose

This document defines the UX/UI direction for Fulus and provides the working specification for the redesign.

The goal is not to turn Fulus into a conventional POS interface or a generic SaaS dashboard.

Fulus should feel like a **business operating system for everyday business owners**: fast to understand, easy to operate, highly visual, and useful at a glance.

The uploaded Fulus mockup is the **primary and controlling visual reference** for this work. Screens must follow its visual language closely and become better through refinement, not drift into a different design language.

The redesign must preserve the application's existing business logic, offline-first behavior, synchronization architecture, permissions, financial correctness, and production contracts unless a genuine product requirement requires a change.

---

## 2. Core Design Direction

Fulus uses a tile-based interaction language inspired by:

- the clarity and familiarity of Nigerian fintech/terminal interfaces;
- the glanceable information architecture of Windows Phone/Lumia Live Tiles;
- modern mobile interaction patterns;
- Fulus's own brand identity.

This is **inspiration at the interaction level, not a reproduction of another company's branding or UI**. The Fulus mockup itself is the visual authority for implementation.

### Core principle

> If the user needs to squint, search, or think about what to tap, the interface has failed.

### Secondary principle

> Important business information should be understandable at a glance.

---

## 3. Product UX Principles

### 3.1 Glanceability

The Home screen should answer quickly:

1. How is the business doing today?
2. What needs attention?
3. What can I do next?

Numbers, status, and actionable information should have visual priority over explanatory text.

### 3.2 Action first

Primary actions should be directly tappable.

Examples:

- Sell
- Add stock
- Add expense
- View customers
- Collect credit
- View reports

The user should not have to interpret a metric before reaching the relevant task.

### 3.3 Large touch targets

Important controls should be comfortable to use on inexpensive Android phones and in real shop environments.

Target:

- minimum interactive target: **48dp**
- primary actions should generally be larger where practical;
- avoid controls that require precise tapping.

### 3.4 Visual hierarchy

Every screen should clearly communicate:

1. what matters most;
2. what can be acted on;
3. supporting information;
4. secondary/navigation controls.

### 3.5 Low cognitive load

Avoid:

- unnecessary menus;
- dense paragraphs;
- excessive metrics;
- tiny controls;
- duplicate status information;
- decorative elements that compete with actions.

### 3.6 Business-state awareness

Fulus should surface information according to the current state of the business.

Examples:

- low stock becomes prominent when action is needed;
- unpaid customer credit is surfaced when relevant;
- an unsynced state is visible without creating unnecessary alarm;
- empty businesses do not receive meaningless charts or metrics.

---

## 4. Fulus Visual Language

### 4.1 Tile-based layout

Important functionality should be represented through clear visual tiles or large cards.

Tiles may vary in size according to importance.

Examples:

- large business-performance tile;
- large Sell/Stock action tiles;
- medium Money/Customers tiles;
- prominent Low Stock attention tile.

Uniform grids should not be used everywhere merely for visual consistency.

### 4.2 Large numbers

Financial and operational values should use large, highly legible typography.

Examples:

- `₦245,800`
- `38 sales`
- `7 low-stock items`
- `₦82,400 owed`

Currency formatting must continue to use the application's existing domain formatting and precision rules.

### 4.3 Icons

Icons should:

- communicate the concept quickly;
- have consistent visual weight;
- remain recognizable at small sizes;
- use semantic labels/tooltips for icon-only actions;
- not be the sole carrier of meaning.

### 4.4 Color

Color should communicate hierarchy and state rather than become decoration.

The established Fulus brand blue remains the primary interaction accent.

Status colors should have accompanying text/icon semantics and must not communicate meaning through color alone.

### 4.5 Typography

Typography should prioritize:

- large primary values;
- short, strong labels;
- readable secondary information;
- safe behavior with large system text settings.

Text must not be clipped simply to preserve a visual composition.

### 4.6 Shape and elevation

Use a coherent system for:

- corner radii;
- borders;
- elevation/shadows;
- spacing;
- tile padding.

These values should come from shared design tokens rather than one-off screen constants.

---

## 5. Navigation

The target navigation model is:

**Home | Sell | Stock | Money | More**

Navigation should remain predictable across the application.

The current app shell/navigation implementation should be evaluated before replacement. Existing routes and business behavior must remain intact unless the redesign explicitly requires a routing change.

No hamburger-menu maze should be introduced for primary workflows.

Secondary tools can remain under More where appropriate.

---

## 6. Home Screen

Home is the first redesign target because it establishes the Fulus visual language.

### Target structure

1. Header/business context
2. Business-state hero
3. High-value information tiles
4. Attention/alerts
5. Quick actions
6. Recent activity
7. Persistent navigation

The exact ordering may adapt to the current business state.

### Existing product contract must remain

The current Home implementation already defines important business behavior:

- pre-opening state;
- open-shop state;
- closed state;
- employee shift state;
- prioritized attention notices;
- quick actions;
- recent money activity;
- offline-readable data;
- refresh/data-change behavior;
- employee permission boundaries.

The visual redesign must preserve these contracts.

### Home should not become

- a wall of metrics;
- a chart dashboard;
- an alert wall;
- a network-dependent loading screen;
- a static mockup disconnected from real business state.

---

## 7. Screen-by-Screen UX Direction

### 7.1 Sell

Goal: make selling extremely fast.

Design direction:

- prominent search;
- obvious product/category access;
- large product tiles;
- clear prices;
- clear stock availability where useful;
- persistent cart summary;
- obvious charge/checkout action.

### 7.2 Cart

Goal: make the current sale immediately understandable.

Prioritize:

- product;
- quantity;
- unit price;
- line total;
- overall total;
- remove/edit controls;
- checkout action.

Avoid unnecessary form complexity.

### 7.3 Payment

Goal: make payment completion obvious and safe.

Payment methods should be large, visually distinct, and easy to select.

Split payment must remain understandable without exposing implementation complexity.

### 7.4 Sale Complete

Goal: provide immediate confirmation and useful next actions.

The success state should clearly communicate:

- sale completed;
- amount;
- payment result;
- relevant receipt/share/next-sale actions.

### 7.5 Stock

Goal: make inventory status visual and actionable.

Surface:

- product count;
- categories;
- low-stock items;
- stock movement;
- add stock;
- product search.

Low-stock information should become visually prominent when action is required.

### 7.6 Money

Goal: provide a clear financial operating view.

Surface:

- money in;
- money out;
- available balance;
- customer credit;
- supplier payments;
- recent transactions.

The screen should remain operational rather than becoming an accounting spreadsheet.

### 7.7 Customers

Goal: make customer relationships and credit easy to understand.

Surface:

- customer count;
- search;
- outstanding credit;
- recent customer activity;
- clear customer-level balances.

### 7.8 Reports

Goal: present useful business intelligence without unnecessary complexity.

Reports should emphasize:

- sales;
- profit;
- expenses;
- stock;
- customer credit.

Charts are useful when they improve understanding, not simply because chart data exists.

### 7.9 Employees

Goal: make staff management understandable at a glance.

Surface:

- employee identity;
- role;
- active/inactive state;
- permissions/access where appropriate.

Sensitive business data must continue to obey existing authorization rules.

### 7.10 More

Goal: provide secondary tools without hiding primary workflows.

Likely areas:

- Business settings
- Printers
- Backup & Sync
- Employees & Permissions
- Help & Support
- About Fulus

---

## 8. Component System

The redesign should strengthen shared components rather than create isolated screen-specific versions.

Candidate shared primitives include:

- Fulus tile
- Fulus metric tile
- Fulus action tile
- Fulus attention tile
- Fulus section header
- Fulus list row
- Fulus empty state
- Fulus error state
- Fulus loading/skeleton state
- Fulus buttons
- Fulus icon buttons
- Fulus navigation items
- Fulus search field
- Fulus status indicator

Shared primitives must consume design tokens.

---

## 9. Responsive Behavior

Fulus must work across:

- small Android phones;
- normal phones;
- large phones;
- tablets/large windows where supported.

Rules:

- avoid unnecessary horizontal gutters on narrow screens;
- constrain content on large windows;
- do not stretch information indefinitely;
- allow large text to reflow;
- preserve discoverability of important actions;
- avoid silent clipping and unsafe overflow.

---

## 10. Accessibility

Every production screen must consider:

- minimum 48dp interactive targets;
- semantic labels;
- icon-only action labels/tooltips;
- large system text;
- sufficient contrast;
- keyboard/focus traversal where supported;
- status communicated through text/semantics, not color alone;
- reduced-motion preferences.

Accessibility is part of the visual design system, not a final afterthought.

---

## 11. State Design

Every relevant screen must have intentional states for:

- populated;
- empty;
- loading;
- error;
- retry;
- offline;
- disabled/unavailable action;
- long content;
- large text;
- dark theme;
- narrow width.

Fast local reads should not cause unnecessary loading flashes.

Offline state must not be represented as failure when the feature is intentionally usable offline.

---

## 12. Motion and Interaction

Motion should be:

- restrained;
- consistent;
- purposeful;
- short enough for frequent business operations.

Use the existing interaction foundation and motion ceilings.

Reduced-motion settings must remove non-essential animation.

Press states and haptics should reinforce primary actions without becoming distracting.

---

## 13. Offline and Sync UX

The UI redesign must not weaken Fulus's offline-first model.

Users should be able to distinguish:

- local business data available now;
- work pending synchronization;
- successful synchronization;
- actual errors.

Avoid duplicate or contradictory sync messaging.

Do not display a network-dependent loading gate for information that is already available locally.

---

## 14. Data and Architecture Boundary

UX/UI work must not casually modify:

- financial calculations;
- accounting rules;
- synchronization semantics;
- business-switch fencing;
- authorization;
- server-authoritative financial operations;
- database constraints;
- migration history;
- offline persistence.

If a UI requirement exposes a genuine domain/data limitation, document it first and make the smallest appropriate architectural change.

---

## 15. Reference Mockup Mapping

The reference mockup establishes the target visual language:

| Reference area | Fulus implementation |
|---|---|
| Home | Business command center |
| Sell | Fast product selection and sale |
| Stock | Visual inventory management |
| Money | Financial operating view |
| Customers | Customer and credit management |
| New Sale | Payment workflow |
| Stock Alert | Prioritized low-stock state |
| Employees | Staff management |
| Reports | Business reporting |
| More | Settings and secondary tools |

The reference is a **strict visual target**. Do not replace its tile composition, hierarchy, spacing character, visual density, navigation language, or overall screen feel with a generic SaaS, Material dashboard, or conventional POS design.

Real Fulus data, permissions, states, and workflows must fit inside the mockup's visual system. Preserve the mockup's visual direction and solve product requirements within that direction.

---

## 16. Redesign Process

### Phase 1 — Baseline audit

Audit:

- design tokens;
- shared widgets;
- AppShell/navigation;
- Home;
- current screen patterns;
- accessibility primitives;
- responsive behavior;
- existing dark mode;
- loading/error/empty states.

Deliverable: documented gap list.

### Phase 2 — Design system

Standardize:

- colors;
- typography;
- spacing;
- tile dimensions;
- radii;
- elevation;
- icon sizing;
- touch targets;
- state treatments.

Deliverable: reusable Fulus UI primitives/tokens.

### Phase 3 — Home

Redesign Home against the reference while preserving its existing domain contract.

Deliverable: production Fulus Home.

### Phase 4 — Core workflows

Apply the system to:

1. Sell
2. Cart
3. Payment
4. Sale complete
5. Stock
6. Money
7. Customers
8. Reports
9. Employees
10. More

### Phase 5 — Consumer-grade polish

Validate:

- motion;
- haptics;
- skeletons;
- accessibility;
- dark mode;
- responsive layouts;
- edge states;
- interaction consistency.

---

## 17. Quality Gate

A redesigned screen is not complete until:

- [ ] It follows the Fulus tile/visual language.
- [ ] Primary information is understandable at a glance.
- [ ] Primary actions are obvious.
- [ ] Important targets meet the 48dp baseline.
- [ ] Large text does not break the layout.
- [ ] Empty/loading/error/offline states are intentional.
- [ ] Dark mode is coherent.
- [ ] Narrow and large layouts are tested.
- [ ] Existing business behavior remains correct.
- [ ] Existing permission boundaries remain correct.
- [ ] Offline behavior remains correct.
- [ ] No duplicate or misleading sync messaging is introduced.
- [ ] Flutter analysis passes.
- [ ] Relevant tests pass.
- [ ] CI is green.

---

## 18. Working Rule

Do not redesign screens independently.

Every new screen should strengthen the same Fulus design language.

When a new UI pattern is needed:

1. determine whether an existing shared primitive can handle it;
2. extend the shared system when the pattern is reusable;
3. only create a screen-specific component when there is a clear reason.

The objective is a Fulus application that feels like **one coherent product**, not a collection of individually redesigned screens.

---

## 19. Current Starting Point

The first implementation task after this specification is:

> **Audit the existing design tokens, shared widgets, AppShell/navigation, and Home implementation against this specification and the Fulus reference mockup before making visual code changes.**

The audit should identify:

- what already matches;
- what partially matches;
- what conflicts with the target;
- what should be reused;
- what should be refactored;
- what must be newly introduced.

Only after that baseline should implementation begin.


---

# 20. Deep Research Findings — Locked Direction

**Research completed:** 2026-09-26  
**Decision:** Research informs implementation, but the supplied Fulus mockup remains the visual source of truth.

## 20.1 Research objective

The research asks how Fulus can become the best possible version of the visual language already established by the mockup without drifting away from it.

The answer is to strengthen the mockup with proven principles: glanceable information, large readable hierarchy, tile-based information architecture, direct actions, strong typography, familiar mobile interaction, generous touch targets, meaningful business states, honest offline/sync communication, and reusable components.

## 20.2 Windows Phone / Lumia research

Microsoft's historical Windows Phone guidance emphasized clean, light, open and fast interfaces, understanding an application at a glance, typography as functional hierarchy, and motion as feedback. Microsoft's Live Tile guidance describes surfacing useful information without requiring the user to open the app. [1][2]

Microsoft's Windows Phone material also described the experience as “glance and go,” with the Start screen surfacing what is happening, what is next, and what was missed. [3]

### Fulus interpretation

The important lesson is not “make everything a tile.” The lesson is: put the most useful information and actions on the surface, in a form that can be understood immediately.

Therefore:

- Home must feel alive with useful business information.
- Tile size must reflect information importance.
- A tile must earn its space by communicating useful information or providing a useful action.
- Large numbers should be visually dominant when they represent important business state.
- Dynamic business state should update the surface without requiring deep navigation.
- Animation must remain purposeful and restrained.

Do not replace the mockup's tile language with a generic card-dashboard layout simply because cards are easier to implement.

## 20.3 Nigerian fintech / merchant research

Current Nigerian merchant products reinforce a complementary lesson: operational familiarity.

Moniepoint emphasizes easy operation, payment collection, transfers, card payments, instant settlement, and business management tools. [4][5]

OPay's business platform emphasizes safer, easier and faster payment collection across channels and everyday business operations. [6]

PalmPay's current business products combine payments, POS, transaction management, business accounts and business-management tools. [7][8]

### Fulus interpretation

The useful interaction lesson is operational clarity:

- important actions should look tappable;
- money movement should be immediately understandable;
- confirmation states should be unmistakable;
- high-frequency workflows should require few decisions;
- operators should not need to understand technical concepts to complete normal work.

Fulus must borrow this operational clarity, not their branding, colors, logos, copy style, or proprietary UI.

## 20.4 Mobile accessibility research

Android guidance recommends interactive touch targets of at least 48dp, with adequate spacing. [9]

W3C guidance similarly emphasizes sufficiently large touch targets because touch input is less precise than a mouse. [10]

### Fulus interpretation

The existing 48dp baseline remains correct, but 48dp is a floor rather than the target for every important action.

For the mockup:

- primary tiles should generally be substantially larger than the minimum;
- primary actions should have generous internal padding;
- icon-only controls must still have a large hit area;
- adjacent actions must not feel cramped;
- small visual icons can exist inside large interactive regions.

## 20.5 Offline-first research

Android's official offline-first guidance states that an offline-first application should remain usable without reliable connectivity and should present local data without waiting for a network request. It also identifies synchronization and conflict reconciliation as separate concerns. [11]

Recent offline-first UX guidance similarly emphasizes that offline is a normal operating condition and that the UI should distinguish locally saved work, pending synchronization, and actual errors. [12]

### Fulus interpretation

The UI must never make connectivity the center of the user's normal business workflow.

Good states: Saved on this phone, Syncing, Synced, Needs attention.

Avoid technical synchronization terminology, indefinite spinners, contradictory connected and last-backup states, or presenting a successful local action as failed merely because cloud synchronization is pending.

## 20.6 Tile and card research

Material guidance notes that cards can provide context and entry points, but warns against using separate cards where they make scanning harder. It also emphasizes hierarchy within a card and avoiding unnecessary information/actions. [13]

### Fulus interpretation

This supports the mockup's differentiated tile sizes.

A tile should communicate what it is, why it matters, and what can be done with it.

Avoid turning every small piece of information into its own bordered card. The visual rhythm should come from size, spacing, typography, grouping, iconography, color/state, and intentional alignment.

---

# 21. Mockup Fidelity Rules — Non-Negotiable

The user has explicitly established the mockup as the visual target.

## 21.1 Do not drift

Do not redesign Fulus into a generic SaaS dashboard, spreadsheet-like business app, conventional POS, standard Material dashboard, card-heavy banking clone, or navigation-heavy enterprise application.

## 21.2 “Better” means refinement, not divergence

Allowed: better spacing, typography, responsive behavior, hierarchy, accessibility, state handling, animation, loading/error states, interaction feedback, real-data integration, and component architecture.

Not allowed: replacing the core composition, removing the tile language, shrinking primary content into dense lists, turning the screen into a conventional dashboard, replacing glanceable information with deep navigation, or introducing a competing visual language.

## 21.3 Screen-level fidelity

Every redesigned screen must be reviewed against the mockup at whole-screen level, not merely component-by-component.

Review overall silhouette, dominant visual blocks, tile sizes, spacing rhythm, navigation position, information density, typography hierarchy, icon placement, primary action prominence, and color/state treatment.

A screen can contain individually good components and still fail the mockup if its overall composition has drifted.

## 21.4 Shared system must serve the mockup

The shared component system should be built from the mockup outward.

Correct sequence:

Mockup → visual rules → tokens → reusable primitives → screens

Not:

Existing widgets → rearrange widgets → approximate mockup

---

# 22. Fulus Visual System Derived From Research

## 22.1 Primary visual hierarchy

Normally: Business state → important number → action → supporting context.

The primary number should be perceived before the explanatory sentence.

## 22.2 Tile hierarchy

Use a deliberate size vocabulary:

- Hero tile: business-critical state or major metric.
- Large action tile: frequent primary workflow.
- Medium information tile: important supporting business information.
- Small utility tile: secondary information/action.

Do not make all tiles equal.

## 22.3 Tile content rule

A tile should communicate its purpose in one glance. If a tile requires a paragraph to explain itself, redesign the tile.

## 22.4 Action rule

The user should be able to identify the primary action before reading every label on the screen.

## 22.5 Information density rule

Fulus should feel information-rich without feeling information-heavy: fewer, stronger elements; larger primary values; short labels; meaningful grouping; whitespace where it improves scanning; and no decorative metrics.

---

# 23. Current Fulus Baseline Findings

The repository audit found a useful existing foundation.

### Already aligned

The codebase already has centralized design tokens, Fulus-specific colors, typography, spacing, radius, elevation and motion tokens, icon sizing, a 48dp touch-target baseline, shared buttons, cards, list rows, search, empty/error states, quick actions, consumer interaction polish, offline-aware architecture, and responsive layout helpers.

The existing Home screen already has important business-state behavior: not-yet-opened, open-shop, closed, employee-shift, business-wide permissions, attention notices, quick actions, recent activity, local/offline-safe reads, and refresh/data-change handling.

Therefore, the redesign should build on the existing product foundation rather than replace it.

### Important current gap

The current FulusAppShell uses a navigation drawer as its primary navigation mechanism.

The target UX specification calls for Home | Sell | Stock | Money | More with persistent bottom navigation on the primary mobile experience.

This is now an explicit design-system work item. The existing drawer can remain useful for secondary or expanded navigation where appropriate, especially on larger layouts, but it must not cause the primary mobile experience to diverge from the mockup.

---

# 24. Research-to-Implementation Decisions

| Research finding | Fulus decision |
|---|---|
| Windows Phone prioritized glanceability | Home surfaces important business state directly |
| Live Tiles exposed information without opening apps | Fulus tiles communicate useful information before navigation |
| Windows Phone emphasized typography | Large business numbers remain dominant |
| Nigerian merchant apps prioritize operational simplicity | High-frequency Fulus actions remain obvious and direct |
| Merchant products emphasize payment clarity | Sell/payment confirmation must be unmistakable |
| Android recommends 48dp touch targets | 48dp remains the minimum baseline |
| Larger targets improve touch reliability | Important mockup tiles/actions should exceed the minimum |
| Offline-first requires local usability | UI must work from local state without network gating |
| Sync is separate from local persistence | Saved, syncing, synced, and error states must be distinguishable |
| Cards can harm scanning when overused | Do not turn every piece of information into a separate card |
| Responsive layouts must adapt | Tile composition must reflow without losing hierarchy |

---

# 25. Screen-by-Screen Fidelity Strategy

## Home

Primary visual goal: reproduce and strengthen the mockup's business command center.

Must communicate at a glance: business identity/context, today's important state, major business number(s), immediate actions, attention items, recent activity, and sync state without technical noise.

## Sell

Primary visual goal: large, fast, visual selling. It must feel like the mockup's action language, not a conventional POS grid. Products, categories, search, cart and checkout must remain visually obvious.

## Stock

Primary visual goal: visual inventory control. Low stock must be immediately visible when relevant.

## Money

Primary visual goal: money at a glance. Cash movement, balances, credit and recent transactions should use the same tile hierarchy.

## Customers

Primary visual goal: people and credit, not a CRM spreadsheet. Customer identity and amount owed should be immediately understandable.

## Reports

Primary visual goal: business understanding without dashboard overload. Use visual summaries first, detail second.

## Employees

Primary visual goal: clear people/status management. Roles and permissions remain subordinate to the visual hierarchy but must remain understandable.

## More

Primary visual goal: secondary tools without cluttering the primary business experience.

---

# 26. Validation Method

Every screen will go through four comparisons.

### A. Mockup comparison

Does the screen visibly belong to the same product shown in the mockup?

### B. Glance test

Can a user understand the most important information in approximately one short glance?

### C. Thumb test

Can the primary actions be comfortably used on a normal Android phone without precise tapping?

### D. State test

Does the screen remain truthful and understandable in empty, populated, loading, offline, syncing, synced, error, permission-limited, narrow, large-text, and dark-mode states?

A screen fails the redesign gate if any of these tests exposes a fundamental mismatch.

---

# 27. Research Sources

1. Microsoft Learn — Windows Phone design principles: https://learn.microsoft.com/en-us/archive/msdn-magazine/2012/january/windows-phone-design-your-windows-phone-apps-to-sell
2. Microsoft Learn — Live Tiles and glanceable UX: https://learn.microsoft.com/en-us/archive/msdn-magazine/2014/december/modern-apps-build-a-better-ux-with-live-tiles
3. Microsoft Devices Blog — The future is glanceable: https://blogs.windows.com/devices/2011/03/02/the-future-is-glanceable/
4. Moniepoint — POS terminal: https://moniepoint.com/ng/business/point-of-sale-terminal
5. Moniepoint — Business banking/business management: https://moniepoint.com/ng/business
6. OPay Business — Business and payment solutions: https://opaybusiness.opayweb.com/
7. PalmPay — Business/POS: https://www.palmpay.com/business/pos/
8. PalmPay — Business account and management tools: https://www.palmpay.com/business/account/
9. Android Accessibility — Touch target size: https://support.google.com/accessibility/android/answer/7101858
10. W3C WAI — Target Size: https://www.w3.org/WAI/WCAG21/Understanding/target-size
11. Android Developers — Build an offline-first app: https://developer.android.com/topic/architecture/data-layer/offline-first
12. Offline-first UX research reference used during this audit: https://www.synapse.ge/blog/offline-first-mobile-apps/
13. Material Design — Cards and information hierarchy: https://m1.material.io/components/cards.html

---

# 28. Final Design Mandate

> **The mockup is the visual source of truth.**

Research exists to make the mockup better, more usable, more accessible, more responsive, and more production-ready.

Research does not give permission to redesign Fulus into something else.

The implementation goal is:

> **Make the actual Fulus app look and feel like the mockup, then make that design work exceptionally well with real Fulus data, real business states, real offline behavior, and real production constraints.**

The final product should feel immediately recognizable as the same design shown in the mockup on every major screen.
