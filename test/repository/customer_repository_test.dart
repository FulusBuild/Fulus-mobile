import 'package:fulus_mobile/data/local/database/database.dart';
import 'package:fulus_mobile/data/local/database/tables.dart';
import 'package:fulus_mobile/data/repositories/customer_repository_impl.dart';
import 'package:fulus_mobile/domain/entities/customer.dart';
import 'package:fulus_mobile/domain/entities/auth_user.dart';
import 'package:fulus_mobile/sync/sync_queue.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SyncQueue syncQueue;
  late CustomerRepositoryImpl repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.locations).insert(LocationsCompanion.insert(
      localId: 'location-1',
      name: 'Test Location',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      syncStatus: SyncStatus.settled,
    ));
    await db.into(db.users).insert(
      UsersCompanion.insert(
        localId: 'owner-user',
        fullName: 'Owner',
        role: AuthRole.owner,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await db.into(db.sessions).insert(
      SessionsCompanion.insert(
        id: 'current',
        userId: 'owner-user',
        activeLocationId: const Value('location-1'),
      ),
    );
    syncQueue = SyncQueue(db);
    repository = CustomerRepositoryImpl(db: db, syncQueue: syncQueue);
  });

  tearDown(() async {
    await db.close();
  });

  group('createCustomer', () {
    test('writes the customer locally with zero starting balance', () async {
      final result = await repository.createCustomer(
        const CustomerDraft(name: 'Chidinma Okafor', locationId: 'location-1', phone: '+2348012345678'),
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
        const CustomerDraft(name: 'Walk-in Customer', locationId: 'location-1'),
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
      await repository.createCustomer(const CustomerDraft(name: 'Zainab', locationId: 'location-1'));
      await repository.createCustomer(const CustomerDraft(name: 'Amina', locationId: 'location-1'));

      final emitted = await repository.watchCustomers().first;

      expect(emitted.map((c) => c.name), ['Amina', 'Zainab']);
    });
  });

  group('getCustomerById', () {
    test('returns the matching customer', () async {
      final created = await repository.createCustomer(
        const CustomerDraft(name: 'Test Customer', locationId: 'location-1'),
      );

      final fetched = await repository.getCustomerById(created.localId);

      expect(fetched?.localId, created.localId);
    });

    test('returns null for an id that was never created', () async {
      final fetched = await repository.getCustomerById('does-not-exist');
      expect(fetched, isNull);
    });
  });

  group('location isolation', () {
    test('customer reads are scoped to the active location while outbox lookup remains available', () async {
      final now = DateTime.utc(2026, 10, 9, 10);
      await db.batch((batch) {
        batch.insertAll(db.locations, [
          LocationsCompanion.insert(
            localId: 'location-a',
            name: 'Location A',
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
          LocationsCompanion.insert(
            localId: 'location-b',
            name: 'Location B',
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
        ]);
      });
      await (db.update(db.sessions)..where((session) => session.id.equals('current')))
          .write(const SessionsCompanion(activeLocationId: Value('location-a')));
      await db.batch((batch) {
        batch.insertAll(db.customers, [
          CustomersCompanion.insert(
            localId: 'customer-a',
            locationId: const Value('location-a'),
            name: 'Customer A',
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.settled,
          ),
          CustomersCompanion.insert(
            localId: 'customer-b',
            locationId: const Value('location-b'),
            name: 'Customer B',
            createdAt: now,
            updatedAt: now,
            syncStatus: SyncStatus.pending,
          ),
        ]);
      });

      final visible = await repository.watchCustomers().first;
      expect(visible.map((customer) => customer.localId), ['customer-a']);
      expect(await repository.getCustomerById('customer-b'), isNull);
      expect(
        (await repository.getCustomerById('customer-b', forSync: true))?.localId,
        'customer-b',
      );
    });
  });

  group('markSynced', () {
    test('sets serverId and syncStatus on the local row', () async {
      final created = await repository.createCustomer(
        const CustomerDraft(name: 'Test Customer', locationId: 'location-1'),
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
