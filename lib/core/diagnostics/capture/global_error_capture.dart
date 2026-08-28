import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../diagnostic_logger.dart';
import '../models/diagnostic_enums.dart';

/// Installs the two process-wide error hooks Flutter offers, plus a
/// calm release-mode fallback for [ErrorWidget.builder] — together,
/// this is the safety net that guarantees *something* is captured for
/// literally any exception anywhere in the app, even in a module this
/// implementation pass never specifically instrumented (see the
/// implementation report's own "coverage" section). What it captures
/// won't have the fine-grained stage/evidence a purpose-built
/// [DiagnosticOperation] gives — see that class's own header comment —
/// but it will never be nothing.
///
/// Call once, from main.dart, before `bootstrap()` runs — installing
/// this is what makes startup/initialization failures (diagnostic
/// system brief, Section 2) genuinely capturable rather than an
/// aspiration: [logger] itself has no dependency on the database or
/// anything else bootstrap() sets up (its constructor is all optional
/// parameters with safe defaults), so it's ready to catch a failure in
/// bootstrap() itself, before the database is even open — those events
/// simply queue in the file-based fallback store until bootstrap()
/// finishes and attaches the real one.
void installGlobalErrorCapture(DiagnosticLogger logger) {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    unawaited(
      logger.captureError(
        error: details.exception,
        stackTrace: details.stack ?? StackTrace.current,
        severity: DiagnosticSeverity.critical,
        category: DiagnosticCategory.flutterFramework,
        component: details.library ?? 'Flutter framework',
        title: 'Display error',
        context: {
          if (details.context != null) 'Context': details.context.toString(),
          // FIX (Sell-screen crash investigation): Flutter already
          // computes "the relevant error-causing widget was: X, created
          // by file:line" for exactly the error types we couldn't
          // localize (RenderFlex overflow, "RenderBox was not laid
          // out") — it lives in FlutterErrorDetails.informationCollector,
          // which this handler was dropping entirely. Several assertion
          // types (BuildScope/InheritedElement/etc.) fire deep in
          // framework traversal code with zero app frames in the stack
          // itself; informationCollector is often the only place an app
          // file:line shows up at all for those. Most FlutterErrorDetails
          // (anything reported via a plain `throw`) have no
          // informationCollector and this stays absent, same as before.
          if (_collectWidgetInfo(details) case final info?) 'Widget details': info,
        },
      ),
    );
    // Preserves whatever Flutter's own default behavior was (console
    // dump in debug, silent in release) — this function adds capture,
    // it does not take over error presentation.
    if (defaultOnError != null) {
      defaultOnError(details);
    }
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(
      logger.captureError(
        error: error,
        stackTrace: stack,
        severity: DiagnosticSeverity.error,
        category: DiagnosticCategory.dartRuntime,
        title: 'Unexpected error',
      ),
    );
    // `true` = handled; Flutter should not additionally treat this as
    // fatal. An error that reached here already escaped every other
    // handler in the app, but the app itself is still running and
    // should keep doing so.
    return true;
  };

  if (kReleaseMode) {
    ErrorWidget.builder = _releaseModeErrorBuilder;
  }
  // In debug/profile builds, ErrorWidget.builder is deliberately left
  // at its Flutter default (the familiar red screen) — a developer
  // running the app locally wants the raw error, not the same calm
  // fallback a cashier would see.
}

/// See the doc comment above the `'Widget details'` context entry in
/// [installGlobalErrorCapture] for why this exists. Returns null for
/// the (common) case where Flutter didn't attach an
/// [FlutterErrorDetails.informationCollector] at all — most exceptions
/// don't have one; it's specific to a handful of framework-detected
/// conditions like layout overflow.
String? _collectWidgetInfo(FlutterErrorDetails details) {
  final collector = details.informationCollector;
  if (collector == null) return null;
  final nodes = collector().toList();
  if (nodes.isEmpty) return null;
  return nodes.map((node) => node.toStringDeep()).join('\n').trim();
}

/// A calm, on-brand fallback shown instead of the red screen of death
/// when a widget fails to build in a release build — brief Section 16's
/// "do not expose raw exceptions to ordinary users", applied to the one
/// error surface (`ErrorWidget.builder`) that both hooks above cannot
/// reach on their own, since a build-time widget error is what those
/// hooks are themselves reporting *around*, not a screen they replace.
///
/// Deliberately built from plain Material widgets rather than this
/// app's own FulusScreen/FulusButton component library: this is the
/// fallback shown when something has already gone wrong inside the
/// widget tree, so it intentionally takes on the fewest possible
/// dependencies that could also fail.
Widget _releaseModeErrorBuilder(FlutterErrorDetails details) {
  return Material(
    color: Colors.white,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text(
              'Something went wrong on this screen.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Details were saved to Diagnostics in More.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    ),
  );
}
