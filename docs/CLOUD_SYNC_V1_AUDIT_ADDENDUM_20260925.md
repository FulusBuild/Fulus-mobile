# Cloud Sync V1 Audit Addendum — 2026-09-25

## Live mutation RPC inventory

Production project: `bejcuvoxemwomcatgyxz`.

The complete `public.fulus_api_*` inventory was queried from `pg_proc`, including identity arguments, SECURITY DEFINER state, function configuration, effective ACL, and function definitions.

Findings:
- Current externally usable mutation wrappers are restricted to `service_role`; no `anon`, `authenticated`, or `public` EXECUTE grant was found on the audited mutation wrapper surface.
- Current hardened wrappers use SECURITY DEFINER with an empty `search_path` and perform business/permission/device/location authorization before delegating to the authoritative mutation.
- Current idempotent command wrappers either lock the `idempotency_keys` row with `FOR UPDATE` directly or delegate to an authoritative helper that performs the same idempotency protocol. Representative examples verified in production include inventory adjustment/set, customer create/update, location create, expense update, cash-drawer open/close, income create, sale create, return create, repayment, and sale payment.
- Legacy overloads remain present in the database in some names, but the inspected legacy overloads have no external `anon`/`authenticated`/`public` execute grant. They are therefore not an exposed API path in the current privilege state.
- Authoritative helper functions emit `sync_changes` in the same PostgreSQL transaction as their mutation. Composite sale/return/payment paths emit the corresponding aggregate and derived stock/ledger changes from the same function transaction.
- A legacy `create_location` helper was found with an unlocked idempotency read and incomplete request-hash validation, but its current client-facing `fulus_api_create_location` wrapper is the hardened overload and performs the locked idempotency/request-hash/device/user checks. No externally exposed defect was established from the legacy helper because its effective ACL is not external.

Status: 🟢 current exposed mutation surface has no new authorization/idempotency defect established. Legacy database overloads remain a maintenance/deletion candidate, not an active exposure.

## Cursor/recovery adversarial coverage

Added regression coverage to `test/sync/fulus_sync_coordinator_test.dart` in commit `4988bc30ef6883f0baf7ce3074dd67c80148f80a` for:
- reordered change-feed sequences;
- duplicate sequence values;
- empty page with `hasMore=true`;
- response cursor ahead of the durable requested cursor.

Current coordinator behavior verified by implementation plus existing tests:
- changes are applied before cursor acknowledgement;
- `next_cursor` is treated only as a pagination hint;
- durable cursor advancement is monotonic;
- already-acknowledged changes are skipped;
- global sequence gaps are permitted while returned pages must remain strictly ordered;
- cursor-too-old recovery persists the authoritative snapshot boundary before post-recovery delta pull.

CI evidence limitation:
- GitHub workflow lookup for commit `4988bc30ef6883f0baf7ce3074dd67c80148f80a` currently exposes no workflow run/status. The repository workflow is configured for pushes to `main`, but the connected GitHub Actions endpoint has not exposed a run for this commit. Therefore this test commit is **FIXED_PENDING_CI**, not CI-proven.

Remaining cursor gates:
- explicit cursor persistence failure injection;
- cursor-too-old followed by post-recovery delta failure;
- recovery process death;
- physical Android process-kill/restart evidence.

Next audit focus: production integrity/adversarial data invariants and the remaining cursor/recovery failure-injection matrix. Do not deploy a migration unless a concrete production defect is proven.
