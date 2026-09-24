import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../app/bootstrap.dart';
import '../app/providers.dart';
import '../core/diagnostics/diagnostic_logger.dart';
import '../core/diagnostics/models/diagnostic_enums.dart';

const fulusBackgroundSyncUniqueName = 'fulus-cloud-sync';
const fulusBackgroundSyncTaskName = 'fulus.cloud.sync';

/// WorkManager entrypoint for Android background Cloud Sync.
///
/// This is deliberately a second runtime, not an always-open socket. Android
/// decides when the worker gets CPU time. The worker uses the same durable
/// outbox, authoritative pull cursor, recovery flow and sync engine as the
/// foreground runtime, while SQLite execution leasing prevents two runtimes
/// from mutating sync state concurrently.
@pragma('vm:entry-point')
void fulusBackgroundSyncCallback() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName != fulusBackgroundSyncTaskName) return true;

    WidgetsFlutterBinding.ensureInitialized();
    final preferences = await SharedPreferences.getInstance();
    final syncEnabled =
        preferences.getBool('fulus_sync_enabled') ?? false;
    if (!syncEnabled) return true;

    final diagnosticLogger = DiagnosticLogger();
    ProviderContainer? container;
    try {
      container = await bootstrap(diagnosticLogger: diagnosticLogger);
      final triggers = container.read(syncTriggersProvider);
      await triggers.syncNow();
      await triggers.waitForIdle();

      // A worker can legitimately wake while the account is signed out, no
      // business is selected, or readiness is waiting for user action. That is
      // not a worker failure. The foreground lifecycle will pick up when the
      // missing prerequisite becomes available.
      return true;
    } catch (error, stackTrace) {
      await diagnosticLogger.captureError(
          error: error,
          stackTrace: stackTrace,
          severity: DiagnosticSeverity.warning,
          category: DiagnosticCategory.synchronization,
          component: 'WorkManager',
          operation: 'backgroundSync',
        title: 'Background Cloud Sync attempt failed',
      );
      return false;
    } finally {
      final current = container;
      if (current != null) {
        final triggers = current.read(syncTriggersProvider);
        triggers.dispose();
        final db = current.read(databaseProvider);
        current.dispose();
        await db.close();
      }
    }
  });
}

/// Owns the Android WorkManager schedule.
///
/// The 15-minute cadence is the platform scheduling floor for periodic work on
/// Android in normal WorkManager usage. Foreground SyncTriggers remains much
/// more responsive (30 seconds + connectivity/resume/mutation triggers).
class FulusBackgroundSyncScheduler {
  FulusBackgroundSyncScheduler();

  bool _initialized = false;

  Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    await Workmanager().initialize(fulusBackgroundSyncCallback);
    _initialized = true;
  }

  Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return;
    if (!_initialized) {
      throw StateError('FulusBackgroundSyncScheduler is not initialized.');
    }

    if (!enabled) {
      await Workmanager().cancelByUniqueName(
        fulusBackgroundSyncUniqueName,
      );
      return;
    }

    await Workmanager().registerPeriodicTask(
      fulusBackgroundSyncUniqueName,
      fulusBackgroundSyncTaskName,
      frequency: const Duration(minutes: 15),
      constraints: const Constraints(
        networkType: NetworkType.connected,
      ),
      existingPeriodicWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 1),
      tag: 'fulus-cloud-sync',
    );
  }
}
