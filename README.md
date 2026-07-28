# BMS Mobile — Foundation Checkpoint

This is for anyone — human developer or another Claude instance — picking up
work on BMS Mobile. It covers what the project is, what's built and passing
right now, the conventions worth keeping, and the mistakes worth not
repeating. **Read this before touching code.** Nearly every mistake in
Section 4 happened because a description like this one existed somewhere but
wasn't fully read first.

## Status: Phase 0 is code-complete

Every entity vertical Phase 0 calls for is built, wired, and passing CI on
both sides (backend `pytest`, mobile `flutter analyze --fatal-infos` +
`flutter test`). What's *not* independently confirmed from this repo alone is
the actual exit criterion: Architecture Section 13's real end-to-end
test — create a sale offline on a real (or emulated) device, kill the app,
restart it, reconnect, confirm it synced clean. Green CI is real signal, but
it's a different claim from that one. Check whether that's actually happened
before treating Phase 0 as fully closed, not just code-complete.

## 1. What this project is

BMS (Business Management System) is a full-stack business management
system — POS, inventory, customers, expenses/income, employees — built as a
web app (Next.js + FastAPI) with a Tauri desktop wrapper. BMS Mobile is a
Flutter app letting staff use the same system from a phone, with one
non-negotiable requirement: **it must work fully offline and sync
automatically once connectivity returns.** A cashier ringing up a sale in a
shop with bad signal must never see that sale fail or hang.

Two documents describe the intended design (ask if you weren't handed
these):

- **`BMS-Mobile-Product-Design-Bible-COMPLETE.md`** — the UX/product spec.
  16 volumes: screens, flows, user-facing behavior.
- **`BMS-Mobile-Flutter-Architecture-2.md`** — the technical architecture.
  Folder structure, state management, database design, sync engine, security.
  Numbered sections this repo's own comments constantly cite ("Section 3",
  "Section 7a", etc.).

**Both documents contain real errors**, found the hard way over this
project's history — see Section 4. Treat them as a map, not the territory.
Verify against the actual backend Python code and this repo's actual Dart
code before trusting either doc's description of what exists.

## 2. Repo layout

Two codebases, usually handed over separately:

```
bms/backend/              — FastAPI + SQLAlchemy + Alembic (Python)
  app/
    models/                — SQLAlchemy ORM models
    routers/                — one file per resource
    schemas/                — Pydantic request/response
    services/               — business logic (routers call into these)
  alembic/versions/         — migrations, numbered 0001, 0002, ...
  tests/                    — pytest, one file per resource

bms-mobile-foundation-checkpoint/   — this repo (Flutter)
  lib/
    app/                    — bootstrap.dart (DI wiring), providers.dart,
                              router.dart, app.dart
    core/                   — config, errors, security (PIN hashing), theme
    data/
      local/database/        — Drift schema (tables.dart, database.dart)
      local/secure_storage/
      remote/                 — ApiClient + one *_api.dart per resource
      repositories/           — concrete repository implementations + mappers
    domain/
      entities/               — plain domain types + DTOs, zero Flutter/Drift
                                imports
      repositories/           — abstract repository interfaces
    sync/                   — SyncEngine, SyncQueue, SyncTriggers, per-entity
                              handlers
  test/
    repository/             — real in-memory Drift, no mocks
    sync/                   — sync engine + handler tests (mocktail for the
                              API layer only)
  android/                 — real scaffold now exists (see Section 8)
  .github/workflows/ci.yml
```

Building or fixing a mobile feature almost always means checking (and
sometimes fixing) the backend endpoint it talks to.

## 3. What's built — the full vertical list

**Push-sync entities** (local-write-first → sync queue → sync engine →
backend), all following the pattern in Section 5:

- **Sale** — the original, most complete vertical. `locationId` required.
  Has a known gap: a product/customer referenced by a sale needs its own
  server ID before the sale can sync.
- **Customer** — no `locationId` at all (Architecture Section 7a: a
  customer's identity/balance/history belong to the whole business, not one
  location).
- **Expense**, **IncomeRecord** — `locationId` required, mirroring Sale.
- **StockMovement** — a deliberate deviation from the 8-step pattern: three
  write methods (`recordStockIn`/`recordStockOut`/`recordAdjustment`), not
  one generic `create`, because the backend has three distinct request
  shapes. `markSettled(localId)` instead of `markSynced(localId, serverId)`,
  since none of the three backend endpoints return a server ID for the
  movement itself. `StockMovementType.transfer` and `toLocationId` exist in
  the schema, deliberately unused by any write path — real groundwork for a
  Phase 2 feature, not dead code to remove.

