import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
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

  test('seeds only repayment ledger entries because credit/refund entries are server-derived', () async {
    final now = DateTime.now();
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        localId: 'ledger-customer',
        name: 'Ledger customer',
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      ),
    );

    Future<void> insertLedger(String localId, String entryType) async {
      await db.into(db.customerLedgerEntries).insert(
        CustomerLedgerEntriesCompanion.insert(
          localId: localId,
          customerLocalId: 'ledger-customer',
          entryType: entryType,
          amount: 100,
          createdAt: now,
          updatedAt: now,
          syncStatus: SyncStatus.pending,
        ),
      );
    }

    await insertLedger('credit-sale-ledger', 'creditSale');
    await insertLedger('repayment-ledger', 'repayment');
    await insertLedger('refund-ledger', 'refundAdjustment');

    await queue.seedExistingBusinessData();

    final rows = await db.select(db.syncQueueItems).get();
    expect(
      rows.where((row) => row.entityType == 'customer_ledger').map((row) => row.entityLocalId),
      ['repayment-ledger'],
    );
  });

  test('does not duplicate a seed task already enqueued by a local mutation', () async {
    final now = DateTime.now();
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        localId: 'seeded-product',
        name: 'Seeded product',
        sku: 'SEED-1',
        costPrice: 100,
        sellingPrice: 150,
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.pending,
      ),
    );
    await queue.enqueue(SyncTask.createProduct('seeded-product'));

    await queue.seedExistingBusinessData();

    final rows = await db.select(db.syncQueueItems).get();
    final matching = rows.where(
      (row) =>
          row.entityType == 'product' &&
          row.entityLocalId == 'seeded-product' &&
          row.operation == 'create',
    );
    expect(matching, hasLength(1));
  });

  test('a newer mutation can replace a blocked outbox row', () async {
    await queue.enqueue(SyncTask.updateCustomer('customer-1'));
    final old = (await db.select(db.syncQueueItems).get()).single;
    await (db.update(db.syncQueueItems)..where((q) => q.id.equals(old.id))).write(
      const SyncQueueItemsCompanion(lastError: Value('[BLOCKED] stale conflict')),
    );
    await db.into(db.syncConflictRecords).insert(
      SyncConflictRecordsCompanion.insert(
        id: old.id + ':conflict',
        operationId: old.id,
        entityType: 'customer',
        entityLocalId: 'customer-1',
        message: 'stale conflict',
        createdAt: DateTime.now(),
      ),
    );

    await queue.enqueue(SyncTask.updateCustomer('customer-1'));

    final rows = await db.select(db.syncQueueItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, isNot(old.id));
    expect(rows.single.lastError, isNull);

    final conflict = (await db.select(db.syncConflictRecords).get()).single;
    expect(conflict.resolvedAt, isNotNull);
    expect(conflict.resolution, 'superseded_by_newer_local_mutation');
  });

  test('keeps create and update operations distinct', () async {
    await queue.enqueue(SyncTask.createProduct('product-1'));
    await queue.enqueue(SyncTask.updateProduct('product-1'));

    final rows = await db.select(db.syncQueueItems).get();
    expect(rows, hasLength(2));
  });
}
