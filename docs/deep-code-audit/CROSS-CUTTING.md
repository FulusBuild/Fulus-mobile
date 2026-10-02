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

## X-002 — Local identity / cloud Auth identity namespace

Status: Closed in Part 02 source scope; runtime/production verification remains pending.

The local Users.local_id namespace is not universally the same identity as the Supabase Auth user ID. Owner identities created by AuthRepositoryImpl receive a local ULID, while cloud employee projections use the Supabase user ID. Part 02 found that bootstrap was assigning the local ID directly to ApiClient as the active cloud user, which could cause the refresh layer to select the wrong credential or fall back to a global credential.

Fix applied in Part 02:
- bootstrap no longer derives cloud identity from the local session row;
- startup/global refresh binds the in-memory cloud identity to the user ID returned by Supabase;
- once a cloud identity is explicitly selected, its refresh path never falls back to the legacy global token;
- per-user refresh restoration rejects a response issued for a different cloud user.

Relevant parts:
- Part 02 — Authentication & Sessions
- Part 03 — Employee, Membership & Access Control
- Part 04 — Business & Location Isolation
- Part 13 — Cloud APIs & Edge Functions
- Part 20 — Security & Production Hardening

Remaining verification:
1. Fresh owner account sign-in → kill/reopen → cloud sync with rotated refresh token.
2. Employee A → Employee B switching on a shared device, including process death between switch and next sync.
3. Rejected A token with a still-present legacy/global token for B must never authenticate as B.
4. Production Supabase response identity must remain equal to the selected local/cloud identity mapping.
