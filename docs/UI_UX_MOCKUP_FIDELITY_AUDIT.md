# Fulus UI/UX Mockup Fidelity Audit

Active workstream: PR #81 (ux-ui-foundation)
Source of truth: approved Fulus mockup + docs/UX_UI_REDESIGN_SPEC.md
Rule: refine the mockup, do not replace its visual language with a generic SaaS dashboard, conventional POS, or unrelated Material layout.

## Completed foundation
- [x] Primary navigation: Home | Sell | Stock | Money | More
- [x] Primary navigation uses large touch targets and persistent mobile navigation
- [x] Global drawer/hamburger navigation removed from the workspace
- [x] Shared FulusScreen header supports contextual back navigation
- [x] Shared FulusListRow baseline raised to 56dp
- [x] Shared FulusActionTile established for primary workspace actions
- [x] Home uses glanceable business summary, action tiles, attention states and recent activity
- [x] Stock uses visual summary metrics, search, filters and actionable inventory
- [x] Money uses the shared action-tile language and glanceable financial summary
- [x] More uses the same tile language instead of a dense settings list
- [x] Important interaction targets and semantics have been hardened
- [x] Loading, empty and error states have been added/refined across audited core screens
- [x] Offline/sync messaging is kept separate from ordinary local data availability
- [x] Reduced-motion behavior is preserved where motion exists
- [x] Secondary actions use shared Fulus controls across Team, Reports, checkout, receipts and auth flows
- [x] Material segmented controls in audited flows replaced with the shared Fulus chip language
- [x] Common confirmation/action dialogs in audited flows use the shared Fulus button hierarchy

## Current UI/UX audit areas

### 1. Home
- [x] Business context and sync status
- [x] Large primary sales value
- [x] Primary actions
- [x] Attention state
- [x] Recent activity
- [x] Loading/error/empty states
- [ ] Final whole-screen comparison against the supplied mockup at phone width
- [ ] Final whole-screen comparison at narrow phone width
- [ ] Final large-text/accessibility visual pass

### 2. Sell
- [x] Search/product discovery
- [x] Product presentation
- [x] Cart summary
- [x] Touch-friendly product interactions
- [x] Core spacing, density and hierarchy pass completed
- [ ] Final whole-screen mockup comparison
- [ ] Empty/search-no-results state visual pass
- [ ] Narrow-width and large-text pass

### 3. Cart / Payment / Sale complete
- [x] Cart quantity interaction
- [x] Customer selection interaction
- [x] Large payment method targets
- [x] Sale-success confirmation and next actions
- [x] Receipt preview
- [ ] Final visual consistency pass across the complete sale journey
- [ ] Error/retry/loading state consistency pass

### 4. Stock
- [x] Glanceable stock metrics
- [x] Search and category filtering
- [x] Low/out-of-stock attention
- [x] Product list touch targets
- [x] Business-configured currency in stock value summary
- [ ] Final mockup-fidelity pass for metric/tile composition
- [ ] Narrow-width chip/filter behavior review
- [ ] Large-text review

### 5. Money
- [x] Balance/summary hierarchy
- [x] Shared action tiles
- [x] Period filtering
- [x] Recent activity
- [x] History/search/filter states
- [ ] Final mockup-fidelity pass for tile sizing and information density
- [ ] Large-text and narrow-width pass

### 6. Customers / Employees / Reports
- [x] Shared list/card/tile primitives
- [x] Customer credit visibility
- [x] Employee overview
- [x] Reports period/export/drill-down structure
- [x] Secondary screen tile/card/row composition pass
- [x] Empty/error/loading consistency review
- [ ] Final whole-screen visual comparison against the mockup

### 7. More / Settings / Secondary screens
- [x] More workspace tiles
- [x] Settings entry and contextual navigation
- [x] Secondary destinations accessible without global drawer
- [ ] Final hierarchy and spacing pass
- [ ] Check that secondary screens do not regress into dense generic settings layouts

### 9. Screen inventory / wiring audit
The route tree and direct Navigator flows were reviewed after the onboarding rework. A screen being reachable is not treated as UI-audited; this section tracks screens that have not yet received a dedicated mockup-fidelity pass.

#### Dedicated UI pass still required
- [ ] Money secondary: Add Income, Add Expense, Customer Profile, Archived Customers, Daily Closing Summary, Transaction Detail, Suppliers, Supplier Profile, Pay Supplier / Ledger Payment, Record Repayment
- [ ] More secondary: Deactivated Employees, Sales Transactions, Diagnostics, Diagnostic Detail
- [ ] Settings secondary: Backup, Fulus Cloud Connection, Printer Pairing, Sync Detail
- [ ] Sell secondary: Refund Search, Refund Confirm, Void Sale, Sale Success
- [ ] Stock secondary: Add/Edit Product, Product Detail, Categories, Bulk Import, Bulk Import Review, Stock Movement History
- [ ] Auth/security: App Lock
- [ ] Remaining onboarding walkthrough: First Run Setup, Essential Settings, Add First Product, Navigation Intro, First Sale Intro, Transaction Verification, Completion

#### Wiring status
- [x] Primary Home / Sell / Stock / Money / More navigation is wired through the persistent shell.
- [x] Routed secondary screens are connected through go_router.
- [x] Plain-Navigator onboarding/recovery flows that intentionally sit outside the shell are reachable through their owning flow.
- [x] Sale Success -> Transaction Verification -> Completion is directly wired as a deliberate walkthrough chain.
- [x] Customer repayment and supplier payment share the LedgerPaymentScreen presentation workspace through their owning routes.
- [ ] Dedicated UI pass for every screen above is still open even where routing/wiring already works.
- [ ] Verify every secondary route at narrow width, large text, dark theme, loading/empty/error states after its visual pass.

### 8. Global polish
- [ ] Verify 48dp minimum across all interactive controls
- [ ] Verify primary actions are comfortably larger than the minimum where appropriate
- [ ] Verify icon-only controls have semantics/tooltips
- [ ] Verify no important information relies on color alone
- [ ] Verify typography at large system text
- [ ] Verify narrow phone layout
- [ ] Verify wide/tablet layout
- [ ] Verify dark theme
- [ ] Verify loading/empty/error/offline states
- [ ] Verify press feedback and reduced motion
- [ ] Verify no duplicate or contradictory sync status
- [ ] Whole-screen visual review of every primary tab

## Current workstream boundary

This workstream is intentionally UI/UX-only. Until the UI/UX completion gate is closed, defer unrelated production-readiness work unless it directly blocks UI validation.

### Deferred outside this workstream
- Full cloud-sync/backend audit
- Supabase schema, RLS and server-side performance work
- Sync conflict-resolution and background-sync architecture
- Android WorkManager/background reliability work
- Auth/backend architecture changes
- Server-side location isolation work
- Deployment/infrastructure work unrelated to UI validation
- Hardware-specific validation such as printing/camera/background device behavior

CI remains a validation gate for UI changes, but unrelated CI/Vercel failures are not UI blockers.

## UI/UX completion gate
A screen is complete only when its whole composition matches the approved visual direction, not merely when its individual widgets are technically correct.

Do not move to unrelated production/cloud-sync audit work while this ledger has open UI/UX fidelity items unless explicitly instructed.