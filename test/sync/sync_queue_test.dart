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

  test('replaces duplicate update operations with a fresh queue identity', () async {
    final task = SyncTask.updateProduct('product-1');

    await queue.enqueue(task);
    final first = (await db.select(db.syncQueueItems).get()).single;
    await queue.enqueue(task);

    final rows = await db.select(db.syncQueueItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, isNot(first.id));
    expect(rows.single.entityType, 'product');
    expect(rows.single.entityLocalId, 'product-1');
    expect(rows.single.operation, 'update');
  });

  test('normalizes legacy dependency priorities before automatic drain', () async {
    await queue.enqueue(SyncTask.createProduct('product-1'));
    await queue.enqueue(SyncTask.createSale('sale-1'));

    await (db.update(db.syncQueueItems)
          ..where((q) => q.entityType.equals('product')))
        .write(const SyncQueueItemsCompanion(priority: Value(99)));
    await (db.update(db.syncQueueItems)
          ..where((q) => q.entityType.equals('sale')))
        .write(const SyncQueueItemsCompanion(priority: Value(99)));

    await queue.normalizeDependencyPriorities();

    final rows = await db.select(db.syncQueueItems).get();
    final product = rows.singleWhere((row) => row.entityType == 'product');
    final sale = rows.singleWhere((row) => row.entityType == 'sale');

    expect(product.priority, SyncPriority.stockAndCustomerWrites);
    expect(sale.priority, SyncPriority.salesAndPayments);
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

  test('does not reseed an entity that already has a server identity', () async {
    final now = DateTime.now();
    await db.into(db.products).insert(
      ProductsCompanion.insert(
        localId: 'already-synced-product',
        serverId: const Value('server-product-1'),
        name: 'Already synced product',
        sku: 'SYNC-1',
        costPrice: 100,
        sellingPrice: 150,
        createdAt: now,
        updatedAt: now,
        syncStatus: SyncStatus.synced,
      ),
    );

    await queue.seedExistingBusinessData();

    final rows = await db.select(db.syncQueueItems).get();
    expect(
      rows.where(
        (row) =>
            row.entityType == 'product' &&
            row.entityLocalId == 'already-synced-product',
      ),
      isEmpty,
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
  test('concurrent enqueue calls deduplicate the same mutation', () async {
    await Future.wait([
      queue.enqueue(SyncTask.createProduct('product-concurrent')),
      queue.enqueue(SyncTask.createProduct('product-concurrent')),
    ]);

    final rows = await db.select(db.syncQueueItems).get();
    expect(rows, hasLength(1));
    expect(rows.single.entityType, 'product');
    expect(rows.single.entityLocalId, 'product-concurrent');
    expect(rows.single.operation, 'create');
  });

}
