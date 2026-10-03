# Part 19 — Errors, Diagnostics & Observability

## Scope
This pass audits exception capture, diagnostic persistence, fallback storage, redaction, user-facing sync errors, remote diagnostic upload, lifecycle capture, and diagnostic read APIs.

## Baseline
- Part 19 work started from the Part 18 audit branch after the current main baseline was inspected.
- Relevant areas: `lib/core/diagnostics/**`, `lib/data/remote/fulus_diagnostic_uploader.dart`, `lib/sync/sync_user_message.dart`, `lib/main.dart`, `supabase/functions/fulus-diagnostics/index.ts`, and diagnostic tests.

## Pass A — Structural inventory

### Capture
- `DiagnosticLogger` is the central capture facade.
- `global_error_capture.dart` installs process-wide Flutter error hooks and release error-widget handling.
- `current_screen_tracker.dart` supplies navigation context.
- `BreadcrumbTrail` and `DiagnosticOperation` provide bounded operation history and failure-stage context.

### Storage
- `DriftDiagnosticStore` persists diagnostic events in the existing local Drift database.
- `FallbackDiagnosticStore` provides file-backed JSONL buffering when the primary store is unavailable.
- The logger drains fallback entries after the primary store is attached.

### Safety
- `DiagnosticRedactor` applies key-name and secret-shape redaction before persistence and export.
- Stack traces and event fields have bounded sizes.
- Normal user-facing sync errors are converted by `syncUserMessage` rather than exposing transport/database terminology.

### Remote observability
- `FulusDiagnosticUploader` is best-effort and never participates in the business operation's success path.
- `fulus-diagnostics` requires a bearer session, verifies business membership when a business is supplied, optionally verifies the registered device, bounds event size, and upserts by event ID.

## Pass B — Function/class audit

### DiagnosticLogger
The capture path is defensive: classification, event construction, redaction, persistence, and fallback are inside the capture guard. Startup can capture before Drift exists because the fallback store is independent.

### DriftDiagnosticStore
Persistence returns false instead of throwing, allowing the logger to fall back. Duplicate events within five minutes are coalesced by title/component/operation/exception type. Retention is bounded by a minimum recent-row floor.

### FallbackDiagnosticStore
Writes are bounded and JSONL-based. A malformed line does not prevent other entries from being recovered.

### DiagnosticRedactor
Sensitive key names are replaced and JWT/Bearer-shaped values are redacted. Export applies a second defensive redaction pass.

### FulusDiagnosticUploader
Upload is authenticated, membership/device checked server-side, size bounded, and idempotent by event ID. The local diagnostic store remains authoritative when remote upload fails.

## Concrete finding

### P19-001 — Medium — DiagnosticLogger read facade could throw

**Observed behavior:** The logger's documented non-throwing contract covered capture/breadcrumb paths, but several public read/maintenance methods directly delegated to the attached `DiagnosticStore`. A custom or future store implementation that throws could therefore propagate through `getById`, `getSummary`, `getForExport`, `markViewed`, retention, deletion, or the diagnostic event stream.

**Expected invariant:** Diagnostic failures must never become application failures. The logger facade should provide safe results even when its backing store is unavailable or malformed.

**Root cause:** Capture/persistence paths had defensive boundaries, while the read passthroughs relied on the current Drift implementation's own defensive behavior instead of enforcing the facade's contract.

**Fix:** Guard all public read/maintenance methods. Convert failures to safe empty/null/no-op results. Wrap the event stream in an async generator that yields an empty list if the backing stream cannot be created.

**Regression:** Added a throwing-store test covering all read/maintenance methods and the event stream.

**Cross-check:** Capture, breadcrumb, fallback, redaction, remote upload, and user-facing sync-error paths were reviewed; no second instance of the same unguarded facade boundary was found.

## Pass C — Line/branch audit

### Failure containment
- Primary local write failure falls back to file storage.
- Fallback failure reaches only a last-resort diagnostic print.
- Remote upload failure is swallowed.
- Diagnostic maintenance failure is now swallowed at the logger facade.

### Sensitive data
Redaction occurs before local persistence and again during export. Remote upload receives the already-redacted event.

### User-facing error language
Sync infrastructure details are intentionally converted to calm business-language messages. This keeps diagnostic detail available to diagnostics while avoiding technical leakage in normal workflows.

### Remote trust boundary
The Edge Function authenticates the caller. Business-scoped events require active membership. Device-scoped events additionally require an active device registered by that user for that business.

## Pass D — Cross-system audit

```
Flutter/Dart failure
  → global capture / operation instrumentation
  → DiagnosticLogger
  → redaction
  → Drift store
      ↘ fallback file if unavailable
  → local diagnostic UI/export
  → best-effort remote uploader
  → authenticated fulus-diagnostics Edge Function
  → diagnostic_events
```

The business operation is not dependent on any downstream diagnostic stage.

## Remaining evidence

### P19-RUNTIME-001 — Runtime evidence
A real Android failure-injection run is still required to prove global Flutter capture, process-startup capture, fallback-file recovery, and remote upload behavior on a physical/emulated runtime. Source/tests provide strong structural evidence but do not substitute for device execution.

### P19-PROD-001 — Production evidence
The diagnostic Edge Function's live authorization/device-registration behavior should be exercised with an authenticated member, non-member, wrong device, and missing-business diagnostic event before final production-hardening closure.

## Conclusion

The concrete logger-facade failure boundary was fixed conservatively with regression coverage. Remaining Part 19 uncertainty is runtime/production evidence rather than an unproven source rewrite.
