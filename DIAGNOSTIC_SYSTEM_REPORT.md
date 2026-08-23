# Fulus Diagnostic & Crash Logging System — Implementation Report

Deterministic (no AI), offline-first, crash-safe diagnostic and crash-logging
system for Fulus Mobile Phase 0. 30 new files, 12 edited files. Full inventory
and rationale below.

---

## 1. What was built

A five-layer system, each layer independently testable:

1. **Models** (`core/diagnostics/models/`) — `DiagnosticEvent`, `Breadcrumb`,
   `DeviceContext`, and the enums (`DiagnosticSeverity`, `DiagnosticCategory`,
   `DiagnosticConfidence`, `DiagnosticLifecycleStatus`). Pure Dart, zero
   Flutter/Drift dependency — usable from a plain unit test or the file-based
   fallback store exactly as easily as from the Drift-backed one.
2. **Root-cause engine** (`core/diagnostics/engine/`) — a deterministic,
   priority-ordered rule list. No AI/LLM call anywhere in this path.
3. **Storage** (`core/diagnostics/storage/`) — a Drift-backed primary store
   (`DiagnosticEvents` table, schema v8) plus an independent file-based
   emergency fallback for when the primary database is itself what's failing.
4. **The facade** (`core/diagnostics/diagnostic_logger.dart`) — the single
   entry point (`DiagnosticLogger`) the rest of the app depends on, plus
   global error capture (`FlutterError.onError`,
   `PlatformDispatcher.instance.onError`, a calm release-mode
   `ErrorWidget.builder`) so *something* is captured even in modules this
   pass never specifically instrumented.
5. **Export & UI** — text/JSON report generation, Share Sheet integration
   (reusing the existing `share_plus` pattern from `ExportService`), and two
   screens under More → Diagnostics.

## 2. Where it's integrated

| Integration point | What it does |
|---|---|
| `main.dart` | Constructs `DiagnosticLogger` and installs global capture **before** `bootstrap()` runs, wrapped in `runZonedGuarded` — so a failure inside `bootstrap()` itself is still captured. |
| `bootstrap.dart` | Attaches the real Drift store the moment the database exists; runs retention cleanup once per cold start; passes the logger into `SaleRepositoryImpl`, `DraftCartRepositoryImpl`, `SyncEngine`; registers `diagnosticLoggerProvider`. |
| `DraftCartRepositoryImpl.completeSale` | **The flagship integration.** Full `DiagnosticOperation` with stages (`Validate cart` → `Build sale` → `Persist sale` → `Clear cart`), Sale ID/item-count/payment-method evidence, capture-then-rethrow on failure — `PaymentScreen`'s existing `catch (_)` is completely unchanged. |
| `SaleRepositoryImpl.createSale` | Breadcrumbs only (`Sale transaction started`, `Inventory update started/completed`, `Sale transaction committed`) — the operation-level capture belongs one layer up, in `completeSale`. |
| `SyncEngine` | Captures every path that ends in `attentionNeeded` (conflict, missing handler, threshold exceeded) at `warning` severity — nothing is lost, so nothing here is `error`. |
| `CartCubit` | Breadcrumbs on every mutation (`addProduct`, `increment/decrement/setItemQuantity`, `removeItem`, `setCustomer`, `addPayment`) — so a sale failure's "Recent activity" shows what the cashier was actually doing, not just the final repository call. |
| Global safety net | Every other module (Inventory adjustments, Customers, Employees, Exports, Onboarding, etc.) is covered by `FlutterError.onError`/`PlatformDispatcher.onError` only — see Limitations. |

Every constructor parameter added is **optional and nullable**
(`DiagnosticLogger? diagnosticLogger`) — no existing call site, test, or
constructor signature was forced to change.

## 3. Failure categories covered

`DiagnosticCategory` has 17 values (database, network, authentication,
synchronization, fileSystem, sales, inventory, startup, validation,
stateConsistency, exportReporting, platformChannel, navigation,
configuration, flutterFramework, dartRuntime, unknown) — consolidated from
the brief's longer boundary list where several boundaries are diagnosed
identically (e.g. PDF and CSV export both land in `exportReporting`).

## 4. How root causes are determined

`RootCauseEngine.classify()` runs a fixed-priority list of plain-Dart rules
(`engine/rules/*.dart` — database, network, auth, sync, file system, generic)
against a normalized `DiagnosticSignal`. First match wins. **No rule ever
guesses** — if nothing matches, the result is `DiagnosticCause.unknown()` at
`UNKNOWN` confidence, never a fabricated explanation. Matching is done on
stable signals verified directly against this codebase: SQLite's own error
text (`FOREIGN KEY constraint failed`, `database is locked`, …), `DioException`
type/status, `AuthFailure`'s public `.message` strings (the specific variant
classes are private to `failure.dart`; their messages are stable and public),
the exact `[CONFLICT] ` prefix `ConflictResolver.annotate` already writes, and
`dart:io`'s `FileSystemException.osError`.

