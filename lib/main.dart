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

      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      final logicalSize = view.physicalSize / view.devicePixelRatio;
      final isTablet = logicalSize.shortestSide >= kTabletBreakpoint;
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

      // Orientation is a platform preference, not a prerequisite for the
      // local-first first frame. Apply it after runApp so the platform call
      // cannot extend the startup gate.
      if (!isTablet) {
        unawaited(
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]),
        );
      }

      // Cloud Sync is deliberately started only after the Flutter tree exists.
      // Its network/session reconciliation must never hold the first frame.
      unawaited(
        container.read(syncServiceProvider).bootstrap().catchError(
          (Object error, StackTrace stackTrace) {
            unawaited(
              diagnosticLogger.captureError(
                error: error,
                stackTrace: stackTrace,
                severity: DiagnosticSeverity.error,
                category: DiagnosticCategory.synchronization,
                component: 'SyncService',
                operation: 'bootstrap',
                title: 'Cloud Sync startup failed',
              ),
            );
          },
        ),
      );

      // WorkManager is the OS-level safety net for Cloud Sync when Android
      // suspends or terminates the Flutter process. It is deliberately
      // initialized after the first Flutter frame: scheduler registration is
      // infrastructure, not a prerequisite for rendering the local-first
      // workspace. A scheduler failure must never prevent the app from
      // becoming interactive.
      final backgroundSyncScheduler = FulusBackgroundSyncScheduler();
      unawaited(() async {
        try {
          await backgroundSyncScheduler.initialize();

          final syncConfig = container.read(syncConfigProvider);
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
        } catch (error, stackTrace) {
          unawaited(
            diagnosticLogger.captureError(
              error: error,
              stackTrace: stackTrace,
              severity: DiagnosticSeverity.warning,
              category: DiagnosticCategory.synchronization,
              component: 'WorkManager',
              operation: 'initialize',
              title: 'Background Cloud Sync scheduler initialization failed',
            ),
          );
        }
      }());
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
