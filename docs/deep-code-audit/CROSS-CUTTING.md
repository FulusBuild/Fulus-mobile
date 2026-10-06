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

## X-002 — Local identity / cloud Auth identity namespace

Status: Closed in Part 02 source scope; runtime/production verification remains pending.

The local Users.local_id namespace is not universally the same identity as the Supabase Auth user ID. Owner identities created by AuthRepositoryImpl receive a local ULID, while cloud employee projections use the Supabase user ID. Part 02 found that bootstrap was assigning the local ID directly to ApiClient as the active cloud user, which could cause the refresh layer to select the wrong credential or fall back to a global credential.

Fix applied in Part 02:
- bootstrap no longer derives cloud identity from the local session row;
- startup/global refresh binds the in-memory cloud identity to the user ID returned by Supabase;
- once a cloud identity is explicitly selected, its refresh path never falls back to the legacy global token;
- per-user refresh restoration rejects a response issued for a different cloud user.

## X-003 — Employee authorization projection vs server authority

Status: Partially proven; Part 03 source fixes applied.

Employee permissions are projected locally from the server-authoritative StaffClaim into user_permissions and consumed by router/app-shell and local repository checks. Cloud staff mutations independently enforce membership, role, permission-delegation, and location authorization. P03-001 fixed the staff device-inventory authorization boundary.

## X-004 — Business/location-scoped employee bootstrap

Status: Fixed in Part 04; production/runtime verification pending.

Employee provisioning previously entered the owner/admin full-business restore RPC. Part 04 introduced a separate employee restore contract scoped to the assigned active location while preserving intentionally business-wide catalog/customer identity.

## X-005 — Local financial representation

Status: **Closed in source; runtime/production evidence pending.**

The current local schema persists monetary values as SQLite INTEGER minor units across products, customers, sales, sale items, payments, expenses, income, returns, and cash-drawer state. Database migration v17 converts the historical REAL values at the migration boundary with explicit two-decimal rounding. Source inspection now proves the integer-safe representation; runtime upgrade/convergence evidence remains.

Relevant parts:
- Part 05 — Local Database & Persistence
- Part 07 — Domain & Business Logic
- Part 09 — Sales & Checkout
- Part 10 — Financial & Ledger Integrity
- Part 11 — Inventory & Stock

Required evidence:
1. Enumerate every monetary field and calculation.
2. Define the canonical integer unit.
3. Verify API/database compatibility.
4. Migrate persisted values without rounding loss.
5. Add exact-arithmetic regression coverage across sale/payment/credit/refund/expense/income/drawer paths.

## X-006 — Local cardinality constraints

Status: Open; requires Parts 06, 09, 10, and 16 cross-check.

Two local invariants are currently documented and enforced primarily by repository logic:
- one draft cart per location;
- one open cash-drawer shift per location.

The database does not currently provide corresponding uniqueness constraints. The audit deliberately did not add destructive migrations before determining how existing duplicate rows would be reconciled safely.

Required evidence:
1. Determine whether duplicate rows already exist on representative legacy databases.
2. Define non-destructive migration behavior.
3. Add database-level uniqueness.
4. Add concurrent repository regression tests.
5. Verify restore/import paths cannot bypass the invariant.

## X-007 — Local/cloud sale arithmetic contract

Status: **Closed in source; runtime evidence pending.**

The current Sale/SaleDraft, CartCubit, draft-cart repository, and cloud sale RPC agree on integer money, discount bounds, applied payment, credit, tendered cash, and change semantics. Exact local/cloud regression coverage exists.


## X-008 — Sale tender/change contract

Status: **Closed in source; runtime evidence pending.**

The current checkout preserves tendered cash separately from applied payment. Cloud V2 persists cash_tendered/cash_change and records only applied cash in the cash ledger. Split-payment and credit semantics are covered by exact regressions. Remaining proof is physical offline→sync execution.

## X-009 — Financial integer-money contract

Status: **Closed in source; runtime/production evidence pending.**\n\nThe coordinated migration from local floating-point monetary values to integer minor units is implemented. The cloud contract remains NUMERIC(14,2), with explicit decimal-string JSON boundaries and exact local integer arithmetic.

The migration must cover catalog prices, sales, payments, customer/supplier ledgers, expenses, income, returns, tax remittance, drawer state, drafts, reports and receipts. It must also define tendered cash versus applied payment versus change.


## X-010 — Inventory tracking-flag contract

Status: Closed in Part 11 source; CI green; production invariant checks clean.

The product `tracks_stock` flag was enforced by sales and absolute stock-setting paths but not by the common manual stock-movement boundary. Part 11 found that Product Detail exposed Record stock for non-tracked products, the local repository could create a stock row/movement, and the delta inventory command lacked the same server-side guard. The source fix now enforces the invariant locally, at the UI action boundary, and at the database insert boundary.