**Read + pull-sync entities** (`syncFromServer()`, no `SyncTask`/`SyncHandler`,
nothing pushed through `SyncQueue`):

- **Product** — paginates `GET /api/inventory/products`, upserts into
  `Products` + `ProductStockLevels`. Has its own `reconcileStockLevel()`
  method so `StockMovementSyncHandler` can update one product's stock from a
  response it already has, without re-pulling the whole catalog.
- **Location** — the backend had *zero* location infrastructure until this
  project built it (see Section 6). `GET /api/locations` returns a bare,
  unpaginated array.
- **BusinessSettings** — domain type is named `BusinessProfile`, not
  `BusinessSettings` (see Section 4 for why). Singleton row, fixed local id
  `'singleton'`.

None of the three above has a real trigger yet beyond the on-launch,
fire-and-forget call in `bootstrap.dart` (see Section 3a) — no manual
"Sync Now" button, no pull-to-refresh, because no screen exists yet to put
one on.

**Auth**: login, silent refresh on launch, refresh-token rotation, the
`ApiClient` interceptor's reactive 401-refresh, and the owner-approval PIN
system (`ApprovalPinRepository`, real Argon2id hashing via
`dargon2_flutter`). `AuthRepositoryImpl` now persists the signed-in user to
the local `Sessions` table — `restoreSession()` falls back to this cached
identity when the network is unreachable, rather than returning null for the
whole launch.

**Sync engine** (`SyncEngine`, `SyncQueue`, `SyncTriggers`): generic and
entity-agnostic — priority lanes, retry-with-backoff, "needs attention" after
repeated failures, connectivity/foreground/manual triggers. Adding a new
push-sync entity means writing a `SyncHandler` and registering it in
`bootstrap.dart`'s handler map, not touching the engine itself.

**App shell**: `main.dart` → `bootstrap()` → `BmsApp` (theme, light/dark via
`AppTheme`/design tokens) → `go_router`-based `router.dart` with five named
routes (`home`/`sell`/`stock`/`money`/`more`, matching the Product Design
Bible's five destinations) — each currently rendering a real, honest
placeholder screen ("Volume 5 — cart, checkout. Not yet built."), not a mock.
No feature screen actually consumes any repository yet.

### 3a. The on-launch sync trigger

Decided once, for Location + BusinessSettings + Product together, in
`bootstrap.dart`: fired unawaited, right after all three repositories are
constructed, each wrapped in its own `.catchError((_) {})`. Deliberately
**not** awaited before `bootstrap()` returns — unlike
`authRepository.restoreSession()`, which *is* awaited — because a slow or
failed catalog sync must never delay app startup; that would violate the
core offline-first requirement. No connectivity pre-check the way
`SyncTriggers._runIfOnline()` has one: that check exists to avoid repeated
doomed attempts on *frequent* triggers (every connectivity change, every
resume). This runs once, and `ApiClient`'s bounded Dio timeouts (10s
connect / 15s receive) already guarantee it fails within a bounded window
rather than hanging. What this doesn't solve: a fresh install's very first
launch with zero connectivity has nothing cached to fall back on regardless —
a real, separate onboarding-UX gap, not a sync-trigger problem.

## 4. Real mistakes made — don't repeat these

Every one of these actually broke something or would have in production.

1. **Import path depth.** A file in `lib/data/remote/endpoints/` is three
   directories below `lib/`, not two. Verify mechanically:
   ```python
   import re
   from pathlib import Path
   for base in [Path("lib"), Path("test")]:
       for f in base.rglob("*.dart"):
           for line in f.read_text().splitlines():
               m = re.match(r"^\s*import\s+'([^']+)'", line)
               if not m: continue
               target = m.group(1)
               if target.startswith(("package:", "dart:")): continue
               if not (f.parent / target).resolve().exists():
                   print(f"BROKEN: {f}: {target}")
   ```

2. **`SyncStatus` used without `tables.dart` imported.** `database.dart`
   alone isn't enough — `SyncStatus` lives in `tables.dart`. Happened twice
   independently.

3. **A convenience method on the wrong class.** `toCreateDto()`/similar
   belongs on the persisted entity, not its `Draft` — the sync handler only
   ever has the entity, fetched fresh from the database at sync time.

4. **`DateTime` has no const constructor. Ever.** Not a version quirk — a
   permanent Dart SDK decision. `const Foo(someField: DateTime(...))` always
   fails. A same-line grep isn't enough (formatting spans lines); use a
   paren-depth-tracking check instead of a naive regex.

