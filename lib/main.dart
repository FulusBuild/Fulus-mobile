import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'app/providers.dart';
import 'core/diagnostics/capture/global_error_capture.dart';
import 'core/diagnostics/diagnostic_logger.dart';
import 'core/diagnostics/models/diagnostic_enums.dart';
import 'core/theme/device_form_factor.dart';
import 'data/remote/fulus_diagnostic_uploader.dart';

Future<void> main() async {
  final diagnosticLogger = DiagnosticLogger();

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final logicalSize = view.physicalSize / view.devicePixelRatio;
      final isTablet = logicalSize.shortestSide >= kTabletBreakpoint;
      if (!isTablet) {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }

      installGlobalErrorCapture(diagnosticLogger);
      unawaited(diagnosticLogger.resolveDeviceContext());

      final container = await bootstrap(diagnosticLogger: diagnosticLogger);

      // Remote diagnostics starts only after the existing bootstrap has
      // created the authenticated ApiClient and cloud connection state.
      // It reads the existing on-device diagnostic store, so failures from
      // startup, onboarding, restore, sync, database and Flutter itself are
      // uploaded automatically once a valid session is available.
      final diagnosticUploader = FulusDiagnosticUploader(
        logger: diagnosticLogger,
        apiClient: container.read(apiClientProvider),
        connection: container.read(fulusConnectionStateProvider),
      );
      diagnosticUploader.start();

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const FulusApp(),
        ),
      );
    },
    (error, stack) {
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