Relevant parts:
- Part 08 — Product & Catalog
- Part 09 — Sales & Checkout
- Part 11 — Inventory & Stock
- Part 13 — Cloud APIs
- Part 20 — Security & Production

Production evidence at audit time: zero inventory movements for non-stock-tracked products and zero business/location scope mismatches.

## X-011 — Stock-in composite transaction boundary

Status: Closed for the local Stock In transaction boundary; later sync/process-death/financial cross-checks remain owned by their respective parts.

Manual stock-in commits inventory and its outbox entry before optional product cost/supplier and supplier-credit writes complete. This creates a partial local-success boundary that differs from the atomic sale checkout transaction.

Relevant parts:
- Part 06 — Repositories
- Part 07 — Domain Logic
- Part 09 — Sales & Checkout
- Part 10 — Financial & Ledger Integrity
- Part 11 — Inventory & Stock

Evidence/fix completed in Part 11:
1. The single repository transaction now owns stock, movement, product metadata, supplier credit, and outbox writes.
2. Durable outbox entries remain inside the same transaction.
3. Regression coverage proves successful composite commit and rollback when supplier-credit validation fails.
4. The later sync/process-death retry dimensions remain part of Parts 14–17 rather than being claimed closed here.


## X-012 — Customer repayment overpayment contract

Status: Fixed in source; deployment and live convergence verification pending.

The local customer-credit contract intentionally records repayments above the outstanding balance, caps the customer balance at zero, and surfaces the excess. The authoritative cloud repayment mutation previously rejected the same operation, creating an offline-to-sync semantic mismatch.

Part 12 adds a migration that makes the cloud mutation follow the established local contract while preserving operation-id idempotency and authorization boundaries.

Relevant parts:
- Part 10 — Financial & Ledger Integrity
- Part 12 — Customers & Credit
- Parts 14–17 — Sync, recovery, process-death, and background execution

## X-013 — Credit return customer-ledger atomicity

Status: Fixed in source; deployment and live verification pending.

The authoritative return mutation previously attempted the same `customer_ledger_entries.operation_id` twice for a `refund_method='credit'` return. Because customer ledger operation IDs are unique per business, the second insert aborts the transaction. This makes the credit-refund path materially different from cash/card/mobile-money return paths.

Part 12 fixes the mutation by making the first credit branch validation/calculation-only and retaining a single ledger reversal mutation.

Relevant parts:
- Part 09 — Sales & Checkout
- Part 10 — Financial & Ledger Integrity
- Part 12 — Customers & Credit
- Parts 14–17 — Sync, recovery, process-death, and background execution


## X-014 — Customer repayment canonical operation identity

Status: Fixed in Part 12 source; CI/runtime verification pending.

A repayment mutation is committed remotely before the local push handler receives the response and attaches the server ID. Canonical ledger rows include the durable operation ID, which is also the local outbox row ID, but the ledger reconciler previously ignored it. That created a narrow concurrent pull/push window in which the same repayment could appear as two local ledger entries.

Part 12 now carries operation_id through canonical reconciliation and uses the durable outbox identity to reuse the existing local repayment row.

Relevant parts:
- Part 10 — Financial & Ledger Integrity
- Part 12 — Customers & Credit
- Parts 14–17 — Sync, recovery, process-death, and background execution

## X-015 — Employee canonical pull fencing

Status: Fixed in Part 14 source; CI/runtime verification pending.

The canonical pull path fences incoming server changes against pending local outbox mutations. The common entity lookup omitted employee rows, unlike the other registered sync entities. Part 14 added the employee serverId→localId lookup and a regression proving a queued employee update blocks canonical application.

The employee repository completion path was also cross-checked and already fences stale push completions against newer employee mutations.

## X-016 — Diagnostic failure containment

Status: Fixed in Part 19 source; CI/runtime verification pending.

The diagnostic logger's capture/write path already had fallback containment, but read/maintenance methods delegated directly to the store. Part 19 added a defensive facade boundary so a failing diagnostic store cannot become a user-facing failure.

## X-017 — Production Auth password security configuration

Status: Open; production configuration evidence.

Supabase's production security advisor reports leaked-password protection disabled. This is an Auth configuration item rather than a repository migration. It must be enabled and re-verified in production.

## X-018 — Final runtime evidence boundary

Status: Open.

Parts 15, 17, 18 and 19 still require real Android/runtime evidence for fresh-install restore, process-death WorkManager recovery, instant navigation/branch behavior, and diagnostic capture/fallback. Part 20 additionally requires a targeted production authorization matrix before the audit can be declared fully closed.

