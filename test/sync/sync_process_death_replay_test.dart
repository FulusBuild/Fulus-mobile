import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/retry_policy.dart';
import 'package:fulus_mobile/sync/sync_handler.dart';
import 'package:fulus_mobile/sync/sync_config.dart';
import 'package:fulus_mobile/sync/sync_status_notifier.dart';
import 'package:fulus_mobile/sync/sync_triggers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockConnectivity extends Mock implements Connectivity {}
class _MockSyncStatusNotifier extends Mock implements SyncStatusNotifier {}

/// Models the important crash boundary:
/// the remote mutation commits, but the process dies before SyncEngine can
/// remove the durable outbox row. A fresh engine must safely retry the same
/// operation. In production the server-side operation id/idempotency key is
/// what makes the second delivery a replay rather than a second mutation.
void main() {
  test('a committed remote operation remains retryable after process death', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);

    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'operation-1',
        entityType: 'widget',
        entityLocalId: 'local-1',
        operation: 'create',
        priority: 0,
        enqueuedAt: DateTime(2026, 9, 23, 12),
      ),
    );

    var remoteMutationCount = 0;
    var firstDelivery = true;

    Future<void> deliver(SyncQueueItem item) async {
      // The remote side commits exactly once, keyed by the durable queue id.
      if (!firstDelivery) {
        return;
      }
      firstDelivery = false;
      remoteMutationCount++;
      // Simulate process death/network loss after the server committed but
      // before     // Use a zero-delay retry policy only to make the restart test deterministic.
    // Production uses the normal capped backoff; the property under test here
    // is that a fresh app instance automatically discovers durable work without
    // requiring a manual "Sync Now" action once that work is eligible.
    final secondEngine = SyncEngine(
      db: db,
      retryPolicy: const RetryPolicy(baseDelay: Duration.zero),
      handlersByEntityType: {
        'widget': _FunctionHandler((item) async {
          // Server idempotency recognizes operation-1 as already committed.
          await deliver(item);
        }),
      },
    );

    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'fulus_sync_enabled': true,
    });
    final config = await SyncConfig.load();
    final connectivity = _MockConnectivity();
    final statusNotifier = _MockSyncStatusNotifier();
    when(() => connectivity.checkConnectivity())
        .thenAnswer((_) async => [ConnectivityResult.wifi]);
    when(() => connectivity.onConnectivityChanged)
        .thenAnswer((_) => const Stream.empty());
    when(() => statusNotifier.checkForStuckSyncAndNotify())
        .thenAnswer((_) async {});

    // A fresh SyncTriggers instance represents app restart. start() must
    // discover and drain the durable outbox automatically. No manual run is
    // invoked here.
    final triggers = SyncTriggers(
      syncEngine: secondEngine,
      syncConfig: config,
      syncStatusNotifier: statusNotifier,
      connectivity: connectivity,
      isReady: () async => true,
    );
    await triggers.start();

    expect(remoteMutationCount, 1);
    expect(await db.select(db.syncQueueItems).get(), isEmpty);
    triggers.dispose();ByEntityType: {
        'widget': _FunctionHandler((item) async {
          // Server idempotency recognizes operation-1 as already committed.
          await deliver(item);
        }),
      },
    );

    // The first failure records backoff. A real restart does not bypass that
    // safety window automatically, so use a manual run to model the recovery
    // trigger that explicitly retries durable pending work.
    await secondEngine.runOnce(manual: true);

    expect(remoteMutationCount, 1);
    expect(await db.select(db.syncQueueItems).get(), isEmpty);
  });
}

class _FunctionHandler implements SyncHandler {
  _FunctionHandler(this._run);

  final Future<void> Function(SyncQueueItem item) _run;

  @override
  Future<void> sync(SyncQueueItem item) => _run(item);
}
