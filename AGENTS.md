# Fulus Engineering — Mandatory Pre-CI Verification Protocol

> **READ THIS BEFORE DOING ANY WORK IN THIS REPOSITORY.**
>
> This is a mandatory engineering rule for every future Fulus development, audit, sync, migration, bug-fix, and hardening session.
>
> **Core principle: CI is the second proof layer, not the first integration test.**
>
> Before committing or triggering CI, prove the change locally or against the appropriate E2E/test environment whenever the behavior can be exercised there.

## 1. Required workflow

**Inspect → Trace → Verify contract → Execute → Verify authoritative state → Verify change feed → Test replay/rejection → Review diff → Commit → CI → Inspect CI → Continue**

Do not skip directly from implementation to CI when pre-CI verification is possible.

A green CI run does **not** by itself prove that the relevant production behavior is correct.

## 2. Mandatory full-chain trace

For every mutation or sync operation being added or changed, trace:

UI / Repository
→ Local DB transaction
→ Outbox / SyncQueue
→ Operation payload
→ submitOperation()
→ Edge Function / HTTP action
→ Action mapping
→ RPC / PostgreSQL function
→ Database tables / constraints / triggers
→ sync_changes
→ Pull / reconciliation
→ Local DB
→ UI

Verify using actual source/schema/function definitions:

- exact operation name
- exact JSON payload
- exact field names and types
- nullable vs required fields
- local IDs vs server IDs
- identifier semantics
- exact Edge Function action
- exact PostgreSQL function name
- exact PostgreSQL function signature
- exact argument order
- database-side validation
- tables modified
- triggers
- change-feed events
- idempotency behavior
- response shape
- error shape
- client response parsing
- reconciliation behavior

**Never infer a server contract from client code alone.**

## 3. Contract-mismatch checklist

Before CI, explicitly challenge:

- identifier mismatch (for example product_id vs sale_item_id)
- payload field mismatch
- payload nesting mismatch
- response-shape mismatch
- function-signature mismatch
- argument-order mismatch
- enum/string mismatch
- nullable/non-nullable mismatch
- local ID/server ID mismatch
- operation-name mismatch
- database entity-name mismatch
- change-feed entity-type mismatch
- idempotency-key mismatch
- authorization/RLS mismatch
- reconciliation mismatch

Ask:

> **What is the most likely integration mismatch here, and what evidence can I obtain before CI to disprove it?**

## 4. Mandatory pre-CI execution

For every mutation that can be exercised through the E2E/test environment:

### A. Execute the real mutation

Do not rely only on compilation or unit tests.

### B. Verify the API result

Check:

- HTTP status
- response body
- response nesting
- returned server ID
- idempotency status

Do not assume all API responses have the same shape.

### C. Verify authoritative database state

Prove:

- expected row exists
- expected values are correct
- relationships/FKs are correct
- no unintended duplicate exists
- timestamps are correct
- related records were created/updated atomically where required

### D. Verify the change feed

Prove the expected sync_changes event has:

- correct entity type
- correct entity ID
- correct operation/event type
- correct payload
- correct sequence/order
- correct timestamp

### E. Verify replay/idempotency

Repeat the same operation and prove:

- no duplicate business record
- deterministic response
- idempotency key is respected
- correct already-applied/replay semantics

### F. Verify rejection

Send an intentionally invalid mutation and prove:

- authoritative transaction rolls back
- no partial business state remains
- failure is preserved
- local optimistic state is reconciled if necessary
- user-facing error is sanitized

### G. Verify reconciliation

Prove canonical server state can reach and correctly update the local database.

## 5. PostgreSQL function verification

Before modifying, wrapping, or calling a Supabase RPC/function, inspect the actual current function definition.

Verify:

- schema
- function name
- argument names
- argument types
- argument order
- return type
- SECURITY DEFINER / INVOKER
- search_path
- grants/revokes
- RLS interaction
- functions it calls
- triggers and constraints it depends on

**Never write a wrapper around an assumed function signature.**

If a migration calls public.some_function(...), prove that the target function actually exists with that exact signature.

## 6. Migration verification

Every database migration requires three checks:

### Static
Review SQL syntax, signatures, constraints, indexes, RLS, grants/revokes, idempotency, and compatibility.

### Existing-schema compatibility
Compare the migration against the actual current schema and function definitions.

### Live behavior
Apply it to the appropriate Supabase environment and exercise the affected behavior.

A migration applying successfully is **not** proof that the behavior is correct.

## 7. Mutation matrix

Maintain a complete mutation matrix during the Cloud Sync audit:

| Mutation | Client Payload | API Action | DB Function | DB Effects | Change Feed | Idempotency | Replay | Rejection | Reconciliation |
|---|---|---|---|---|---|---|---|---|---|