5. **Drift naming collisions — two different kinds, both real:**
   - *Row-class collision*: Drift singularizes a plural table class name for
     its generated row class (`Products` → `Product`), colliding with a
     same-named domain entity. Fix: `@DataClassName('FooRow')` on the table,
     decided *before* writing the repository, not after hitting the error.
   - *Table-class collision* (found this project, not in the original
     playbook): `@DataClassName` only renames the generated **row** class —
     it does nothing for the **table** class itself. `BusinessSettings` (the
     domain entity) and `BusinessSettings` (the Drift `Table` subclass) were
     literally the same name, because "Settings" has no clean singular the
     way `Products`/`Product` does. This only surfaced as
     `flutter analyze`'s `ambiguous_import` the moment one file (the mapper)
     imported both. Fixed by renaming the *domain* entity to `BusinessProfile`
     — matching what the backend actually calls the concept — rather than
     touch the table class and risk guessing wrong about what Drift derives
     a runtime accessor name from.
   - Also don't assume an import you added is *needed* just because a
     sibling file needs the same-looking one: `location_repository_impl.dart`
     and `business_settings_repository_impl.dart` do NOT need
     `package:drift/drift.dart` imported directly (their query-builder
     methods resolve without it), while `product_repository_impl.dart` and
     others genuinely do (they reference `SyncStatus`/use joins directly).
     `flutter analyze` caught both directions of this mistake for real.

6. **A described idempotency mechanism that isn't real.** The architecture
   doc describes retried sale creation getting "rejected with a 409." The
   actual backend (`sale_service.create_sale`) catches the collision
   internally and returns the existing sale with a normal 201. Read the
   actual service function, never just the doc's description of it.

7. **Assumed idempotency that didn't exist.** `Customer`, `Expense`,
   `Income`, and all three stock-movement endpoints had zero protection
   against a retried create/apply until backend work added it
   (`client_reference` column + check-before-insert, migrations
   0012–0015). For stock movements specifically, a retry without this
   silently double-applies a real quantity change — actual inventory
   corruption, not just a duplicate row. Before building a mobile sync
   handler for any entity, check the backend service for this. If it's
   missing, fix the backend first.

8. **Wrong assumptions about data-model shape, from inferring instead of
   reading the primary doc directly.** `Expense`/`Income`'s `locationId` was
   made nullable on the reasoning "the backend has no `location_id` column,
   so the mobile field shouldn't be required either" — a non sequitur.
   Architecture Section 7a's own table says these are location-scoped,
   "confirmed, not inferred," required not nullable — the backend gap
   changes what's *sent*, not what's *required locally*. The opposite
   mistake happened with `StockMovement`'s `transfer` type: correctly
   verifying it doesn't exist on the backend, then wrongly concluding it was
   a documentation error and scrubbing it from the mobile schema — when both
   primary docs actually describe it as real, deliberately-deferred Phase 2
   work. **"I checked the backend and didn't find X" only proves X isn't
   built yet — it doesn't tell you whether X was ever supposed to exist.**
   Whether a comment says "verified directly against Section 7a" or not,
   that's a claim about a check someone did, not a substitute for doing it
   yourself — both mistakes above were made by trusting an earlier file's
   paraphrase of the architecture doc instead of reading Section 7a's own
   table, which settles nearly every location-scoping question in about
   thirty seconds of actual reading.

9. **A backend model silently out of sync with its own migration.**
   Migration `0011_approval_pin` added `approval_pin_hash`/
   `approval_pin_salt` to the `users` table — verified directly against the
   real `.db` file, the columns are genuinely there. But `app/models/user.py`
   was never updated to declare them as `Mapped` columns. The write side
   (`user.approval_pin_hash = pin_hash`) didn't even raise an error — it
   silently set an untracked Python attribute SQLAlchemy never persisted, so
   the endpoint returned a normal 204 while writing nothing. The read side
   (a class-level `.filter()` query) crashed outright with `AttributeError`.
   Only surfaced by an actual `pytest` run — never visible from reading the
   migration or the model file in isolation, only from checking that they
   still agree with each other.

