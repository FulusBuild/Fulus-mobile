import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:drift/drift.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';

void main() {
  late AppDatabase db;
  late SyncQueue queue;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    queue = SyncQueue(db);
  });

  tearDown(() => db.close());

  test('coalesces duplicate entity operations', () async {
    final task = SyncTask.updateProduct('product-1');

    await queue.enqueue(task);
    await queue.enqueue(task);

    final rows = await db.select(db.syncQueueItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.entityType, 'product');
    expect(rows.single.entityLocalId, 'product-1');
    expect(rows.single.operation, 'update');
  });

  test('defers enqueue trigger until an outer transaction commits', () async {
    var callbackSawCommittedRow = false;
    queue.setOnEnqueued(() async {
      callbackSawCommittedRow =
          (await db.select(db.syncQueueItems).get()).isNotEmpty;
    });

    await db.transaction(() async {
      await queue.enqueue(SyncTask.createProduct('product-1'));
      expect(await db.select(db.syncQueueItems).get(), hasLength(1));
      expect(callbackSawCommittedRow, isFalse);
    });

    await Future<void>.delayed(Duration.zero);
    expect(callbackSawCommittedRow, isTrue);
  });

  test('seeds a pre-cloud archived customer for create-then-archive lifecycle', () async {
    final now = DateTime.now();
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        localId: 'archived-customer',
        name: 'Archived before cloud',
        createdAt: now,
        updatedAt: now,
        deletedAt: Value(now),
        syncStatus: SyncStatus.pending,
      ),
    );

    await queue.seedExistingBusinessData();

    final rows = await db.select(db.syncQueueItems).get();
    expect(
      rows.any((row) =>
          row.entityType == 'customer' &&
          row.entityLocalId == 'archived-customer' &&
          row.operation == 'create'),
      isTrue,
    );
  });

  test('keeps create and update operations distinct', () async {
    await queue.enqueue(SyncTask.createProduct('product-1'));
    await queue.enqueue(SyncTask.updateProduct('product-1'));

    final rows = await db.select(db.syncQueueItems).get();
    expect(rows, hasLength(2));
  });
}