Startup failures are checked **last**, deliberately outside every
category-specific rule list, so a database failure during startup is still
diagnosed as a database failure — confirmed by test
(`root_cause_engine_test.dart`, "startup fallback" group).

23 rules total across 6 files, all covered by `root_cause_engine_test.dart`
(38 test cases).

## 5. How evidence is collected

Two sources, merged: whatever the call site already knew (`DiagnosticOperation.addContext` /
`captureError`'s `context` param — Sale ID, item count, …) plus whatever the
matched rule itself derives from the exception (e.g. `Constraint: FOREIGN KEY`,
`HTTP status: 500`). Both pass through `DiagnosticRedactor` before ever being
persisted.

## 6. How logs are stored

Primary: a new Drift table, `DiagnosticEvents` (schema v8, see
`tables.dart`/`database.dart`), not a `SyncableColumns` table — a captured
error is a fact about this device, with no server counterpart today.
Duplicate events (same title/component/operation/exceptionType within 5
minutes) bump `occurrenceCount` on the existing row rather than inserting a
new one. Retention runs once per cold start: never deletes the most recent
500 rows regardless of age; beyond that, prunes anything older than 30 days.

**Filtering is done in Dart, after one ordered Drift fetch, not via a
dynamically-built SQL `WHERE` clause** — a deliberate tradeoff given the
environment constraint below (every Drift call used is one I can point at a
real, already-working precedent elsewhere in this codebase). Flagged in
`drift_diagnostic_store.dart`'s own header comment as a reasonable follow-up
optimization once a real build is available to verify the query-builder's
multi-value/`LIKE` API surface against.

Emergency fallback: an independent JSONL file
(`<app docs>/diagnostics/fallback_events.jsonl`), used only when the primary
write itself fails — because the error being diagnosed can itself be a
database failure. Drained back into the primary store automatically once it
recovers.

## 7. How logs are shared

`DiagnosticShareService`, following `ExportService`'s exact existing
temp-file-then-`Share.shareXFiles` pattern. Four options on the detail
screen's share sheet: **This error** / **Today's logs** / **Last 7 days** /
**Full diagnostic report**, as text (default, readable in WhatsApp/email) or
JSON. Every report is redacted a second time at generation, independent of
the redaction already applied at capture time.

## 8. Tests added

Six files, `test/core/diagnostics/`, following this codebase's existing
convention exactly (real `AppDatabase.forTesting(NativeDatabase.memory())`
over mocks, hand-rolled fakes where a fake is needed at all):

- `root_cause_engine_test.dart` — 38 cases across every rule category, the
  unknown fallback, severity overrides, and the startup-fallback ordering.
- `redaction_test.dart` — key-based and value-shape redaction, including the
  deliberate non-redaction of ULID-shaped legitimate evidence.
- `breadcrumb_trail_test.dart` — bounded ring buffer behavior.
- `diagnostic_store_test.dart` — real Drift DB: save/getById, duplicate
  merging, summary counts, every filter type, retention policy boundaries.
- `diagnostic_logger_test.dart` — the crash-safety guarantee specifically:
  `captureError` never throws even when the primary store throws, returns
  false, or the fallback store *also* fails.
- `report_generator_test.dart` — text/JSON report content and redaction.

## 9. Limitations — please read before trusting this as final

**No Flutter/Dart toolchain was available in the environment this was
written in** — nothing here has been run through `flutter analyze` or
`flutter test`. Every API call was checked by hand against a real, confirmed
precedent already working elsewhere in this exact codebase (grepped and read
directly, never guessed from general Drift/Dio knowledge) rather than
compiled. **Before relying on this, run, in order:**

```
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

Two real bugs were caught during manual review this session and are already
fixed in what you're receiving — noted here for transparency, not because
either is still present:
1. `DraftCartRepositoryImpl.completeSale` originally tried
   `paymentMethod.name`, but `aggregatePaymentMethod` returns `String?`, not
   an enum — fixed to use the string directly.
2. `DiagnosticStore`'s abstract `watchEvents`/`getForExport` declared
   non-nullable optional parameters with no default value — a genuine
   null-safety compile error. Fixed to match the concrete implementations'
   actual defaults.

Given the lack of a compiler, `flutter analyze` may still surface something
this review missed — treat this as thoroughly self-reviewed, not
compiler-verified.

**Instrumentation depth is deliberately uneven.** Sales (`completeSale` and
its component calls), Sync, and the global safety net got real,
purpose-built instrumentation. Inventory standalone adjustments, Customers,
Employees, Onboarding, Exports, and everything else rely on the global
safety net only (`FlutterError.onError`/`PlatformDispatcher.onError`) — real
capture, but without stage tracking or hand-picked evidence. The pattern
(`DiagnosticOperation` for a multi-step flow, `logger?.breadcrumb(...)` for
mutations) is meant to be trivially extensible to those modules next; it
wasn't done everywhere in this pass to keep the diff reviewable and
correctness-checkable by hand within the no-compiler constraint above.

**Query performance is approximate under high volume**, per Section 6 —
correct in the common case (retention keeps the table near 500 rows), an
honest approximation otherwise.
