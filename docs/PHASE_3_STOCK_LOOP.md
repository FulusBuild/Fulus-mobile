# Phase 3 — Stock Loop

Phase 3 turns Stock from a catalog view into an action-first inventory workspace.

## Core loop

**Stock → see risk → choose product → change quantity → verify → return to Stock**

## Product principles

- Stock answers the shopkeeper's next question before exposing configuration.
- Low/out-of-stock products are actionable shortcuts, not decorative statistics.
- Adding a product stays short: Name + Price first; details remain secondary.
- Stock in/out/adjustment share one record-stock entry point.
- Every mutation is local-first and recoverable.
- No destructive action without clear confirmation/approval where required.
- Avoid technical inventory terminology unless it helps the task.
- Preserve the existing Fulus blue/white/black visual language.

## Phase 3 acceptance criteria

1. A new shopkeeper can add a product without understanding SKU, inventory accounting, or backend concepts.
2. A shopkeeper can find low/out-of-stock items in one tap from Stock.
3. A shopkeeper can record stock in/out/adjustment without leaving the Stock feature.
4. Product detail gives price, stock, and recent activity at a glance.
5. Search covers product name, SKU, and barcode.
6. Offline stock mutations remain safely persisted/queued.
7. Failed reads show recovery UI instead of endless loading.
8. Stock screens remain usable with long product names, large text, and small phones.
9. Product creation/editing never silently loses optional fields.
10. Stock value uses cost basis rather than potential retail revenue.

## Explicit non-goals

Transfer remains blocked until a real backend write endpoint exists. Price-change history and actor attribution remain unrepresented until the underlying data model/API exposes them.
