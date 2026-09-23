import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/sync_engine.dart';
import 'package:fulus_mobile/sync/sync_handler.dart';

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
      // before the client received a successful completion and removed the
      // outbox row.
      throw Exception('connection lost after remote commit');
    }

    final firstEngine = SyncEngine(
      db: db,
      handlersByEntityType: {
        'widget': _FunctionHandler(deliver),
      },
    );
    await firstEngine.runOnce();

    expect(remoteMutationCount, 1);
    expect(await db.select(db.syncQueueItems).get(), hasLength(1));

    // A new SyncEngine instance represents an app restart. The durable row
    // survived, so the same operation is delivered again.
    final secondEngine = SyncEngine(
      db: db,
      handlersByEntityType: {
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
