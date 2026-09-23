# Fulus Full-System Battle-Test Protocol

## Mission

This protocol is for independent adversarial testing of Fulus Mobile.

Do not try to confirm that Fulus works. Try to discover how it can fail.

Treat previous AI conclusions as hypotheses. The goal is to expose failures that could cause data loss, duplication, corruption, incorrect business results, unsafe recovery, misleading UI, or long-term operational problems.

## Start with the real repository

Before auditing:

- inspect architecture and data flow;
- inspect database/schema and migrations;
- inspect repositories/services and state management;
- inspect local persistence and cloud synchronization;
- inspect authentication/authorization;
- inspect backup/restore;
- inspect reports and derived calculations;
- inspect tests and CI;
- inspect recent changes and relevant documentation.

Do not rely on memory when repository evidence is available.

## Attack every layer

### Sales

Try double taps, repeated submissions, interrupted checkout, app crash/force-kill, network loss, offline sales, timeouts, retries, duplicate requests, partial payments, credit, discounts, returns, voids, invalid/zero/very large/boundary quantities and prices, and concurrent activity from multiple devices.

Trace each event through local data, stock, money, customer/credit, reports, sync, and cloud state.

### Inventory

Attack additions, reductions, sales, returns, voids, adjustments, transfers, multiple locations, zero/negative/very large quantities, concurrent changes, offline changes, duplicate sync, stale screens, and interrupted operations.

Verify that stock cannot silently disappear, duplicate, or diverge from legitimate business events.

### Money and finance

Attack income, expenses, payments, refunds, reversals, credit payments, duplicate/partial/failed/offline payments, large values, boundary dates, retries, crashes, and concurrent transactions.

Reconcile financial totals with underlying transactions.

### Customers and credit

Attack credit sales, partial/full/duplicate/over payments, returns against credit, offline repayments, concurrent updates, archived/deleted customers, and long transaction histories.

Verify balances against the underlying ledger.

### Cloud sync

Treat synchronization as a distributed-systems problem.

Test no network, intermittent network, timeouts, server rejection, server accepts request but response is lost, duplicate requests, retries, app/device restart, reordered operations, stale queues, concurrent changes on multiple devices, conflicts, partial sync, authentication/token expiry, long offline periods, large pending queues, sync after upgrade, and sync after restore.

Explicitly verify idempotency, ordering, conflict handling, retry safety, local durability, cloud durability, eventual consistency, and truthful sync states.

Never accept “it syncs” as sufficient evidence.

### Database and migrations

Attack interrupted writes, transaction boundaries, concurrent writes, corrupted/incomplete state, old databases, skipped versions, interrupted migrations, insufficient storage, renamed/removed fields, and pending sync data across upgrades.

Verify that critical multi-step business operations are atomic where required.

### Backup and restore

Test:

BACKUP → LOSS/DELETE SIMULATION → RESTORE → SYNC → NORMAL USE

and:

BACKUP → CONTINUE USING APP → RESTORE OLD BACKUP

Check for missing data, duplicate records, broken relationships, stale sync operations, invalid IDs, and report inconsistencies.

### Authentication and authorization

Test owner/cashier roles, multiple cashiers, expired sessions, account switching, stale permissions, offline behavior, and deactivated users.

Verify both security and legitimate offline business continuity.

### UI/UX

Attack small phones, tablets, unusual aspect ratios, long names, large numbers, empty/loading/error/offline/sync states, repeated taps, slow devices, large datasets, background/foreground transitions, orientation changes, and destructive actions.

Ask whether a non-technical business owner could misunderstand what happened or lose confidence/data because the interface communicates the wrong state.

### Reports

Cross-check sales, returns, voids, expenses, income, payments, credit, stock, dates, locations, and cashiers.

Test midnight, date boundaries, month/year boundaries, historical corrections, returns, voids, offline records, and synced records.

Trace important numbers back to source transactions.

### Scale and long-term durability

Reason about realistic growth in products, transactions, customers, sync queues, reports, and devices.

Look for inefficient queries, unbounded memory/queue growth, excessive network calls, large payloads, slow startup, UI freezes, and report/sync degradation.

Ask what could break after years of daily use.

### Security and trust

Investigate realistic risks involving authorization, local/cloud storage, backups, tokens, identifiers, input handling, sensitive logs, and network assumptions.

Focus on protecting legitimate Fulus users and their business data.

## Cross-system battle tests

Never audit subsystems only in isolation.

Trace complete events such as:

SALE → LOCAL DB → STOCK → PAYMENT → CREDIT → REPORT → SYNC → CLOUD → OTHER DEVICE → REPORT → BACKUP → RESTORE → SYNC

Repeat equivalent end-to-end tracing for stock additions, expenses, income, credit payments, returns, voids, transfers, product changes, and customer changes.

## Property and invariant testing

Define properties that must remain true regardless of execution path.

Examples:

- transactions cannot be duplicated;
- completed transactions cannot disappear;
- stock changes require legitimate causes;
- payments cannot reduce balances twice;
- local success survives cloud failure;
- retries do not create duplicate business events;
- reports reconcile with source records;
- valid restore preserves business relationships.

Discover additional invariants from the actual architecture.

## Chaos/failure injection

Where practical, deliberately simulate network disappearance/recovery, request timeout, accepted request with lost response, app crash/force-kill, device restart, database failure, storage failure, authentication expiry, simultaneous changes, duplicate queue entries, stale UI/data, and interrupted migration.

The question is not only “does it work?” but “does it fail safely?”

## Test the tests

Audit whether tests can actually detect broken behavior.

Look for missing coverage of failure paths, offline paths, retries, concurrency, migrations, backup/restore, synchronization, cross-system invariants, and realistic end-to-end behavior.

Green CI is evidence, not proof of universal correctness.

## Fix loop

For every real defect:

1. explain the business impact;
2. reproduce it where practical;
3. identify root cause;
4. implement the safest appropriate fix;
5. add regression coverage;
6. run relevant validation;
7. inspect the diff;
8. attempt to break the fix again.

Do not stop at a theoretical issue list.

## Evidence standard

Never claim bug-free, impossible to break, 100% reliable, or guaranteed safe.

Instead report what was tested, what passed, what was fixed, what remains untested, what remains a plausible risk, and what limitations are intentionally accepted.

## Final audit report

Produce:

1. Executive summary.
2. Systems audited.
3. Findings with severity and business impact.
4. Fixes and evidence.
5. Failure scenarios actually tested.
6. Cross-system findings.
7. Remaining risks.
8. Completion matrix mapping requirements to implementation and test evidence.

Use severity based on business consequence:

- **P0:** catastrophic potential business/data loss.
- **P1:** material corruption of money, inventory, customers, or transactions.
- **P2:** significant functional failure or serious disruption.
- **P3:** minor functional issue.
- **P4:** cosmetic/low impact.

Do not rank by how impressive the bug looks technically. Rank by potential business consequence.

## Final rule

Do not try to make the product owner feel confident.

Try to make Fulus deserve confidence through evidence.
