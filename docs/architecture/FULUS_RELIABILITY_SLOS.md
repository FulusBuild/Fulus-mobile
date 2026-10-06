# Fulus Reliability SLOs

**Status:** Defined for P1 benchmark closure  
**Scope:** User-visible local-first reliability and synchronization behavior  
**Owner:** Fulus engineering

These are the initial measurable SLOs requested by the benchmark. They define what should be measured; they do not claim that production currently meets every target.

## 1. Local mutation visibility

**SLO:** 99% of successful foreground business mutations should become visible from local state within **250 ms** after the local transaction commits.

Measurement:
- start: local mutation command accepted
- end: first UI/state observation reflecting the committed mutation
- exclude network latency

Why: local-first behavior must feel immediate even when offline.

## 2. Eligible sync completion

**SLO:** 95% of durable operations that are eligible for synchronization and have a healthy network/session should reach a terminal server acknowledgement within **60 seconds**.

Measurement:
- start: operation enters the durable outbox
- end: acknowledged/applied, or a deterministic terminal rejection/conflict
- exclude time while network/session is unavailable

## 3. Sync recovery after transient failure

**SLO:** 99% of operations interrupted by a transient process/network failure should remain durable and be retried without manual data re-entry.

Measurement:
- verify operation identity survives restart
- verify no duplicate canonical business mutation is created
- verify queue reaches a terminal state after recovery

## 4. Canonical reconciliation freshness

**SLO:** 95% of devices with an available healthy connection should apply newly available authorized canonical changes within **60 seconds**.

Measurement:
- start: server change becomes available to the device's authorized feed
- end: local canonical projection commits the change

## 5. Restore safety

**SLO:** 100% of restore attempts must end in one of two safe states:
1. the restored database is reopened successfully and the maintenance fence is released, or
2. the previous database is restored and reopened, with the original restore error surfaced.

No partial database replacement is an acceptable outcome.

## 6. Financial precision

**SLO:** 100% of financial test transactions must preserve integer minor-unit magnitude across:
- local persistence
- domain arithmetic
- outbox serialization
- API request/response
- canonical reconciliation
- presentation formatting

No financial path may rely on IEEE-754 floating-point representation for persisted/calculated money.

## 7. Cardinality invariants

**SLO:** 100% enforcement of critical local cardinality invariants at the database boundary:
- at most one draft cart per location
- at most one open cash-drawer shift per location

Application checks remain useful for UX, but cannot be the sole enforcement mechanism.

## 8. Measurement requirements

Diagnostics should eventually emit:
- mutation-local-commit latency
- operation age/time-to-terminal-state
- sync cycle duration
- reconciliation lag
- restore duration/result
- queue retry count
- conflict/rejection count

These metrics should be tagged with non-sensitive dimensions such as operation type, result class, and app version. Do not emit customer financial payloads, access tokens, or other sensitive data.

## 9. Evidence boundary

Source and unit/integration tests can establish implementation correctness and deterministic invariants. The following require Android/production evidence before they can be claimed as achieved SLOs:
- process death during sync
- WorkManager restart
- physical database restore/reopen
- multi-device convergence
- production authorization/security configuration

The benchmark therefore distinguishes **SLO defined**, **SLO test-proven**, and **SLO production-observed**.