At minimum cover:

- product create/update
- category create/update
- supplier create/update
- location create/update
- stock creation
- stock adjustment
- inventory movement
- sale
- sale item
- sale payment
- Quick Sale
- return
- customer create/update
- customer repayment
- income
- expense
- expense category
- cash drawer open
- cash drawer close
- staff/user changes
- permissions/membership changes
- every other cloud-synced business entity

Do not mark a mutation complete merely because its happy path works.

## 8. Outbox/retry/process-death verification

For sync-related changes, consider and test:

- local transaction atomicity
- outbox creation in the same transaction
- process death between local commit and push
- duplicate enqueue
- retry after transient failure
- permanent rejection
- blocked/conflict operations
- concurrent queue processing
- stale operation state
- restart recovery
- cursor advancement only after successful application
- cursor-too-old/recovery behavior

## 9. Pull/reconciliation verification

Verify:

- ordered change application
- cursor persistence
- no skipped changes
- no duplicate application
- idempotent handlers
- deletes/tombstones where applicable
- canonical server values override rejected optimistic values
- relationship/FK ordering
- timestamp preservation
- recovery after stale cursor
- post-recovery final reconciliation

## 10. Restore verification

For restore/import changes:

- restore ordering follows FK dependencies
- owner/business identity is preserved correctly
- staff/membership relationships are valid
- IDs are handled consistently
- restored state can immediately sync again
- restored data does not generate unintended duplicate mutations
- restore followed by pull/push is tested

## 11. Multi-device and conflict verification

Where relevant, test:

- device A mutation → device B pull
- device B mutation → device A pull
- concurrent mutations
- duplicate/replayed commands
- rejected optimistic mutations
- canonical reconciliation
- device revocation
- unauthorized device
- business/user mismatch

## 12. Security and authorization

For affected operations verify:

- authenticated vs unauthenticated behavior
- business membership
- device ownership/registration
- permissions
- RLS
- SECURITY DEFINER boundaries
- search_path hardening
- privilege grants/revokes
- cross-business access is rejected
- cross-user/device access is rejected

Do not weaken security merely to make an E2E test pass.

## 13. User-facing errors

Internal details such as raw SQL, PostgreSQL errors, stack traces, table names, and implementation details must not leak into normal user-facing error messages.

Test the actual user-facing path where practical.

## 14. Evidence status

Classify every audit item:

- 🟢 **PROVEN** — directly verified through implementation plus execution/test/evidence.
- 🟡 **PARTIAL** — some evidence exists, but an important path remains unverified.
- 🔴 **UNKNOWN** — not yet verified.

Never convert 🟡 or 🔴 to 🟢 through assumption.

## 15. CI discipline

Before CI:

1. inspect implementation
2. trace the complete contract
3. inspect actual server/database definitions
4. run relevant unit/widget tests
5. execute the real E2E mutation when possible
6. verify authoritative DB state
7. verify change feed
8. test idempotent replay
9. test rejection
10. verify reconciliation
11. inspect migration/schema compatibility
12. review git diff
13. run git diff --check
14. commit
15. trigger CI

If CI discovers a contract mismatch that should reasonably have been discoverable before CI, do not merely patch and rerun CI. Identify why pre-CI verification failed to catch it and strengthen the process.

## 16. After CI is green

Do **not** conclude that the audit is finished.

After every successful CI run:

- inspect what CI actually covered
- compare it against the mutation matrix
- identify untested paths
- continue the current audit phase
- perform adversarial testing
- inspect production/test state where appropriate
- move to the next incomplete area

Never use:

> "CI is green, therefore Cloud Sync V1 is complete."

Completion requires evidence across the entire required scope.

## 17. Session handoff rule

Every future session working on Fulus must:

1. Read this file before making code/database changes.
2. Read the relevant existing audit/handoff documentation.
3. Inspect the current branch/working state.
4. Determine what is already proven versus unproven.
5. Continue from evidence rather than assumptions.
6. Preserve this protocol unless explicitly superseded by a newer repository-level engineering policy.

## 18. Fulus-specific operating principle

Fulus is intended to be a durable, local-first business system. Sync correctness therefore includes business correctness.

A successful HTTP request is not enough.

A successful database mutation is not enough.

A successful change-feed event is not enough.

A green CI run is not enough.

The final proof must establish that:

**local intent → authoritative mutation → change feed → remote propagation → local reconciliation → retry/recovery → long-term data integrity**

behaves correctly under normal, duplicate, rejected, interrupted, concurrent, restored, and recovered conditions.

## Final rule

> **Do not use CI to discover an integration contract you could have verified before CI.**
>
> **Prove the contract first. Let CI independently prove the implementation.**