10. **A backend schema change on one side of the stack without checking every
    caller on the other side.** Making `location_id` required on the backend
    (`SaleCreate`/`ExpenseCreate`/`IncomeCreate`) is only half the fix.
    `SaleCreateDto`/`ExpenseCreateDto`/`IncomeCreateDto` on mobile all had
    doc comments explicitly saying "deliberately does NOT send locationId" —
    accurate when written, silently wrong the moment the backend schema
    changed, and never revisited. Every sale, expense, and income creation
    from mobile would have gotten a 422, including through `Sale`, the most
    mature part of the app. Compounding near-miss: even the Pydantic schema
    side wasn't fully done in one pass — `Expense`/`Income`'s **models**
    gained `location_id` before the **schemas** did, which would have made
    every creation crash with a `NOT NULL` violation regardless of what
    mobile sent. A schema/model/DTO/wire-format change on any one layer is
    incomplete until every other layer that touches it is re-checked, not
    just the layer you were actually working on. Concretely: **grep for every
    construction site**, in both `lib/` and `test/`, of anything whose
    constructor signature changed — not just the "main" one. Existing test
    fixtures (`registerFallbackValue`, hand-built fixture objects) are
    exactly the kind of call site this misses if you only check production
    code paths.

11. **Tests that pass without covering the thing that actually broke.**
    The existing sync-handler tests for Expense/Income already captured the
    outgoing DTO and asserted on fields like `description`/`clientReference`
    — but never `locationId`, which is exactly the field that was silently
    missing. A green test suite that never asserts on the field in question
    provides no protection against that field's regression. Added
    `expect(dto.locationId, ...)` to every affected test once the bug above
    was found, specifically so this can't silently reappear.

12. **A stale comment is a live bug, not a documentation nit.** Found
    repeatedly, in both directions — comments describing a backend gap that
    had since been closed (`auth_repository.dart` claiming the approval-PIN
    endpoint "doesn't exist yet," long after it had been built and wired),
    and comments describing intended behavior that the actual, later-settled
    interface no longer matched (`tables.dart` describing a
    `getOrCreate()`/`update()` repository shape for `BusinessSettings` that
    was simplified to `watchSettings()`/`syncFromServer()` and never updated
    to say so). A comment that was accurate when written is not the same
    claim as a comment that's accurate now — check the thing it describes
    still matches, don't just trust that it once did.

