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

The uploaded Fulus mockup is the primary visual reference for this work.

The redesign must preserve the application's existing business logic, offline-first behavior, synchronization architecture, permissions, financial correctness, and production contracts unless a genuine product requirement requires a change.

---

## 2. Core Design Direction

Fulus uses a tile-based interaction language inspired by:

- the clarity and familiarity of Nigerian fintech/terminal interfaces;
- the glanceable information architecture of Windows Phone/Lumia Live Tiles;
- modern mobile interaction patterns;
- Fulus's own brand identity.

This is **inspiration at the interaction level, not a reproduction of another company's branding or UI**.

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

The reference is a **design system target**, not a requirement to copy every mockup element literally.

Real Fulus data, permissions, states, and workflows take precedence.

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
