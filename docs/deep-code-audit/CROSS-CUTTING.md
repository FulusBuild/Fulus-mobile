# Cross-Cutting Audit Findings

## X-001 — Restore / sync maintenance boundary

Status: Partially proven / deferred for cross-part ownership.

Restore closes the live Drift database and reopens a fresh AppDatabase, while running sync services retain direct references to the original database instance. The UI restart gate prevents normal business use after a successful restore, but source inspection does not prove that an active sync cycle cannot overlap closeForMaintenance.

Relevant parts:
- Part 01 — App Bootstrap & Lifecycle
- Part 15 — Backup, Restore & Cross-Device Provisioning
- Part 17 — Background Execution & OS Lifecycle

Required evidence before a fix:
1. Reproduce restore while push, pull, or recovery is actively using the DB.
2. Determine whether closeForMaintenance can race an active sync transaction/cycle.
3. Define the smallest shared maintenance gate.
4. Add regression coverage proving restore and sync cannot overlap unsafely.

No speculative cross-system rewrite is applied from Part 01 alone.