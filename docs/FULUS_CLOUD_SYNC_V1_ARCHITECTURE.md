# Fulus Cloud Sync v1 — Production Architecture

**Status:** implementation plan and source-of-truth architecture  
**Scope:** local-first business data synchronization for Fulus Mobile  
**Principle:** the phone remains operational offline; cloud state is authoritative when connected; retries and crashes must converge without duplicate business effects.

## 1. System model

```
DEVICE
  SQLite local state
       │
       ├── business mutation
       └── durable outbox operation
                 │
                 ▼
          Fulus Cloud API
                 │
       ┌─────────┴─────────┐
       ▼                   ▼
 command transaction    change feed
 idempotency             sequence
 authorization           canonical read
 concurrency             │
       │                 ▼
       └────────────► Sync Coordinator
                           │
                     canonical reconcile
                           │
                     local authoritative state
```

Fulus does **not** synchronize the SQLite database itself. It synchronizes business operations and authoritative entity state.

## 2. Current implementation verified in source

### Local/outbound
- Drift/SQLite is the local business store.
- `sync_queue_items` is the durable outbox.
- Repository mutations enqueue sync work.
- `SyncEngine` drains the outbox with retry classification.
- Phase 1 adds follow-up draining when new work is enqueued during an active drain.
- Restore clears stale outbound queue state before importing a cloud snapshot.

### Cloud command transport
- `FulusSyncApi` is the Fulus Cloud command transport.
- `fulus-api` authenticates the bearer token, resolves business membership, verifies device authorization, and dispatches canonical commands.
- Canonical server functions use stable operation/client references for idempotent business effects.
- Income, cash-drawer, and location command contracts now exist in the repository and must be verified against the deployed database/function state before being considered production-complete.
- Catalog writes are routed through the Fulus API, but their idempotency/event semantics require explicit verification.

### Inbound
- `FulusSyncCoordinator` persists a per-business cursor.
- A change is reconciled locally before its sequence is acknowledged.
- `fulus-sync-state` fetches canonical entity state rather than requiring change-feed payloads to reconstruct aggregates.
- Typed canonical reconcilers exist for the current syncable entity surface.
- Product stock reconciliation rebuilds local stock from authoritative server state.

### Runtime
- Bootstrap constructs the coordinator and typed reconciler.
- Sync readiness gates normal triggers.
- Startup performs authentication, membership selection, device registration, initial reconciliation, then marks Sync Ready.
- Restore has an explicit reconciliation/readiness path.

## 3. Non-negotiable invariants

### Mutation atomicity
Every local syncable mutation must be:

```
ONE LOCAL TRANSACTION
  mutate business row
  append outbox operation
```

There must be no successful local business mutation that can lose its outbound operation because the app died between two separate transactions.

### Idempotency
Every outbound operation has a stable operation ID.

The server must make:

```
same operation ID + same request
    => one business effect
    => repeat returns the original authoritative result
```

A timeout after server commit must therefore be safe to retry.

A reused operation ID with a materially different request must be rejected rather than silently changing the original operation.

### Inbound acknowledgement
Never advance the cursor before successful local reconciliation.

A crash may replay a change. It must never skip one.

### Canonical state
A feed event is a notification that an entity changed. The canonical-state endpoint is the source used to reconstruct the entity/aggregate.

### Tenant/device isolation
Every cloud operation must be scoped by:
- authenticated user
- active business membership
- active registered device
- business ID

## 4. Entity contract

Every syncable entity must have all of these:

1. local mutation path
2. outbox operation
3. client command
4. server transaction
5. idempotency
6. change-feed event
7. canonical read
8. inbound reconciliation
9. retry/error classification
10. tests for offline/retry/replay
11. concurrency semantics where updates can race

Current entity surface:

- sale
- customer
- customer ledger
- product
- category
- supplier
- location
- expense category
- expense
- income
- return
- stock movement
- cash drawer shift

A handler existing in Dart is **not** sufficient evidence that an entity is production-syncable. The complete contract above must exist.

## 5. Update/concurrency model

The next architectural layer is server revisioning.

For mutable entities, the server should expose a monotonic revision/version (or equivalent update token). A client update should carry the revision from which it was based:

```
client base_revision = 7
server current_revision = 7
        │
        ▼
accept update
server revision = 8
```

