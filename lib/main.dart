import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/diagnostics/capture/global_error_capture.dart';
import 'core/diagnostics/diagnostic_logger.dart';
import 'core/diagnostics/models/diagnostic_enums.dart';

/// Entry point. Deliberately thin — every real decision (DB open order,
/// DI wiring, WorkManager registration) lives in bootstrap.dart per
/// Architecture Section 1's stated split between main.dart and
/// app/bootstrap.dart, so this file never grows into a dumping ground as
/// more init steps are added over time.
///
/// The one exception is diagnostics setup, added here rather than in
/// bootstrap.dart on purpose: `diagnosticLogger` and
/// `installGlobalErrorCapture` are constructed/installed before
/// `bootstrap()` is even called, specifically so a failure *inside*
/// bootstrap() itself — opening the database, loading SyncConfig, any
/// of it — is still captured rather than being invisible to the one
/// system meant to explain what went wrong. `diagnosticLogger`'s
/// constructor takes no required dependencies for exactly this reason
/// (see DiagnosticLogger's own header comment): it's ready to catch
/// something before the database it will eventually persist into even
/// exists, buffering to the file-based fallback store in the meantime
/// and draining that once bootstrap() attaches the real one.
///
/// Wrapped in `runZonedGuarded` as well as the two handlers
/// `installGlobalErrorCapture` itself installs
/// (`FlutterError.onError`/`PlatformDispatcher.instance.onError`) —
/// belt and suspenders: the zone guard is the one mechanism that can
/// still catch an async error that somehow occurs outside the Flutter
/// framework's own error zone (before `runApp`, in particular).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final diagnosticLogger = DiagnosticLogger();
  installGlobalErrorCapture(diagnosticLogger);
  // Not awaited: resolving app version/device info crosses a platform
  // channel, and nothing on the critical startup path needs it —
  // DeviceContextProvider itself explains why an event captured before
  // this resolves simply gets DeviceContext.unknown() rather than
  // blocking on it.
  unawaited(diagnosticLogger.resolveDeviceContext());

  runZonedGuarded(
    () async {
      // bootstrap() opens the Drift database and initializes secure
      // storage and the API client — all BEFORE the widget tree is
      // built, per Architecture Section 12's launch-time requirement:
      // nothing on the splash screen should be waiting on a network
      // call, but the local database genuinely does need to be open
      // before the first screen can read from it. bootstrap() opens the
      // DB asynchronously and returns the container with it already
      // wired in, rather than the first screen discovering a null
      // database reference.
      //
      // WorkManager background-sync registration (Architecture Section
      // 8) is NOT part of bootstrap() yet — that's real, undone work
      // belonging to the sync engine, which doesn't exist in this
      // phase. An earlier draft of this comment claimed it was already
      // handled here; it wasn't, and the comment was corrected to stop
      // overstating what the code actually does.
      final container = await bootstrap(diagnosticLogger: diagnosticLogger);

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const FulusApp(),
        ),
      );
    },
    (error, stack) {
      // Reached only for an error escaping the zone above outside
      // Flutter's own build/frame lifecycle (installGlobalErrorCapture
      // already covers that far more common case) — most plausibly a
      // synchronous throw during the `bootstrap()` call itself. Fatal
      // either way (the app never reaches runApp), so severity is
      // critical regardless of what PlatformDispatcher.onError would
      // otherwise have used for an ordinary in-session error.
      unawaited(
        diagnosticLogger.captureError(
          error: error,
          stackTrace: stack,
          severity: DiagnosticSeverity.critical,
          category: DiagnosticCategory.startup,
          title: 'Fulus failed to start',
        ),
      );
    },
  );
}
