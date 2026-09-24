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
import 'sync/background_sync.dart';

Future<void> main() async {
  final diagnosticLogger = DiagnosticLogger();

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // WorkManager is the OS-level safety net for Cloud Sync when Android
      // suspends or terminates the Flutter process. Foreground SyncTriggers
      // remains responsible for responsive sync while the app is running.
      final backgroundSyncScheduler = FulusBackgroundSyncScheduler();
      await backgroundSyncScheduler.initialize();

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

      final syncConfig = container.read(syncConfigProvider);
      // Reconcile the persisted setting with the OS scheduler on every app
      // launch, then keep WorkManager aligned with runtime toggle changes.
      await backgroundSyncScheduler.setEnabled(syncConfig.isEnabled);
      syncConfig.addListener(() {
        unawaited(
          backgroundSyncScheduler
              .setEnabled(syncConfig.isEnabled)
              .catchError((error, stackTrace) {
            unawaited(
              diagnosticLogger.captureError(
                error: error,
                stackTrace: stackTrace,
                severity: DiagnosticSeverity.warning,
                category: DiagnosticCategory.synchronization,
                component: 'WorkManager',
                operation: 'schedule',
                title: 'Background Cloud Sync scheduling failed',
              ),
            );
          }),
        );
      });

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
