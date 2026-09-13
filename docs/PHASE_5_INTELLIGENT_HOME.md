# Phase 5 — Intelligent Home

## Product goal

Home is Fulus's daily command center, not a reporting dashboard. It should answer three questions immediately:

1. **How is the business doing today?**
2. **What needs my attention right now?**
3. **What is the fastest next action?**

The screen must remain useful offline and must not turn operational state into a wall of metrics.

## Current contract

### Primary hero

The hero is one evolving state:

- Before opening: yesterday's performance + **Open Shop**.
- Open: today's sales + **Close Shop**; the close action becomes visually stronger at the typical closing hour.
- Closed: today's final performance, with no misleading action.
- Employee: the employee's own shift only, with no business-wide totals or shop open/close controls.

### Attention layer

Operational notices are prioritized rather than displayed as a dashboard:

1. Low stock — blocks selling.
2. Pending customer credit — money that needs collection.
3. Unsynced work — technical state and lowest operational urgency.

Home shows **at most two** notices. The domain engine enforces this ceiling even if a presentation caller requests more, preventing future UI changes from accidentally creating an alert wall.

### Actions

Primary shortcuts stay action-first:

- Sell
- Add stock
- Add expense
- Reports

Actions navigate directly to the task instead of requiring the user to interpret a metric first.

### Activity

Recent money activity is intentionally limited to a short preview. The full history remains one tap away.

## Phase 5 quality bar

- Offline data remains immediately readable.
- No fake sync certainty or network-dependent loading gate.
- No duplicate sync-status messaging.
- Important controls meet the 48dp touch-target baseline.
- Long names and money values truncate safely instead of overflowing.
- Employee sessions never receive business-wide financial totals without the explicit dashboard permission.
- Pull-to-refresh and data refresh signals return Home to current local truth after sale, stock, income/expense, opening, or closing activity.
- Attention items are actionable and prioritized; zero-value notices disappear.
- Home should feel calm at a glance and become more useful as activity accumulates, rather than becoming visually denser.

## Implementation note

The existing Home surface already contains the hero, prioritized notices, action shortcuts, and recent activity. Phase 5 hardening starts by making the attention ceiling a domain invariant and testing it explicitly. Subsequent Phase 5 work should extend intelligence only when it creates a clearer decision or faster action; new cards or metrics must not be added merely because the data exists.
