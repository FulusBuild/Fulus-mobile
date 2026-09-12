import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
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

  test('keeps create and update operations distinct', () async {
    await queue.enqueue(SyncTask.createProduct('product-1'));
    await queue.enqueue(SyncTask.updateProduct('product-1'));

    final rows = await db.select(db.syncQueueItems).get();
    expect(rows, hasLength(2));
  });
}
