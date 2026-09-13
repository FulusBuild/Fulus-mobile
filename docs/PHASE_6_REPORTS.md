# Phase 6 — Reports

Phase 6 turns reporting into a decision-ready, trustworthy readout of the business without introducing a second source of truth.

## Product contract

- One Reports destination with five categories: Sales, Inventory, Customers, Finance, Team.
- One shared period selector for period-scoped reports: Today, This week, This month, Custom.
- Inventory remains a live snapshot; its rolling operational window is explicitly 30 days.
- Reports are retrospective only. Insights describe recorded facts and never forecast, recommend, or rank employees against one another.
- Empty states explain what the owner needs to record before a report can become useful.
- Failed report loads have a recoverable error state; a failure never leaves a spinner on screen indefinitely.
- Every real underlying list has a drill-down path where one exists: sales transactions, products, customers, employees, and money history.
- Exports are generated from the same loaded report data and use the configured business name/currency.
- Custom-range cancellation does not silently change the selected period.
- Sales aggregates exclude voided transactions and net genuine refunds; the sales transaction drill-down still shows the transaction and its refund/void status.
- Finance net profit is revenue minus cost of goods sold minus expenses. Cash flow is presented separately because cash movement and accounting profit answer different questions.
- Team reporting is business-wide only where the caller grants the existing dashboard/report permission boundary; insights never identify an individual as a top performer.

## Offline-first contract

Reports read the local repositories. They never require a network round trip to render recorded business data. Export is also local-first and is allowed to fail independently of the underlying report data without changing that data.

## Accessibility and interaction

- Large, explicit labels are preferred over unexplained abbreviations.
- Tappable report figures expose a visible navigation affordance.
- Theme-aware surfaces and text are used instead of light-only report colors.
- Loading, empty, and error states are distinct so the owner can tell whether there is no data, data is still loading, or something actually failed.

## Completion checklist

- [x] Shared period selection, including custom range.
- [x] Sales, Inventory, Customers, Finance, and Team reports.
- [x] Rule-based retrospective insights.
- [x] Correct void/refund handling in sales aggregates.
- [x] COGS-aware finance profit calculation.
- [x] Inventory movement counts from real stock movements.
- [x] Customer and employee drill-down identifiers.
- [x] Sales transaction audit trail with cashier/customer/payment/status context.
- [x] CSV/PDF export through the shared export service.
- [x] Empty and recoverable error states for every report tab.
- [x] Dark/system theme-aware presentation.
- [x] Unit coverage for period resolution and report insight rules.
