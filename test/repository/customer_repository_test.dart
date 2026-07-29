import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncQueue syncQueue;
  late CustomerRepositoryImpl repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncQueue = SyncQueue(db);
    repository = CustomerRepositoryImpl(db: db, syncQueue: syncQueue);
  });

  tearDown(() async {
    await db.close();
  });

  group('createCustomer', () {
    test('writes the customer locally with zero starting balance', () async {
      final result = await repository.createCustomer(
        const CustomerDraft(name: 'Chidinma Okafor', phone: '+2348012345678'),
      );

      expect(result.name, 'Chidinma Okafor');
      expect(result.outstandingBalance, 0);

      final rows = await db.select(db.customers).get();
      expect(rows, hasLength(1));
      expect(rows.single.name, 'Chidinma Okafor');
      expect(rows.single.syncStatus, SyncStatus.pending);
    });

    test('enqueues a stock-and-customer-priority sync task', () async {
      final result = await repository.createCustomer(
        const CustomerDraft(name: 'Walk-in Customer'),
      );

      final queued = await db.select(db.syncQueueItems).get();
      expect(queued, hasLength(1));
      expect(queued.single.entityType, 'customer');
      expect(queued.single.operation, 'create');
      expect(queued.single.entityLocalId, result.localId);
      expect(queued.single.priority, SyncPriority.stockAndCustomerWrites);
    });
  });

  group('watchCustomers', () {
    test('emits created customers ordered by name', () async {
      await repository.createCustomer(const CustomerDraft(name: 'Zainab'));
      await repository.createCustomer(const CustomerDraft(name: 'Amina'));

      final emitted = await repository.watchCustomers().first;

      expect(emitted.map((c) => c.name), ['Amina', 'Zainab']);
    });
  });

  group('getCustomerById', () {
    test('returns the matching customer', () async {
      final created = await repository.createCustomer(
        const CustomerDraft(name: 'Test Customer'),
      );

      final fetched = await repository.getCustomerById(created.localId);

      expect(fetched?.localId, created.localId);
    });

    test('returns null for an id that was never created', () async {
      final fetched = await repository.getCustomerById('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('markSynced', () {
    test('sets serverId and syncStatus on the local row', () async {
      final created = await repository.createCustomer(
        const CustomerDraft(name: 'Test Customer'),
      );

      await repository.markSynced(localId: created.localId, serverId: 'server-1');

      final row = await (db.select(db.customers)
            ..where((c) => c.localId.equals(created.localId)))
          .getSingle();
      expect(row.serverId, 'server-1');
      expect(row.syncStatus, SyncStatus.settled);
    });
  });
}