13. **SQLite migration incompatibilities**, found only by actually applying
    the migration (against a real or scratch copy of the `.db` file — not by
    reading it and assuming it's fine): a bare `ALTER TABLE ADD CONSTRAINT`
    right after `CREATE TABLE` in the same migration (SQLite has no such
    `ALTER TABLE` support at all — inline the constraint into `CREATE TABLE`
    instead), and an unnamed inline foreign key inside `batch_alter_table`
    (SQLite's batch-mode rebuild requires every constraint to have an
    explicit name). If you add a migration with a constraint or FK, name it
    explicitly, always — don't rely on implicit naming.

14. **Only ever as good as which snapshot you're actually looking at.**
    Mid-engagement, a "verify against the backend" check turned up zero
    `client_reference` support anywhere — which looked like mistake #7
    happening again, except the real current backend had it correctly, on
    every entity. The check had run against a *stale* backend copy, handed
    over before the relevant migrations existed. Before concluding an
    earlier claim was wrong, check the snapshot's own recency signals first
    (`alembic/versions/` listing, `git log`, file mtimes) — `diff -rq`
    between two snapshots is fast and conclusive when in doubt.

## 5. The established pattern for a new entity

**Write-capable (push-sync)** — read `Customer` or `IncomeRecord` first, the
cleanest examples (`Sale`'s has extra complications; `StockMovement`'s is a
deliberate deviation, not a template):

1. Verify the real backend shape first: `app/schemas/<resource>.py`,
   `app/routers/<resource>.py`, `app/services/<resource>_service.py` — does
   it already have `client_reference` idempotency? If not, fix the backend
   first (migration + model + schema + service check + tests).
2. `domain/entities/<entity>.dart` — plain type + `<Entity>Draft` + wire DTOs.
   Zero Flutter/Drift imports. `toCreateDto()` lives on the entity, not the
   Draft.
3. `domain/repositories/<entity>_repository.dart` — abstract interface.
4. `data/repositories/<entity>_mapper.dart` — Drift Companion/row mapping.
5. `data/repositories/<entity>_repository_impl.dart` — local-write-first,
   ULID id, enqueue a `SyncTask`, never awaits the network.
6. `data/remote/endpoints/<entity>s_api.dart` — Dio client. If the backend
   endpoint is genuinely idempotent, no client-side special-casing needed.
7. `sync/handlers/<entity>_sync_handler.dart` — fetch by local id, convert,
   call the API, `markSynced()`.
8. Wire into `providers.dart` + `bootstrap.dart` (construct, register in
   `SyncEngine`'s handler map).
9. Tests: real in-memory Drift for the repository, mocktail for the API
   client in the sync handler (the one real network boundary).

**Read-only (pull-sync)** — read `Location` or `Product` as the concrete
reference. No `Draft`, no `SyncTask`/`SyncHandler`. Just a
`syncFromServer()` that pulls the current set and reconciles locally, using
`insertOnConflictUpdate` rather than `insertOrReplace` — the latter deletes
then reinserts under the hood, which risks disturbing any foreign keys
pointing at the replaced row during something as routine as a re-sync.

**When the pattern genuinely doesn't fit** — `StockMovement` as the worked
example (three write methods, `markSettled` not `markSynced`, two mutually
exclusive quantity fields). Change the shape and write down why in the code
itself, rather than forcing a fit that isn't real.

## 6. Confirmed backend/architecture-doc discrepancies

| Claim | Reality |
|---|---|
| Retried sale creation gets a 409 the client must handle | `sale_service.create_sale` returns the existing sale with a normal 201 |
| `GET /api/auth/business/{id}/approval-hashes` (business-scoped) | Backend is single-business — real endpoint is `GET /api/auth/approval-hashes` |
| The backend has zero location infrastructure at all | True until this project built it — `Locations` table, `location_id` on `Sale`/`Expense`/`Income`/`StockMovement`/`Shift`, and `GET /api/locations` all added this engagement (migrations 0016–0022) |
| A prior handoff document's own discrepancy table asserted `Sale` already had `location_id` on the backend | False — verified directly against `app/models/sale.py`; it had none until migration 0017 |
| `ExpenseCategory` is location-scoped, per Section 7a's table listing it alongside `Expense`/`Income` | Section 7a's own worked example, and the Product Design Bible's concrete category list (Rent/Utilities/Transport/Wages/Other), both describe a shared, business-wide list — not one instantiated per location. Judgment call: `ExpenseCategory` did NOT get `location_id`; only `Expense`/`Income` themselves did |
| Mobile `BusinessSettings` mirrors the backend's full profile | Backend's `BusinessProfile` also has `address`/`phone`/`email`/`tin` — mobile schema was missing all four (now fixed) |
| Migration `0011_approval_pin` fully wired approval-PIN support | The DB columns existed; the SQLAlchemy `User` model was never updated to declare them — writes silently no-op'd, reads crashed (now fixed) |

Removed from this table: "stock movements have a `transfer` type" was once
listed as a discrepancy and scrubbed from the mobile schema on that basis.
It isn't one — see mistake #8 above.

## 7. What's still open (Phase 1+)

- **No screen actually calls `syncFromServer()`.** Decided the trigger
  mechanism (Section 3a); still no manual "Sync Now," no pull-to-refresh —
  there's no screen to put one on yet.
- **`Product.current_stock` stays a single global column**, not
  per-location. Architecture Section 7a itself calls this "a real,
  non-trivial schema change" — it would mean rewriting
  `sale_service.create_sale`'s atomic stock-deduction UPDATE and
  `inventory_service`'s stock-in/out/adjust, and breaking the wire format
  the mobile `Product`/`StockMovement` sync already depends on. Deliberately
  scoped out, not an oversight.
- **`StockMovementType.transfer`** — real, deliberately deferred. No backend
  endpoint exists; Product Design Bible Volume 6 (Decision 21) and
  Architecture Section 14 both sequence this into Phase 2, gated on a second
  location genuinely existing. Don't start before both the backend endpoint
  exists and a second location is a real, reachable scenario.
- **Push-based remote approval** (the PIN system's second half, for when the
  approver isn't physically present) — blocked on external infrastructure (a
  real Firebase project, APNs certs), not buildable by writing more code.
- **Every feature screen** — Sell, Stock, Money, More are honest placeholders
  behind a real router. This is most of Phase 1.
- **The real exit criterion** — see Status, above. Nothing here substitutes
  for it.

## 8. Quick reference — running things

Backend:

```bash
cd bms/backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp ../.env.example .env   # fill in SECRET_KEY at minimum: openssl rand -hex 32
alembic upgrade head
uvicorn app.main:app --reload
```

Backend tests: `cd bms/backend && pytest`

Mobile:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generates *.g.dart
flutter analyze --fatal-infos
flutter test test/repository test/sync
```

Point the app at your backend via `--dart-define=API_BASE_URL=...` (see
`lib/core/config/env_config.dart`) — the default, `http://10.0.2.2:8000`, is
the Android emulator's alias for host localhost.

A real Android scaffold now exists (`android/`) and CI includes an APK build
step — `flutter build apk` is a real, running check now, not a skipped one.
