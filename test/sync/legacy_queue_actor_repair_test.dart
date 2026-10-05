import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/sync/legacy_queue_actor_repair.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import '../helpers/db_seed_helpers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('repairs a legacy sale queue row from the sale actor', () async {
    await seedUser(db, localId: 'employee-a');
    await seedSale(db, localId: 'sale-1', cashierUserId: 'employee-a');
    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'legacy-operation',
        entityType: 'sale',
        entityLocalId: 'sale-1',
        operation: 'create',
        priority: SyncPriority.salesAndPayments,
        enqueuedAt: DateTime(2026, 1, 1),
      ),
    );

    await LegacyQueueActorRepair(db).repair();

    final row = (await db.select(db.syncQueueItems).get()).single;
    expect(row.actorUserId, 'employee-a');
  });

  test('uses current actor only when legacy entity data cannot provide one', () async {
    await db.into(db.syncQueueItems).insert(
      SyncQueueItemsCompanion.insert(
        id: 'legacy-operation',
        entityType: 'unknown',
        entityLocalId: 'unknown-1',
        operation: 'create',
        priority: SyncPriority.stockAndCustomerWrites,
        enqueuedAt: DateTime(2026, 1, 1),
      ),
    );

    await LegacyQueueActorRepair(
      db,
      actorUserIdProvider: () => 'employee-current',
    ).repair();

    final row = (await db.select(db.syncQueueItems).get()).single;
    expect(row.actorUserId, 'employee-current');
  });
}