If another device has already advanced the entity:

```
client base_revision = 7
server current_revision = 8
        │
        ▼
CONFLICT
```

The server must not silently overwrite the other device's state.

Conflict policy must be explicit per entity. Financial event records should generally be immutable events; mutable master data such as customers/products/suppliers requires a defined conflict policy.

## 6. Dependency model

Priority is useful for throughput but is not a dependency graph.

The target model is:

```
location/category/supplier
          ↓
       product
          ↓
 customer/location/product identities
          ↓
 sale / return / repayment / inventory operation
```

Each outbox operation should eventually be able to declare dependencies on other operation IDs. A dependent operation must remain blocked until its prerequisites settle.

## 7. Error model

The sync engine already has stable categories:

- NETWORK
- TEMPORARY_SERVER
- AUTH_EXPIRED
- PERMISSION
- VALIDATION
- CONFLICT
- DEPENDENCY_NOT_READY
- PERMANENT_NOT_FOUND

The remaining hardening task is to ensure transport/server responses provide machine-readable error codes so classification does not depend primarily on message text.

## 8. Recovery model

Required recovery guarantees:

- offline → queued → reconnect → push
- timeout after server commit → retry without duplicate effect
- app killed during push → durable retry
- app killed during pull → replay unapplied change
- token expiry → preserve queue and restore session
- device revoked → stop cloud writes without losing local work
- restore → stale outbound queue removed → canonical reconciliation → Sync Ready
- cursor invalid/too old → explicit bootstrap/recovery, never silent data loss

## 9. Sync Health

Sync Health must report facts from the sync system itself:

- cloud connection
- device authorization
- Sync Ready
- last successful push
- last successful pull
- pending operations
- retrying operations
- blocked/attention operations
- conflicts
- last sync error
- current cursor

Queue count alone is not sufficient health telemetry.

## 10. Scaling path

The first production version can use the current cursor/change-feed model.

Before large scale, add:
- indexed business + sequence feed reads
- bounded page sizes
- canonical aggregate batching
- snapshot/bootstrap for new devices
- cursor-too-old recovery
- 90-day `sync_changes` retention with bounded 5,000-row pruning batches;
- daily pg_cron scheduling for feed compaction;
- stale-cursor bootstrap when a device falls behind the retained window;
- idempotency records are not pruned by the feed-retention job;
- server-side observability
- per-business isolation and rate limits

Current hardening also covers sync-path foreign-key indexes and duplicate-index cleanup; remaining advisor findings are outside the sync critical path or require broader product-level policy decisions.

The architecture should allow these without changing the local-first application model.

## 11. Implementation sequence

### Phase 1 — correctness
- restore stale queue cleanup
- queue drain race
- repository/outbox atomicity
- complete update coverage where server commands exist
- regression tests

### Phase 2 — contract completeness
- audit every handler against a real server command
- verify every command emits a change event
- verify every command is idempotent
- verify canonical reads
- eliminate silent legacy cloud write paths

### Phase 3 — concurrency
- server revisions/update tokens
- expected-revision commands
- durable mutation base cursors
- dirty-local protection
- durable conflict records
- explicit "Use Cloud version" conflict resolution that reconciles canonical state before clearing the parked mutation

### Phase 4 — recovery and scale
- cursor-too-old detection is implemented and returns a machine-readable recovery-required response
- snapshot/bootstrap recovery
- batch canonical reads
- 90-day change-feed retention/compaction with scheduled bounded pruning
- authoritative sync health

### Phase 5 — production verification
Run independent:
1. architecture audit
2. client-flow audit
3. server-flow audit
4. failure/recovery audit
5. final diff/CI/integration audit

Only after all five pass should a release APK be built and tested on a real device.

## 12. Definition of done

Fulus Cloud Sync v1 is complete when a business can:

- create/update business data offline;
- close and reopen the app without losing pending work;
- reconnect and converge without duplicate financial effects;
- use multiple authorized devices;
- receive changes from another device;
- survive crashes during push/pull/restore;
- recover from authentication/device failures;
- detect and handle concurrent mutable-data edits explicitly;
- inspect trustworthy sync health;
- restore a business and reach Sync Ready only after reconciliation.

This document is the architecture target. Individual bug fixes must be evaluated against it rather than becoming isolated sync behavior.
