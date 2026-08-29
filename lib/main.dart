import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// `diagnosticLogger` itself is built here, outside `runZonedGuarded` —
/// its constructor makes no Flutter/platform-channel call (see its own
/// header comment), so it doesn't need a zone or a binding to exist yet,
/// and building it out here is what keeps it reachable from the zone's
/// error callback below, which is a sibling closure to the zone body,
/// not nested inside it.
///
/// `WidgetsFlutterBinding.ensureInitialized()` itself, though, MUST be
/// the first statement *inside* the `runZonedGuarded` body, in the same
/// zone as `runApp()` — this is a hard Flutter framework requirement
/// (see docs.flutter.dev/release/breaking-changes/zone-errors), not a
/// style preference. Flutter's binding pins itself to whichever zone it
/// was initialized in, and asserts on every subsequent framework entry
/// point (`runApp` among them) that the calling zone still matches. A
/// version of this file that initialized the binding *outside*
/// `runZonedGuarded` while calling `runApp` *inside* it — which an
/// earlier draft of this file did — throws a "Zone mismatch"
/// `FlutterError` on the very first frame, and Flutter's own
/// build/dirty-tracking/dispose machinery keeps running in a
/// zone-inconsistent state afterward: exactly the class of cascading
/// assertion this file's own diagnostic system caught downstream of it
/// (RenderBox sizing, InheritedElement dependents, dirty widget in the
/// wrong build scope) the first time this ran on a real device.
Future<void> main() async {
  final diagnosticLogger = DiagnosticLogger();

  runZonedGuarded(
    () async {
      // Must be the first line in this closure — see this function's
      // own header comment on why binding init and runApp() being in
      // the same zone is a hard requirement, not incidental ordering.
      WidgetsFlutterBinding.ensureInitialized();

      // Phones lock to portrait (rotating the phone shouldn't flip the
      // whole UI to landscape — bug report); tablets don't, deliberately
      // — Fulus's stated direction is the same app working properly on
      // iPad later, and a blanket portrait lock here would foreclose
      // that before it's even built. WidgetsBinding.platformDispatcher
      // is available this early (no widget tree/context needed yet);
      // 600 logical pixels on the shortest side is the standard
      // Material breakpoint this app's own responsive code should
      // eventually match, so tablet detection stays consistent as that
      // work happens rather than drifting from a second, differently-
      // tuned threshold picked here in isolation.
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final logicalSize = view.physicalSize / view.devicePixelRatio;
      final isTablet = logicalSize.shortestSide >= 600;
      if (!isTablet) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }

      installGlobalErrorCapture(diagnosticLogger);
      // Not awaited: resolving app version/device info crosses a
      // platform channel, and nothing on the critical startup path
      // needs it — DeviceContextProvider itself explains why an event
      // captured before this resolves simply gets
      // DeviceContext.unknown() rather than blocking on it. Placed
      // after ensureInitialized() deliberately: the platform channel
      // this makes could not be serviced before the binding — and the
      // channel machinery it registers — exist.
      unawaited(diagnosticLogger.resolveDeviceContext());

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
